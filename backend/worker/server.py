"""Run exclusively behind Cloud Run IAM; only queue and scheduler SAs may invoke."""
from __future__ import annotations

import os
from functools import lru_cache

from flask import Flask, jsonify, request
from werkzeug.exceptions import HTTPException

from cloud import Accounts, Objects, Repository
from core import SafeError, validate_task
from crypto import Envelope
from provider import Gemini
from service import Worker

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 4096


@lru_cache(maxsize=1)
def worker():
    project = os.environ["GCLOUD_PROJECT"]
    return Worker(Repository(project), Objects(project, os.environ["VOICE_BUCKET"], os.environ["OUTPUT_BUCKET"]),
                  Envelope(os.environ["KMS_KEY_NAME"]), Gemini(project), Accounts(project))


@app.post("/tasks")
def tasks():
    try:
        payload = request.get_json(silent=True)
        validate_task(payload)
        raw_retry = request.headers.get("X-CloudTasks-TaskRetryCount", "0")
        retry_count = int(raw_retry) if raw_retry.isdigit() and len(raw_retry) <= 4 else 0
        result = worker().handle(payload, retry_count=retry_count)
        return jsonify(result), 200
    except HTTPException as error:
        return jsonify({"errorCode": "invalid_task"}), error.code or 400
    except SafeError as error:
        # Error codes contain no provider payloads, manuscript, or identity.
        app.logger.warning("voice_task_code=%s", error.code)
        return jsonify({"errorCode": error.code}), 503 if error.retryable else 200
    except Exception:
        # Do not emit exception strings/tracebacks: SDK exceptions can include sensitive URLs/bodies.
        app.logger.error("voice_task_code=internal_retry")
        return jsonify({"errorCode": "internal_retry"}), 503


@app.post("/cleanup")
def cleanup():
    try:
        worker().cleanup()
        return jsonify({"status": "complete"}), 200
    except Exception:
        app.logger.error("voice_cleanup_code=internal_retry")
        return jsonify({"errorCode": "internal_retry"}), 503


@app.get("/health")
def health():
    return jsonify({"status": "ok"}), 200
