import importlib.util
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from core import SafeError
from diagnostics import task_key


@unittest.skipUnless(importlib.util.find_spec("flask"), "Install worker requirements for HTTP adapter checks")
class ServerTests(unittest.TestCase):
    def setUp(self):
        import server
        self.server = server
        self.client = server.app.test_client()
    def test_health_does_not_initialize_cloud_clients(self):
        with patch.object(self.server, "worker", side_effect=AssertionError("Unexpected ADC initialization")):
            response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json, {"status": "ok"})
    def test_task_only_accepts_reference_and_provider_retry_code(self):
        with patch.object(self.server, "worker") as factory:
            factory.return_value.handle.side_effect = SafeError("provider_quota", retryable=True)
            with self.assertLogs(self.server.app.logger, level="WARNING") as captured:
                response = self.client.post("/tasks", json={"kind": "narrate", "uid": "alice", "id": "job"},
                                            headers={"X-CloudTasks-TaskRetryCount": "7"})
        self.assertEqual(response.status_code, 503)
        factory.return_value.handle.assert_called_once_with({"kind": "narrate", "uid": "alice", "id": "job"}, retry_count=7)
        self.assertIn("provider_quota", " ".join(captured.output))
    def test_exception_identity_and_stack_are_logged_without_private_values(self):
        with patch.object(self.server, "worker") as factory:
            factory.return_value.handle.side_effect = RuntimeError("raw-parent-recording-or-secret")
            with self.assertLogs(self.server.app.logger, level="ERROR") as captured:
                response = self.client.post("/tasks", json={"kind": "narrate", "uid": "alice", "id": "job"})
        self.assertEqual(response.status_code, 503)
        self.assertNotIn("raw-parent-recording-or-secret", " ".join(captured.output))
        self.assertEqual(len(captured.records), 1)
        details = json.loads(captured.records[0].getMessage())
        self.assertEqual(details["error"]["causes"][0]["type"], "RuntimeError")
        self.assertTrue(details["error"]["causes"][0]["frames"])
        self.assertEqual(details["task_key"], task_key("narrate", "alice", "job"))
        self.assertNotIn("alice", captured.records[0].getMessage())
        self.assertEqual(response.json, {"errorCode": "internal_retry"})
    def test_permanent_failed_task_is_acknowledged(self):
        with patch.object(self.server, "worker") as factory:
            factory.return_value.handle.side_effect = SafeError("ownership_mismatch")
            with self.assertLogs(self.server.app.logger, level="WARNING"):
                response = self.client.post("/tasks", json={"kind": "narrate", "uid": "alice", "id": "job"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json, {"errorCode": "ownership_mismatch"})
    def test_bounded_task_body(self):
        with patch.object(self.server, "worker") as factory:
            response = self.client.post("/tasks", data=b"x" * 5000, content_type="application/json")
        # Werkzeug rejects oversized payloads before decoding them.
        self.assertEqual(response.status_code, 413)
        factory.assert_not_called()


if __name__ == "__main__":
    unittest.main()
