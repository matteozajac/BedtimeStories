"""OAuth-only Gemini Enterprise transport. No client keys or provider IDs are logged."""
from __future__ import annotations

import base64
import json
import time
from urllib.parse import quote

from core import MODEL, STYLES, SafeError, provider_identity, wav_pcm


class ProviderError(SafeError):
    def __init__(self, status: int, ambiguous: bool = False):
        codes = {400: "provider_rejected_recording_or_text", 401: "provider_configuration",
                 403: "provider_access_unavailable", 404: "provider_voice_missing",
                 429: "provider_quota", 500: "provider_unavailable", 502: "provider_unavailable",
                 503: "provider_unavailable", 504: "provider_unavailable"}
        super().__init__(codes.get(status, "provider_failed"), status in {429, 500, 502, 503, 504})
        self.status, self.ambiguous = status, ambiguous


class Gemini:
    def __init__(self, project: str, session=None, sleep=time.sleep):
        if session is None:
            import google.auth
            from google.auth.transport.requests import AuthorizedSession
            credentials, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
            session = AuthorizedSession(credentials)
        self.session, self.sleep = session, sleep
        escaped = quote(project, safe="")
        self.voices = f"https://aiplatform.googleapis.com/v1beta1/projects/{escaped}/locations/global/voices"
        self.generate_url = f"https://aiplatform.googleapis.com/v1/projects/{escaped}/locations/global/publishers/google/models/{MODEL}:generateContent"

    def _request(self, method: str, url: str, *, retry=True, **kwargs) -> dict:
        for attempt in range(4 if retry else 1):
            try:
                response = self.session.request(method, url, timeout=(10, 180), **kwargs)
            except Exception as error:
                # A timed-out create may have committed. Never retry it blindly.
                if retry and attempt < 3:
                    self.sleep(2 ** attempt)
                    continue
                raise ProviderError(503, ambiguous=method == "POST") from error
            if 200 <= response.status_code < 300:
                if response.status_code == 204 or not response.content:
                    return {}
                try:
                    result = response.json()
                    if not isinstance(result, dict):
                        raise ValueError()
                    return result
                except (ValueError, json.JSONDecodeError) as error:
                    raise SafeError("invalid_provider_response") from error
            if retry and response.status_code in {429, 500, 502, 503, 504} and attempt < 3:
                self.sleep(2 ** attempt)
                continue
            raise ProviderError(response.status_code, ambiguous=method == "POST" and response.status_code >= 500)
        raise ProviderError(503)

    def create_voice(self, reference: bytes, consent: bytes, marker: str) -> str:
        wav_pcm(reference, 10, 30)
        wav_pcm(consent, 2, 60)
        result = self._request("POST", self.voices, retry=False, json={
            "store": True,
            "voice": {"type": "VOICE_TYPE_REPLICATED", "displayName": marker,
                      "replicated": {
                          "sourceAudio": {"mimeType": "audio/wav", "data": base64.b64encode(reference).decode()},
                          "consentAudio": {"mimeType": "audio/wav", "data": base64.b64encode(consent).decode()},
                      }},
        })
        return provider_identity(result.get("id"))

    def find_voices(self, marker: str) -> list[str]:
        result, page_token = [], None
        for _ in range(200):
            parameters = {"type": "replicated", "search": marker, "pageSize": 50}
            if page_token:
                parameters["pageToken"] = page_token
            page = self._request("GET", self.voices, params=parameters)
            for voice in page.get("voices", []):
                if voice.get("displayName", voice.get("display_name")) == marker:
                    result.append(provider_identity(voice.get("id")))
            page_token = page.get("nextPageToken", page.get("next_page_token"))
            if not page_token:
                return result
        raise SafeError("voice_reconciliation_incomplete", retryable=True)

    def get_voice(self, voice: str) -> dict | None:
        try:
            return self._request("GET", self.voices + "/" + provider_identity(voice))
        except ProviderError as error:
            if error.status == 404:
                return None
            raise

    def delete_voice(self, voice: str) -> None:
        try:
            self._request("DELETE", self.voices + "/" + provider_identity(voice))
        except ProviderError as error:
            if error.status != 404:
                raise

    def generate(self, voice: str, text: str, style: str) -> bytes:
        if style not in STYLES:
            raise SafeError("invalid_style")
        response = self._request("POST", self.generate_url, json={
            "contents": [{"role": "user", "parts": [{"text": text, "speechMetadata": {"style": STYLES[style]}}]}],
            "generationConfig": {"responseModalities": ["AUDIO"],
                                 "speechConfig": {"voiceConfig": {"voice": provider_identity(voice)}}},
        })
        candidates = response.get("candidates", [])
        if not candidates or candidates[0].get("finishReason") not in {None, "STOP"}:
            raise SafeError("provider_incomplete_audio")
        clips = []
        for part in candidates[0].get("content", {}).get("parts", []):
            inline = part.get("inlineData")
            if inline:
                if inline.get("mimeType", "").split(";")[0] not in {"audio/wav", "audio/x-wav"}:
                    raise SafeError("provider_audio_format")
                try:
                    data = base64.b64decode(inline.get("data", ""), validate=True)
                except (ValueError, TypeError) as error:
                    raise SafeError("invalid_provider_audio") from error
                wav_pcm(data)
                clips.append(data)
        if len(clips) != 1:
            raise SafeError("provider_incomplete_audio")
        return clips[0]
