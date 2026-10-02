#!/usr/bin/env python3
"""Explicit live staging probe using a consenting adult's supplied recordings only."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "worker"))

from core import MODEL, SafeError, assemble_m4a, text_chunks, wav_pcm
from provider import Gemini


def private_write(path, data):
    descriptor = os.open(path, os.O_CREAT | os.O_TRUNC | os.O_WRONLY, 0o600)
    with os.fdopen(descriptor, "wb") as output:
        output.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    parser.add_argument("--reference-wav", type=Path, required=True)
    parser.add_argument("--consent-wav", type=Path, required=True)
    parser.add_argument("--text-file", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--impersonate-service-account")
    parser.add_argument("--speaker-consent-confirmed", action="store_true", required=True,
                        help="The adult speaker knowingly recorded the exact Google consent statement.")
    options = parser.parse_args()
    options.output_dir.mkdir(parents=True, mode=0o700, exist_ok=True)
    if options.output_dir.stat().st_mode & 0o077:
        parser.error("Use a private output directory with permissions 0700.")
    import google.auth
    from google.auth import impersonated_credentials
    from google.auth.transport.requests import AuthorizedSession
    credentials, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    if options.impersonate_service_account:
        credentials = impersonated_credentials.Credentials(source_credentials=credentials,
            target_principal=options.impersonate_service_account,
            target_scopes=["https://www.googleapis.com/auth/cloud-platform"], lifetime=900)
    provider = Gemini(options.project, AuthorizedSession(credentials))
    marker, created_voice = "bedtime-probe-" + uuid.uuid4().hex, None
    report = {"project": options.project, "model": MODEL, "startedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
              "create": False, "get": False, "generation": [], "deleteVerified": False,
              "quality": "Physical listening review is required; successful requests do not prove likeness or emotion quality."}
    attempted_create, status = False, 1
    try:
        reference, consent = options.reference_wav.read_bytes(), options.consent_wav.read_bytes()
        wav_pcm(reference, 10, 30)
        wav_pcm(consent, 2, 60)
        text = options.text_file.read_text(encoding="utf-8")
        chunks = text_chunks(text)
        if len(chunks) > 3:
            raise SafeError("probe_text_too_long")
        attempted_create = True
        created_voice = provider.create_voice(reference, consent, marker)
        report["create"] = True
        report["get"] = provider.get_voice(created_voice) is not None
        for style in ["gentle", "excited"]:
            audio, duration = assemble_m4a([provider.generate(created_voice, chunk, style) for chunk in chunks])
            private_write(options.output_dir / f"{style}.m4a", audio)
            report["generation"].append({"style": style, "duration": duration, "bytes": len(audio)})
        status = 0
    except SafeError as error:
        report["errorCode"] = error.code
    except OSError:
        report["errorCode"] = "input_or_output_file_unavailable"
    except Exception:
        report["errorCode"] = "probe_configuration_or_transport_failed"
    finally:
        try:
            voices = set(provider.find_voices(marker)) if attempted_create else set()
            if created_voice:
                voices.add(created_voice)
            for voice in voices:
                provider.delete_voice(voice)
                if provider.get_voice(voice) is not None:
                    raise SafeError("probe_deletion_unconfirmed")
            report["deleteVerified"] = bool(voices) or not attempted_create
            if attempted_create and not voices:
                report["cleanupErrorCode"] = "probe_creation_unconfirmed"
                status = 1
        except Exception:
            report["cleanupErrorCode"] = "probe_deletion_unconfirmed"
            status = 1
        private_write(options.output_dir / "report.json", json.dumps(report, indent=2).encode())
    print(json.dumps(report, indent=2))
    return status


if __name__ == "__main__":
    raise SystemExit(main())
