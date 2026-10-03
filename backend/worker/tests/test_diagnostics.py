import errno
import json
import logging
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from core import SafeError
from diagnostics import connection, error_snapshot, event, operation_context, task_key
from provider import Gemini, ProviderError
from service import Worker


class DiagnosticsTests(unittest.TestCase):
    def test_original_exception_causes_codes_and_frames_survive_without_values(self):
        secret = "private-story-token-recording"
        try:
            try:
                raise OSError(-errno.ECONNRESET, secret)
            except OSError as original:
                raise SafeError("provider_unavailable", retryable=True) from original
        except SafeError as error:
            details = error_snapshot(error)
        self.assertEqual([cause["type"] for cause in details["causes"]], ["SafeError", "OSError"])
        self.assertEqual(details["causes"][1]["errno"], -errno.ECONNRESET)
        self.assertTrue(details["causes"][0]["retryable"])
        self.assertTrue(all(cause["frames"] and cause["stack_origin"] == "exception" for cause in details["causes"]))
        serialized = json.dumps(details)
        self.assertNotIn(secret, serialized)
        self.assertNotIn(str(Path(__file__).parent), serialized)
        self.assertNotIn("raise OSError", serialized)
        self.assertEqual(set(details["causes"][0]["frames"][0]), {"file", "function", "line"})

    def test_cause_chain_is_bounded_and_cycle_safe(self):
        root = RuntimeError("secret")
        current = root
        for _ in range(10):
            next_error = ValueError("secret")
            current.__cause__ = next_error
            current = next_error
        details = error_snapshot(root)
        self.assertEqual(len(details["causes"]), 5)
        self.assertTrue(details["cause_chain_truncated"])
        current.__cause__ = root
        self.assertEqual(len(error_snapshot(root)["causes"]), 5)
        root.__cause__ = root
        self.assertEqual(len(error_snapshot(root)["causes"]), 1)

    def test_connection_preserves_error_and_phase_but_owner_reports_it_once(self):
        logger = logging.getLogger("diagnostics-test")
        original = RuntimeError("secret-response-and-token")
        with self.assertLogs(logger, "DEBUG") as captured:
            with operation_context(task_key=task_key("narrate", "alice", "job")):
                try:
                    with connection(logger, "gemini", "generate_audio"):
                        raise original
                except RuntimeError as error:
                    self.assertIs(error, original)
                    event(logger, logging.ERROR, "operation_failed", error=error)
        entries = [json.loads(record.getMessage()) for record in captured.records]
        self.assertEqual([entry["event"] for entry in entries], ["connection_started", "connection_failed", "operation_failed"])
        self.assertEqual([entry["severity"] for entry in entries], ["DEBUG", "DEBUG", "ERROR"])
        self.assertEqual(sum("error" in entry for entry in entries), 1)
        self.assertEqual(len({entry["operation_id"] for entry in entries}), 1)
        details = entries[-1]["error"]["causes"][0]
        self.assertEqual((details["connection"], details["phase"]), ("gemini", "generate_audio"))
        self.assertNotIn("secret-response-and-token", json.dumps(entries))
        self.assertNotIn("alice", json.dumps(entries))

    def test_diagnostic_context_does_not_leak_between_requests(self):
        logger = logging.getLogger("diagnostics-test")
        with self.assertLogs(logger, "DEBUG") as captured:
            with operation_context(task_key="first"):
                event(logger, logging.DEBUG, "first")
            event(logger, logging.DEBUG, "outside")
        entries = [json.loads(record.getMessage()) for record in captured.records]
        self.assertIn("operation_id", entries[0])
        self.assertNotIn("operation_id", entries[1])
        self.assertNotIn("task_key", entries[1])

    def test_task_key_matches_functions_queue_contract(self):
        self.assertEqual(task_key("narrate", "A", "job"), "be2ee9e0b465b7ce8f181c4a0930e921d715722103d392c5eaf9241830004a43")

    def test_firestore_stream_failure_retains_specific_scan_phase(self):
        original = OSError("private-database-response")
        class Query:
            def where(self, *args):
                return self
            def stream(self):
                raise original
        repo = SimpleNamespace(db=SimpleNamespace(collection_group=lambda _: Query()))
        objects = SimpleNamespace(cleanup_expired_objects=lambda: None)
        worker = Worker(repo, objects, None, None, None)
        with self.assertLogs("service", "DEBUG"):
            try:
                worker.cleanup()
            except OSError as error:
                self.assertIs(error, original)
                details = error_snapshot(error)
            else:
                self.fail("The original stream failure must propagate to the owner")
        self.assertEqual(details["causes"][0]["connection"], "firestore")
        self.assertEqual(details["causes"][0]["phase"], "scan_expired_jobs")
        self.assertNotIn("private-database-response", json.dumps(details))


class GeminiDiagnosticsTests(unittest.TestCase):
    def test_transport_retry_contains_throw_frames_and_same_correlation_without_payload(self):
        class Session:
            attempts = 0
            def request(self, method, url, **kwargs):
                self.attempts += 1
                if self.attempts == 1:
                    raise TimeoutError("token-and-provider-response-story")
                return type("Response", (), {"status_code": 204, "content": b""})()
        delays = []
        provider = Gemini("private-project", Session(), sleep=delays.append)
        with self.assertLogs("provider", "DEBUG") as captured:
            with operation_context(task_key=task_key("deleteVoice", "alice", "voice")):
                provider.delete_voice("voice_private")
        entries = [json.loads(record.getMessage()) for record in captured.records]
        retries = [entry for entry in entries if entry["event"] == "gemini_request_retry"]
        self.assertEqual(len(retries), 1)
        self.assertEqual(retries[0]["severity"], "WARNING")
        self.assertEqual(retries[0]["error"]["causes"][0]["type"], "TimeoutError")
        self.assertEqual(retries[0]["error"]["causes"][0]["stack_origin"], "exception")
        self.assertEqual(delays, [1])
        self.assertEqual(len({entry["operation_id"] for entry in entries}), 1)
        serialized = json.dumps(entries)
        for secret in ["token-and-provider-response-story", "private-project", "voice_private", "alice"]:
            self.assertNotIn(secret, serialized)

    def test_google_rpc_status_is_allowlisted_without_message_or_details(self):
        class Response:
            status_code, content = 403, b"ignored"
            def json(self):
                return {"error": {"status": "PERMISSION_DENIED", "message": "secret-key-and-story", "details": ["recording"]}}
        class Session:
            def request(self, *args, **kwargs):
                return Response()
        with self.assertRaises(ProviderError) as caught:
            Gemini("private-project", Session()).get_voice("voice_private")
        details = error_snapshot(caught.exception)
        self.assertEqual(details["causes"][0]["provider_status"], "PERMISSION_DENIED")
        self.assertEqual(details["causes"][0]["http_status"], 403)
        self.assertNotIn("secret-key-and-story", json.dumps(details))
        self.assertNotIn("recording", json.dumps(details))


if __name__ == "__main__":
    unittest.main()
