"""Structured diagnostics without exception messages, payloads, locals, or credentials."""
from __future__ import annotations

import contextvars
import functools
import hashlib
import json
import logging
import re
import time
import traceback
import uuid
from contextlib import contextmanager
from pathlib import Path

from core import SafeError

_CONTEXT = contextvars.ContextVar("voice_diagnostics", default={})
_NAME = re.compile(r"^[A-Za-z0-9_.<>-]{1,160}$")
_MAX_CAUSES, _MAX_FRAMES = 5, 24


def configure_logging():
    # Enable our audited events independently of noisy SDK/HTTP debug logging.
    for name in ("server", "service", "provider", "cloud", "crypto"):
        logger = logging.getLogger(name)
        logger.setLevel(logging.DEBUG)
        if not logger.handlers:
            handler = logging.StreamHandler()
            handler.setFormatter(logging.Formatter("%(message)s"))
            logger.addHandler(handler)
        logger.propagate = False


def task_key(kind, uid, item_id):
    # Matches the Functions Cloud Tasks name without exposing an account/item identity.
    return hashlib.sha256(f"{kind}:{uid}:{item_id}".encode()).hexdigest()


@contextmanager
def operation_context(**fields):
    token = _CONTEXT.set({**_CONTEXT.get(), "operation_id": uuid.uuid4().hex, **fields})
    try:
        yield
    finally:
        _CONTEXT.reset(token)


def update_context(**fields):
    _CONTEXT.set({**_CONTEXT.get(), **fields})


def _name(value):
    return value if isinstance(value, str) and _NAME.fullmatch(value) else "unknown"


def error_snapshot(error):
    """Keep original exception identities and throw frames, never str(error) or source lines."""
    causes, seen = [], set()
    current = error
    while isinstance(current, BaseException) and id(current) not in seen and len(causes) < _MAX_CAUSES:
        seen.add(id(current))
        frames = traceback.extract_tb(current.__traceback__) if current.__traceback__ else traceback.extract_stack()[:-1]
        item = {"type": _name(type(current).__name__), "module": _name(type(current).__module__),
                "stack_origin": "exception" if current.__traceback__ else "reporting",
                "frames": [{"file": _name(Path(frame.filename).name), "function": _name(frame.name), "line": frame.lineno}
                           for frame in frames[-_MAX_FRAMES:]]}
        if isinstance(current, SafeError):
            item.update({"code": current.code, "retryable": current.retryable})
        else:
            # Standard OS / RPC numeric codes are safe; arbitrary string properties are not.
            for field in ("errno", "code"):
                value = getattr(current, field, None)
                if isinstance(value, int) and not isinstance(value, bool):
                    item[field] = value
        status = getattr(current, "status", None)
        if isinstance(status, int) and 100 <= status <= 599:
            item["http_status"] = status
        # ProviderError sets this only from the fixed Google RPC status allowlist.
        provider_status = getattr(current, "provider_status", None)
        if isinstance(current, SafeError) and provider_status is not None:
            item["provider_status"] = provider_status
        ambiguous = getattr(current, "ambiguous", None)
        if isinstance(current, SafeError) and isinstance(ambiguous, bool):
            item["ambiguous"] = ambiguous
        phase = getattr(current, "_diagnostic_phase", None)
        if isinstance(phase, dict):
            item["connection"] = _name(phase.get("connection"))
            item["phase"] = _name(phase.get("phase"))
        causes.append(item)
        current = current.__cause__ or (None if current.__suppress_context__ else current.__context__)
    return {"causes": causes, "cause_chain_truncated": current is not None}


def event(logger, level, name, *, error=None, **fields):
    entry = {"event": name, "message": name, "severity": logging.getLevelName(level), **_CONTEXT.get(), **fields}
    if error is not None:
        entry["error"] = error_snapshot(error)
    logger.log(level, json.dumps(entry, separators=(",", ":"), sort_keys=True))


@contextmanager
def connection(logger, service, phase, **fields):
    started = time.monotonic()
    event(logger, logging.DEBUG, "connection_started", connection=service, phase=phase, **fields)
    try:
        yield
    except Exception as error:
        # The owner logs this error once; intermediate adapters supply context and progress.
        if not getattr(error, "_diagnostic_phase", None):
            try:
                error._diagnostic_phase = {"connection": service, "phase": phase}
            except (AttributeError, TypeError):
                pass
        event(logger, logging.DEBUG, "connection_failed", connection=service, phase=phase,
              elapsed_ms=round((time.monotonic() - started) * 1000), **fields)
        raise
    else:
        event(logger, logging.DEBUG, "connection_completed", connection=service, phase=phase,
              elapsed_ms=round((time.monotonic() - started) * 1000), **fields)


def observed(service, phase):
    """A fixed operation name deliberately excludes method arguments and returned data."""
    def decorate(function):
        @functools.wraps(function)
        def execute(*args, **kwargs):
            with connection(logging.getLogger(function.__module__), service, phase):
                return function(*args, **kwargs)
        return execute
    return decorate
