import base64
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from core import BUILT_IN_VOICES, SafeError, built_in_voice, provider_identity
from provider import Gemini
from test_worker import Response, Session, fixture, wav


def built_in_fixture(profile_id="builtin-pl-luna", language="pl-PL"):
    worker, repo, provider, objects, accounts = fixture()
    repo.put("privateAccounts/alice/jobs/job", {"voiceProfileId": profile_id, "language": language})
    repo.delete_tree("privateAccounts/alice/voices")
    repo.delete_tree("users/alice/voices")
    return worker, repo, provider, objects, accounts


class BuiltInVoiceTests(unittest.TestCase):
    def test_catalog_matches_callable_api_and_client_logical_ids(self):
        root = Path(__file__).resolve().parents[3]
        server = (root / "backend/functions/src/voice-catalog.ts").read_text()
        client = (root / "BedtimeStories/CloudNarration/VoiceProfile.swift").read_text()
        for profile_id, (language, provider) in BUILT_IN_VOICES.items():
            self.assertIn(f'"{profile_id}"', server)
            self.assertIn(f'"{profile_id}"', client)
            self.assertIn(f'language: "{language}", providerVoice: "{provider}"', server)
        for language in ("pl-PL", "en-US"):
            self.assertEqual(len({provider for lang, provider in BUILT_IN_VOICES.values() if lang == language}), 3)

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg unavailable")
    def test_each_language_narrates_without_creating_a_personal_voice(self):
        for profile_id, (language, expected) in BUILT_IN_VOICES.items():
            with self.subTest(profile=profile_id):
                worker, repo, provider, objects, _ = built_in_fixture(profile_id, language)
                self.assertEqual(worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})["status"], "complete")
                self.assertEqual(repo.get("users/alice/jobs/job")["state"], "ready")
                self.assertEqual(provider.generated[0][0], expected)
                self.assertEqual(provider.created, 0)
                self.assertTrue(objects.outputs)
                self.assertIsNone(repo.get(f"privateAccounts/alice/voices/{profile_id}"))

    def test_unknown_voice_and_wrong_language_never_reach_provider(self):
        for profile_id, language in [("builtin-pl-injected", "pl-PL"), ("builtin-en-luna", "pl-PL")]:
            worker, _, provider, _, _ = built_in_fixture(profile_id, language)
            with self.assertRaises(SafeError):
                worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})
            self.assertEqual(provider.generated, [])

    def test_builtin_still_requires_active_account_and_owned_job(self):
        for account_deleted in (True, False):
            worker, repo, provider, _, _ = built_in_fixture()
            if account_deleted:
                repo.put("privateAccounts/alice", {"state": "deleted"})
                self.assertEqual(worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})["status"], "cancelled")
            else:
                repo.put("privateAccounts/alice/jobs/job", {"uid": "bob"})
                with self.assertRaises(SafeError):
                    worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})
            self.assertEqual(provider.generated, [])

    def test_account_deletion_or_language_change_during_synthesis_prevents_publication(self):
        for mutation in ({"state": "deleted"}, {"language": "en-US"}):
            worker, repo, provider, objects, _ = built_in_fixture()
            path = "privateAccounts/alice" if "state" in mutation else "privateAccounts/alice/jobs/job"
            provider.hook = lambda: repo.put(path, mutation)
            try:
                worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})
            except SafeError:
                pass
            self.assertEqual(objects.outputs, {})
            self.assertNotEqual(repo.get("users/alice/jobs/job")["state"], "ready")

    def test_prebuilt_transport_preserves_text_and_uses_fixed_language_direction(self):
        response = Response(200, {"candidates": [{"finishReason": "STOP", "content": {"parts": [{"inlineData": {
            "mimeType": "audio/wav", "data": base64.b64encode(wav()).decode(),
        }}]}}]})
        session = Session([response])
        text = "Mały królik zasnął pod gwiazdami."
        self.assertEqual(Gemini("bedtime", session).generate("Sulafat", text, "gentle", "pl-PL"), wav())
        request = session.requests[0][2]["json"]
        self.assertEqual(request["generationConfig"]["speechConfig"]["voiceConfig"]["voice"], "Sulafat")
        self.assertEqual(request["contents"][0]["parts"][0]["text"], text)
        self.assertIn("fluent Polish", request["contents"][0]["parts"][0]["speechMetadata"]["style"])
        with self.assertRaises(SafeError):
            provider_identity("Sulafat")  # replication/delete/get remain custom-voice-only
        for value in ("Kore", "arbitrary", "builtin-pl-luna"):
            with self.assertRaises(SafeError):
                Gemini("bedtime", Session([])).generate(value, text, "gentle", "pl-PL")


if __name__ == "__main__":
    unittest.main()
