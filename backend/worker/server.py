"""Run exclusively behind Cloud Run IAM; only queue and scheduler SAs may invoke."""
from __future__ import annotations

import os
import logging
import time
from functools import lru_cache

from flask import Flask, jsonify, request
from werkzeug.exceptions import HTTPException

from cloud import Accounts, Objects, Repository
from core import SafeError, validate_task
from crypto import Envelope
from provider import Gemini
from service import Worker
from diagnostics import configure_logging, event, operation_context, task_key, update_context

configure_logging()
app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 4096


@lru_cache(maxsize=1)
def worker():
    project = os.environ["GCLOUD_PROJECT"]
    return Worker(Repository(project), Objects(project, os.environ["VOICE_BUCKET"], os.environ["OUTPUT_BUCKET"]),
                  Envelope(os.environ["KMS_KEY_NAME"]), Gemini(project), Accounts(project))


@app.post("/tasks")
def tasks():
    with operation_context(route="tasks"):
        started = time.monotonic()
        event(app.logger, logging.DEBUG, "voice_task_started")
        try:
            payload = request.get_json(silent=True)
            kind, uid, item_id = validate_task(payload)
            raw_retry = request.headers.get("X-CloudTasks-TaskRetryCount", "0")
            retry_count = int(raw_retry) if raw_retry.isdigit() and len(raw_retry) <= 4 else 0
            update_context(task_kind=kind, task_key=task_key(kind, uid, item_id), queue_retry_count=retry_count)
            result = worker().handle(payload, retry_count=retry_count)
            event(app.logger, logging.INFO, "voice_task_completed", status=result["status"],
                  elapsed_ms=round((time.monotonic() - started) * 1000))
            return jsonify(result), 200
        except HTTPException as error:
            event(app.logger, logging.WARNING, "voice_task_rejected", error=error, code="invalid_task")
            return jsonify({"errorCode": "invalid_task"}), error.code or 400
        except SafeError as error:
            event(app.logger, logging.WARNING if error.retryable else logging.ERROR, "voice_task_failed", error=error,
                  code=error.code, elapsed_ms=round((time.monotonic() - started) * 1000))
            return jsonify({"errorCode": error.code}), 503 if error.retryable else 200
        except Exception as error:
            event(app.logger, logging.ERROR, "voice_task_failed", error=error, code="internal_retry",
                  elapsed_ms=round((time.monotonic() - started) * 1000))
            return jsonify({"errorCode": "internal_retry"}), 503


@app.post("/cleanup")
def cleanup():
    with operation_context(route="cleanup"):
        started = time.monotonic()
        event(app.logger, logging.DEBUG, "voice_cleanup_started")
        try:
            worker().cleanup()
            event(app.logger, logging.INFO, "voice_cleanup_completed", elapsed_ms=round((time.monotonic() - started) * 1000))
            return jsonify({"status": "complete"}), 200
        except Exception as error:
            event(app.logger, logging.ERROR, "voice_cleanup_failed", error=error, code="internal_retry",
                  elapsed_ms=round((time.monotonic() - started) * 1000))
            return jsonify({"errorCode": "internal_retry"}), 503


@app.get("/health")
def health():
    return jsonify({"status": "ok"}), 200
