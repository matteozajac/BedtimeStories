"""Pure validation and audio assembly; no cloud credentials required for tests."""
from __future__ import annotations

import hashlib
import io
import json
import re
import subprocess
import tempfile
import wave
from pathlib import Path
from typing import Iterable

MODEL = "gemini-3.8-flash-tts"
IDENTIFIER = re.compile(r"^[A-Za-z0-9_-]{1,128}$")
PROVIDER_IDENTIFIER = re.compile(r"^voice_[A-Za-z0-9_-]{1,256}$")
STYLES = {
    "natural": "natural, warm conversational storytelling, unhurried",
    "gentle": "gentle, calm bedtime storytelling, soft and unhurried",
    "curious": "curious, lightly playful storytelling, warm and clear",
    "excited": "excited, joyful storytelling, expressive but comfortable volume",
    "reassuring": "reassuring, warm and comforting, measured pace",
    "whispered": "softly whispered, intimate bedtime storytelling, clear pronunciation",
}
MAX_WAV_BYTES = 24_000 * 2 * 360 + 4096
MAX_CHUNK_WORDS = 200
MAX_CHUNK_CHARS = 2400


class SafeError(Exception):
    """Only its non-sensitive code may be exposed to clients or logs."""
    def __init__(self, code: str, retryable: bool = False):
        super().__init__(code)
        self.code, self.retryable = code, retryable


class Stopped(SafeError):
    def __init__(self):
        super().__init__("cancelled")


def identity(value: object) -> str:
    if not isinstance(value, str) or not IDENTIFIER.fullmatch(value):
        raise SafeError("invalid_identifier")
    return value


def provider_identity(value: object) -> str:
    if not isinstance(value, str) or not PROVIDER_IDENTIFIER.fullmatch(value):
        raise SafeError("invalid_provider_voice")
    return value


def validate_task(payload: object) -> tuple[str, str, str]:
    if not isinstance(payload, dict) or set(payload) != {"kind", "uid", "id"}:
        raise SafeError("invalid_task")
    kind = payload["kind"]
    if kind not in {"enroll", "narrate", "deleteVoice", "deleteAccount"}:
        raise SafeError("invalid_task")
    uid, item_id = identity(payload["uid"]), identity(payload["id"])
    if kind == "deleteAccount" and item_id != uid:
        raise SafeError("invalid_task")
    return kind, uid, item_id


def assert_owner(document: dict | None, uid: str, item_id: str, id_field: str) -> dict:
    if not document or document.get("uid") != uid or document.get(id_field) != item_id:
        raise SafeError("ownership_mismatch")
    return document


def canonical_aad(uid: str, voice_id: str, kind: str) -> bytes:
    identity(uid)
    identity(voice_id)
    return json.dumps({"version": 1, "uid": uid, "voiceId": voice_id, "kind": kind},
                      ensure_ascii=False, separators=(",", ":")).encode()


def wav_pcm(data: bytes, minimum: float = 0.01, maximum: float = 360) -> tuple[bytes, float]:
    """Validate full PCM WAV payload, including truncation and unsupported formats."""
    if len(data) > MAX_WAV_BYTES or not data.startswith(b"RIFF"):
        raise SafeError("invalid_audio")
    try:
        with wave.open(io.BytesIO(data), "rb") as audio:
            if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate(), audio.getcomptype()) != (1, 2, 24000, "NONE"):
                raise SafeError("invalid_audio")
            frames = audio.getnframes()
            duration = frames / 24000
            if not minimum <= duration <= maximum:
                raise SafeError("invalid_audio_duration")
            pcm = audio.readframes(frames)
            if len(pcm) != frames * 2:
                raise SafeError("truncated_audio")
            return pcm, duration
    except (wave.Error, EOFError, ValueError, OSError) as error:
        raise SafeError("invalid_audio") from error


def pcm_wav(pcm: bytes) -> bytes:
    if len(pcm) % 2 or not pcm:
        raise SafeError("invalid_audio")
    output = io.BytesIO()
    with wave.open(output, "wb") as audio:
        audio.setparams((1, 2, 24000, 0, "NONE", "not compressed"))
        audio.writeframes(pcm)
    return output.getvalue()


def text_chunks(text: str) -> list[str]:
    """Preserve all supplied characters; prefer sentence, then whitespace boundaries."""
    if not isinstance(text, str) or not text.strip():
        raise SafeError("empty_text")
    chunks, remaining = [], text
    while remaining:
        if len(remaining) <= MAX_CHUNK_CHARS and len(remaining.split()) <= MAX_CHUNK_WORDS:
            chunks.append(remaining)
            break
        words = list(re.finditer(r"\S+", remaining))
        bound = min(MAX_CHUNK_CHARS, words[MAX_CHUNK_WORDS].start() if len(words) > MAX_CHUNK_WORDS else len(remaining))
        sentence = list(re.finditer(r"[.!?…][\"'”’)]*\s+", remaining[:bound]))
        if sentence:
            split = sentence[-1].end()
        else:
            whitespace = list(re.finditer(r"\s+", remaining[:bound]))
            split = whitespace[-1].end() if whitespace else bound
        # Include a hard-broken character sequence only when a single word exceeds the cap.
        chunks.append(remaining[:split])
        remaining = remaining[split:]
    return chunks


def chapter_chunks(chapter: dict) -> list[dict]:
    if not isinstance(chapter, dict):
        raise SafeError("invalid_snapshot")
    identity(chapter.get("id"))
    paragraphs = chapter.get("paragraphs")
    if not isinstance(paragraphs, list) or not paragraphs:
        raise SafeError("invalid_snapshot")
    result = []
    for paragraph in paragraphs:
        if not isinstance(paragraph, dict):
            raise SafeError("invalid_snapshot")
        style = paragraph.get("style", "gentle")
        if style not in STYLES:
            raise SafeError("invalid_style")
        for text in text_chunks(paragraph.get("text")):
            result.append({"text": text, "style": style})
    return result


def chunk_hash(chunk: dict) -> str:
    return hashlib.sha256(json.dumps(chunk, ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def assemble_m4a(clips: Iterable[bytes]) -> tuple[bytes, float]:
    """Decode RIFF containers first; never concatenate WAV headers."""
    duration = 0.0
    with tempfile.TemporaryDirectory(prefix="bedtime-audio-") as directory:
        pcm_file = Path(directory) / "chapter.pcm"
        with pcm_file.open("wb") as output:
            for clip in clips:
                pcm, seconds = wav_pcm(clip)
                output.write(pcm)
                duration += seconds
                if duration > 7200:
                    raise SafeError("chapter_too_long")
        if duration == 0:
            raise SafeError("empty_audio")
        destination = Path(directory) / "chapter.m4a"
        command = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-f", "s16le",
                   "-ar", "24000", "-ac", "1", "-i", str(pcm_file), "-c:a", "aac", "-b:a", "64k",
                   "-movflags", "+faststart", "-y", str(destination)]
        try:
            subprocess.run(command, capture_output=True, check=True, timeout=120)
            result = destination.read_bytes()
            probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0",
                                    "-show_entries", "stream=codec_name,sample_rate,channels",
                                    "-of", "json", str(destination)], capture_output=True, check=True, timeout=30)
            streams = json.loads(probe.stdout).get("streams", [])
            if len(streams) != 1 or streams[0] != {"codec_name": "aac", "sample_rate": "24000", "channels": 1} or not result:
                raise SafeError("encoding_failed")
        except (subprocess.SubprocessError, OSError, ValueError) as error:
            raise SafeError("encoding_failed") from error
    return result, duration
