"""OAuth-only Gemini Enterprise transport. No client keys or provider IDs are logged."""
from __future__ import annotations

import base64
import json
import logging
import time
from urllib.parse import quote

from core import MODEL, STYLES, SafeError, provider_identity, synthesis_voice, wav_pcm
from diagnostics import connection, event, observed

LOGGER = logging.getLogger(__name__)
PROVIDER_STATUSES = {"INVALID_ARGUMENT", "UNAUTHENTICATED", "PERMISSION_DENIED", "NOT_FOUND",
                     "RESOURCE_EXHAUSTED", "FAILED_PRECONDITION", "ABORTED", "OUT_OF_RANGE",
                     "UNIMPLEMENTED", "INTERNAL", "UNAVAILABLE", "DATA_LOSS", "DEADLINE_EXCEEDED",
                     "CANCELLED", "ALREADY_EXISTS", "UNKNOWN"}


class ProviderError(SafeError):
    def __init__(self, status: int, ambiguous: bool = False, provider_status: str | None = None):
        codes = {400: "provider_rejected_recording_or_text", 401: "provider_configuration",
                 403: "provider_access_unavailable", 404: "provider_voice_missing",
                 429: "provider_quota", 500: "provider_unavailable", 502: "provider_unavailable",
                 503: "provider_unavailable", 504: "provider_unavailable"}
        super().__init__(codes.get(status, "provider_failed"), status in {429, 500, 502, 503, 504})
        self.status, self.ambiguous = status, ambiguous
        self.provider_status = provider_status if provider_status in PROVIDER_STATUSES else None


class Gemini:
    @observed("gemini", "initialize_oauth_session")
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

    def _request(self, method: str, url: str, *, operation: str, retry=True, **kwargs) -> dict:
        for attempt in range(4 if retry else 1):
            started = time.monotonic()
            fields = {"connection": "gemini", "phase": operation, "method": method, "attempt": attempt + 1,
                      "model": MODEL if operation == "generate_audio" else "voices", "retry_allowed": retry}
            event(LOGGER, logging.DEBUG, "gemini_request_started", **fields)
            try:
                with connection(LOGGER, "gemini", operation, attempt=attempt + 1):
                    response = self.session.request(method, url, timeout=(10, 180), **kwargs)
            except Exception as error:
                # A timed-out create may have committed. Never retry it blindly.
                if retry and attempt < 3:
                    event(LOGGER, logging.WARNING, "gemini_request_retry", error=error,
                          elapsed_ms=round((time.monotonic() - started) * 1000), retry_delay_seconds=2 ** attempt, **fields)
                    self.sleep(2 ** attempt)
                    continue
                raise ProviderError(503, ambiguous=method == "POST") from error
            event(LOGGER, logging.DEBUG, "gemini_response_received", http_status=response.status_code,
                  elapsed_ms=round((time.monotonic() - started) * 1000), **fields)
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
            provider_status = None
            try:
                payload = response.json()
                candidate = payload.get("error", {}).get("status") if isinstance(payload, dict) and isinstance(payload.get("error"), dict) else None
                if isinstance(candidate, str) and candidate in PROVIDER_STATUSES:
                    provider_status = candidate
            except (ValueError, TypeError, json.JSONDecodeError):
                event(LOGGER, logging.DEBUG, "gemini_error_body_unavailable", http_status=response.status_code, **fields)
            if retry and response.status_code in {429, 500, 502, 503, 504} and attempt < 3:
                event(LOGGER, logging.WARNING, "gemini_request_retry", http_status=response.status_code,
                      provider_status=provider_status, retry_delay_seconds=2 ** attempt, **fields)
                self.sleep(2 ** attempt)
                continue
            raise ProviderError(response.status_code, ambiguous=method == "POST" and response.status_code >= 500,
                                provider_status=provider_status)
        raise ProviderError(503)

    @observed("gemini", "create_voice")
    def create_voice(self, reference: bytes, consent: bytes, marker: str) -> str:
        wav_pcm(reference, 10, 30)
        wav_pcm(consent, 2, 60)
        result = self._request("POST", self.voices, operation="create_voice", retry=False, json={
            "store": True,
            "voice": {"type": "VOICE_TYPE_REPLICATED", "displayName": marker,
                      "replicated": {
                          "sourceAudio": {"mimeType": "audio/wav", "data": base64.b64encode(reference).decode()},
                          "consentAudio": {"mimeType": "audio/wav", "data": base64.b64encode(consent).decode()},
                      }},
        })
        return provider_identity(result.get("id"))

    @observed("gemini", "find_voices")
    def find_voices(self, marker: str) -> list[str]:
        result, page_token = [], None
        for page_index in range(200):
            parameters = {"type": "replicated", "search": marker, "pageSize": 50}
            if page_token:
                parameters["pageToken"] = page_token
            event(LOGGER, logging.DEBUG, "gemini_voice_reconciliation_page", page=page_index + 1)
            page = self._request("GET", self.voices, operation="find_voices", params=parameters)
            for voice in page.get("voices", []):
                if voice.get("displayName", voice.get("display_name")) == marker:
                    result.append(provider_identity(voice.get("id")))
            page_token = page.get("nextPageToken", page.get("next_page_token"))
            if not page_token:
                return result
        raise SafeError("voice_reconciliation_incomplete", retryable=True)

    @observed("gemini", "get_voice")
    def get_voice(self, voice: str) -> dict | None:
        try:
            return self._request("GET", self.voices + "/" + provider_identity(voice), operation="get_voice")
        except ProviderError as error:
            if error.status == 404:
                event(LOGGER, logging.WARNING, "gemini_voice_missing", error=error, phase="get_voice", recovery="reconcile_or_renew")
                return None
            raise

    @observed("gemini", "delete_voice")
    def delete_voice(self, voice: str) -> None:
        try:
            self._request("DELETE", self.voices + "/" + provider_identity(voice), operation="delete_voice")
        except ProviderError as error:
            if error.status != 404:
                raise
            event(LOGGER, logging.DEBUG, "gemini_voice_delete_already_complete", http_status=404)

    @observed("gemini", "generate_audio")
    def generate(self, voice: str, text: str, style: str, language: str | None = None) -> bytes:
        if style not in STYLES:
            raise SafeError("invalid_style")
        direction = STYLES[style]
        if language is not None:
            if language not in {"en-US", "pl-PL"}:
                raise SafeError("invalid_voice_language")
            direction += "; " + ("fluent Polish with natural Polish pronunciation" if language == "pl-PL" else "fluent English with natural American English pronunciation")
        response = self._request("POST", self.generate_url, operation="generate_audio", json={
            "contents": [{"role": "user", "parts": [{"text": text, "speechMetadata": {"style": direction}}]}],
            "generationConfig": {"responseModalities": ["AUDIO"],
                                 "speechConfig": {"voiceConfig": {"voice": synthesis_voice(voice)}}},
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
        event(LOGGER, logging.DEBUG, "gemini_audio_validated", audio_bytes=len(clips[0]), phase="generate_audio")
        return clips[0]
