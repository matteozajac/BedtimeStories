import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).resolve().parents[1] / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


prepare = module("prepare", "prepare_functions_env.py")
registration = module("registration", "register_output_bucket.py")


def environment():
    project = "gen-lang-client-0154884984"
    return {"PROJECT_ID": project, "ENABLE_CLOUD_NARRATION": "false", "API_SERVICE_ACCOUNT": f"voice-api@{project}.iam.gserviceaccount.com",
            "VOICE_BUCKET": project + "-voices", "OUTPUT_BUCKET": project + "-audio", "KMS_KEY_NAME": f"projects/{project}/locations/europe-west1/keyRings/voices/cryptoKeys/envelopes",
            "TASK_LOCATION": "europe-west1", "TASK_QUEUE": "bedtime-voice-worker", "TASK_SERVICE_ACCOUNT": f"voice-queue@{project}.iam.gserviceaccount.com",
            "WORKER_URL": "https://bedtime-voice-worker-example.europe-west1.run.app"}


class EnvironmentTests(unittest.TestCase):
    def invoke(self, env):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            source = path / "outputs.json"
            source.write_text(json.dumps({"functions_environment": {"value": env}}))
            with patch.object(sys, "argv", ["prepare", "--outputs-json", str(source), "--functions-dir", str(path)]), contextlib.redirect_stdout(io.StringIO()):
                prepare.main()
            return (path / ".env.gen-lang-client-0154884984").read_text()
    def test_safe_identifiers_keep_feature_disabled(self):
        text = self.invoke(environment())
        self.assertIn("ENABLE_CLOUD_NARRATION=false\n", text)
        self.assertNotIn("GCLOUD_PROJECT", text)
        self.assertNotIn("API_KEY", text)
    def test_reject_secrets_foreign_owner_or_noncanonical_url(self):
        for key, value in [("ENABLE_CLOUD_NARRATION", "true"), ("SECRET_KEY", "secret"),
                           ("VOICE_BUCKET", "foreign-audio"), ("WORKER_URL", "https://evil.example/tasks"),
                           ("WORKER_URL", "https://worker.run.app/tasks"), ("TASK_SERVICE_ACCOUNT", "another@project.iam.gserviceaccount.com")]:
            env = environment()
            env[key] = value
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                self.invoke(env)


class Response:
    def __init__(self, status, body):
        self.status_code, self.body = status, body
    def json(self):
        return self.body


class Session:
    def __init__(self, responses):
        self.responses, self.calls = list(responses), []
    def get(self, url, **kwargs):
        self.calls.append(("GET", url))
        return self.responses.pop(0)
    def post(self, url, **kwargs):
        self.calls.append(("POST", url))
        return self.responses.pop(0)


@unittest.skipUnless(importlib.util.find_spec("google.auth"), "Install worker requirements for ADC adapter checks")
class RegistrationTests(unittest.TestCase):
    def invoke(self, session, extra=None):
        arguments = ["register", "--project", "gen-lang-client-0154884984", "--bucket", "gen-lang-client-0154884984-audio", *(extra or [])]
        with patch.object(sys, "argv", arguments), patch("google.auth.default", return_value=(object(), "project")), \
             patch("google.auth.transport.requests.AuthorizedSession", return_value=session), contextlib.redirect_stdout(io.StringIO()):
            return registration.main()
    def test_readback_mode_never_posts(self):
        session = Session([Response(200, {"projectNumber": "123"}), Response(200, {"projectNumber": "123"}), Response(404, {})])
        self.assertEqual(self.invoke(session), 1)
        self.assertTrue(all(method == "GET" for method, _ in session.calls))
    def test_foreign_bucket_denied_before_firebase_registration(self):
        session = Session([Response(200, {"projectNumber": "123"}), Response(200, {"projectNumber": "456"})])
        self.assertEqual(self.invoke(session, ["--register"]), 1)
        self.assertEqual(len(session.calls), 2)
    def test_explicit_register_then_readback(self):
        session = Session([Response(200, {"projectNumber": "123"}), Response(200, {"projectNumber": "123"}),
                           Response(404, {}), Response(200, {}), Response(200, {})])
        self.assertEqual(self.invoke(session, ["--register"]), 0)
        self.assertTrue(session.calls[3][1].endswith(":addFirebase"))
        self.assertEqual(session.calls[4][0], "GET")
    def test_cli_config_targets_exact_registered_bucket_and_keeps_paths(self):
        session = Session([Response(200, {"projectNumber": "123"}), Response(200, {"projectNumber": "123"}), Response(200, {})])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "backend/infra").mkdir(parents=True)
            (root / "firebase.json").write_text(json.dumps({"functions": [{"source": "backend/functions"}], "storage": {"rules": "backend/storage.rules"}}))
            with patch.object(registration, "__file__", str(root / "backend/infra/register_output_bucket.py")), patch.object(registration.subprocess, "run") as command:
                self.assertEqual(self.invoke(session, ["--configure-cli"]), 0)
            generated = json.loads((root / ".env.firebase.gen-lang-client-0154884984.json").read_text())
            self.assertEqual(generated["storage"], [{"target": "cloud-audio", "rules": "backend/storage.rules"}])
            self.assertEqual(generated["functions"], [{"source": "backend/functions"}])
            self.assertIn("gen-lang-client-0154884984-audio", command.call_args.args[0])
            self.assertEqual(command.call_args.kwargs["cwd"], root.resolve())


if __name__ == "__main__":
    unittest.main()
