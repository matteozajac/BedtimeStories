import base64
import copy
import datetime as dt
import io
import json
import shutil
import sys
import unittest
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from cloud import now
from core import (MODEL, SafeError, assemble_m4a, canonical_aad, chapter_chunks,
                  pcm_wav, text_chunks, validate_task, wav_pcm)
from crypto import Envelope
from provider import Gemini, ProviderError
from service import Worker


def wav(seconds=1):
    return pcm_wav(b"\x10\x00" * int(24000 * seconds))


class FakeKMS:
    def encrypt(self, request):
        return type("Result", (), {"ciphertext": b"wrapped:" + request["plaintext"]})()
    def decrypt(self, request):
        return type("Result", (), {"plaintext": request["ciphertext"][8:]})()


class Repo:
    def __init__(self, docs):
        self.docs = copy.deepcopy(docs)
    def get(self, path):
        return copy.deepcopy(self.docs.get(path))
    def put(self, path, values):
        self.docs.setdefault(path, {}).update(copy.deepcopy(values))
    def atomic(self, paths, operation):
        writes, result = operation({path: self.get(path) for path in paths})
        for path, values in writes.items():
            if values is None:
                self.docs.pop(path, None)
            else:
                self.put(path, values)
        return result
    def collection(self, path):
        return [(key.split("/")[-1], self.get(key)) for key in list(self.docs) if key.startswith(path + "/") and len(key.split("/")) == len(path.split("/")) + 1]
    def delete_tree(self, path):
        for key in list(self.docs):
            if key == path or key.startswith(path + "/"):
                self.docs.pop(key)
    def clear_children(self, path):
        for key in list(self.docs):
            if key.startswith(path + "/"):
                self.docs.pop(key)


class Objects:
    voice_bucket = "private-recordings"
    def __init__(self, envelope):
        self.envelope, self.chunks, self.outputs, self.raw = envelope, {}, {}, {}
        self.output_calls = 0
    def read_envelope(self, uid, voice_id, kind, supplied_path):
        if supplied_path != f"enrollments/{uid}/{voice_id}/{kind}.json":
            raise SafeError("invalid_recording_path")
        return self.envelope.encrypt(wav(12 if kind == "reference" else 8), uid, voice_id, kind)
    def read_checkpoint(self, uid, job_id, chapter_id, index):
        return self.chunks.get((uid, job_id, chapter_id, index))
    def checkpoint(self, uid, job_id, chapter_id, index, clip):
        self.chunks[uid, job_id, chapter_id, index] = clip
    def output(self, uid, job_id, chapter_id, audio, expires_at):
        self.output_calls += 1
        path = f"users/{uid}/jobs/{job_id}/{chapter_id}.m4a"
        self.outputs[path] = audio
        return path
    def delete_prefix(self, bucket, prefix):
        if prefix.startswith("chunks/"):
            _, uid, job_id, _ = prefix.split("/")
            self.chunks = {key: value for key, value in self.chunks.items() if key[:2] != (uid, job_id)}
    def delete_job(self, uid, job_id):
        self.delete_prefix(self.voice_bucket, f"chunks/{uid}/{job_id}/")
        self.outputs = {path: value for path, value in self.outputs.items() if not path.startswith(f"users/{uid}/jobs/{job_id}/")}
    def delete_recordings(self, uid, voice_id):
        self.raw.pop((uid, voice_id), None)
    def delete_account(self, uid):
        self.outputs = {path: value for path, value in self.outputs.items() if not path.startswith(f"users/{uid}/")}
        self.raw = {key: value for key, value in self.raw.items() if key[0] != uid}
        self.chunks = {key: value for key, value in self.chunks.items() if key[0] != uid}
    def recording_enrollments(self):
        return list(self.raw)


class Provider:
    def __init__(self):
        self.voices, self.generated, self.created, self.deleted = {}, [], 0, []
        self.hook = None
        self.ambiguous = False
    def find_voices(self, marker):
        return [voice for voice, name in self.voices.items() if name == marker]
    def create_voice(self, reference, consent, marker):
        self.created += 1
        voice = "voice_" + str(self.created)
        self.voices[voice] = marker
        if self.hook:
            self.hook()
        if self.ambiguous:
            self.ambiguous = False
            raise ProviderError(503, ambiguous=True)
        return voice
    def get_voice(self, voice):
        return {"id": voice} if voice in self.voices else None
    def generate(self, voice, text, style, language=None):
        self.generated.append((voice, text, style))
        if self.hook:
            self.hook()
        return wav(0.1)
    def delete_voice(self, voice):
        self.voices.pop(voice, None)
        self.deleted.append(voice)


class Accounts:
    def __init__(self):
        self.deleted = []
    def delete(self, uid):
        self.deleted.append(uid)


def fixture(status="ready", text="One small rabbit found the moon.", preview=False):
    envelope = Envelope("projects/test/locations/europe-west1/keyRings/voice/cryptoKeys/voice", FakeKMS())
    voice = {"uid": "alice", "voiceId": "voice-profile", "status": status, "retentionAccepted": True,
             "consentVersion": "2026-10-01", "providerVoice": envelope.encrypt(b"voice_initial", "alice", "voice-profile", "providerVoice"),
             "referenceObject": "enrollments/alice/voice-profile/reference.json", "consentObject": "enrollments/alice/voice-profile/consent.json"}
    job = {"uid": "alice", "jobId": "job", "voiceProfileId": "voice-profile", "state": "queued", "preview": preview,
           "expiresAt": now() + dt.timedelta(days=30), "chapters": [{"id": "chapter", "title": "Moon", "paragraphs": [{"text": text, "style": "gentle"}]}]}
    docs = {"privateAccounts/alice": {"state": "active"}, "privateAccounts/alice/voices/voice-profile": voice,
            "users/alice/voices/voice-profile": {"uid": "alice", "status": status},
            "privateAccounts/alice/jobs/job": job, "users/alice/jobs/job": {"uid": "alice", "state": "queued"}}
    repo, provider, objects, accounts = Repo(docs), Provider(), Objects(envelope), Accounts()
    provider.voices["voice_initial"] = "original"
    return Worker(repo, objects, envelope, provider, accounts), repo, provider, objects, accounts


class ValidationTests(unittest.TestCase):
    def test_chunks_preserve_exact_text_with_polish_and_whitespace(self):
        text = ("Mały królik spał.\n\nMama szeptała: „Dobranoc”. " * 300) + "🦊" * 5000
        chunks = text_chunks(text)
        self.assertEqual("".join(chunks), text)
        self.assertTrue(all(len(chunk) <= 2400 and len(chunk.split()) <= 200 for chunk in chunks))
    def test_invalid_task_and_owner_paths(self):
        for payload in [{"kind": "narrate", "uid": "alice/../bob", "id": "job"},
                        {"kind": "deleteAccount", "uid": "alice", "id": "bob"},
                        {"kind": "narrate", "uid": "alice", "id": "job", "path": "other"}]:
            with self.assertRaises(SafeError):
                validate_task(payload)
    def test_audio_bounds_format_and_truncation(self):
        self.assertEqual(wav_pcm(wav(12), 10, 30)[1], 12)
        with self.assertRaises(SafeError):
            wav_pcm(wav(9), 10, 30)
        with self.assertRaises(SafeError):
            wav_pcm(wav()[:-4])
        buffer = io.BytesIO()
        with wave.open(buffer, "wb") as audio:
            audio.setparams((2, 2, 24000, 0, "NONE", "not compressed"))
            audio.writeframes(b"\x00" * 24000 * 4)
        with self.assertRaises(SafeError):
            wav_pcm(buffer.getvalue())
    def test_style_allowlist(self):
        with self.assertRaises(SafeError):
            chapter_chunks({"id": "x", "paragraphs": [{"text": "Hi", "style": "read arbitrary instructions"}]})
    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg unavailable")
    def test_joined_m4a_duration_is_sum_of_decoded_frames(self):
        result, duration = assemble_m4a([wav(0.1), wav(0.2)])
        self.assertAlmostEqual(duration, 0.3)
        self.assertIn(b"ftyp", result[:40])


class EncryptionTests(unittest.TestCase):
    def test_exact_typescript_aad_and_bound_owner(self):
        self.assertEqual(canonical_aad("alice", "v1", "reference"), b'{"version":1,"uid":"alice","voiceId":"v1","kind":"reference"}')
        envelope = Envelope("key", FakeKMS())
        encrypted = envelope.encrypt(b"parent audio", "alice", "v1", "reference")
        self.assertEqual(envelope.decrypt(encrypted, "alice", "v1", "reference"), b"parent audio")
        for uid, profile, kind in [("bob", "v1", "reference"), ("alice", "v2", "reference"), ("alice", "v1", "consent")]:
            with self.assertRaises(SafeError):
                envelope.decrypt(encrypted, uid, profile, kind)
        corrupt = dict(encrypted, ciphertext=base64.b64encode(b"\x00" * 40).decode())
        with self.assertRaises(SafeError):
            envelope.decrypt(corrupt, "alice", "v1", "reference")


class WorkerTests(unittest.TestCase):
    def test_foreign_job_denied_before_provider_call(self):
        worker, repo, provider, _, _ = fixture()
        repo.docs["privateAccounts/alice/jobs/job"]["uid"] = "bob"
        with self.assertRaises(SafeError) as error:
            worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})
        self.assertEqual(error.exception.code, "ownership_mismatch")
        self.assertEqual(provider.generated, [])
    def test_foreign_voice_reference_denied_before_provider_call(self):
        worker, repo, provider, _, _ = fixture()
        repo.docs["privateAccounts/alice/voices/voice-profile"]["uid"] = "bob"
        with self.assertRaises(SafeError):
            worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})
        self.assertEqual(provider.generated, [])
    def test_full_narration_requires_voice_approval(self):
        worker, repo, provider, _, _ = fixture(status="awaitingApproval")
        self.assertEqual(worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})["status"], "cancelled")
        self.assertEqual(provider.generated, [])
    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg unavailable")
    def test_preview_before_approval_and_delivery_idempotency(self):
        worker, repo, provider, objects, _ = fixture(status="awaitingApproval", preview=True)
        worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})
        self.assertEqual(repo.get("users/alice/jobs/job")["state"], "ready")
        self.assertEqual(repo.get("privateAccounts/alice/jobs/job")["chapters"], [])
        self.assertEqual(objects.chunks, {})
        worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})
        self.assertEqual(len(provider.generated), 1)
    def test_cancellation_after_provider_response_cannot_publish(self):
        worker, repo, provider, objects, _ = fixture()
        provider.hook = lambda: repo.put("privateAccounts/alice/jobs/job", {"cancelRequested": True, "state": "cancelled"})
        worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})
        self.assertEqual(objects.output_calls, 0)
        self.assertEqual(objects.chunks, {})
        self.assertEqual(repo.get("users/alice/jobs/job")["state"], "cancelled")
    def test_account_deletion_during_clone_deletes_provider_result(self):
        worker, repo, provider, _, _ = fixture(status="processing")
        repo.put("privateAccounts/alice/voices/voice-profile", {"providerVoice": None})
        provider.hook = lambda: repo.put("privateAccounts/alice", {"state": "deleting"})
        worker.handle({"kind": "enroll", "uid": "alice", "id": "voice-profile"})
        self.assertEqual(provider.deleted, ["voice_1"])
        self.assertEqual(repo.get("users/alice/voices/voice-profile")["status"], "processing")
    def test_uncertain_create_is_reconciled_without_duplicate(self):
        worker, repo, provider, _, _ = fixture(status="processing")
        repo.put("privateAccounts/alice/voices/voice-profile", {"providerVoice": None})
        provider.ambiguous = True
        with self.assertRaises(ProviderError):
            worker.handle({"kind": "enroll", "uid": "alice", "id": "voice-profile"})
        worker.handle({"kind": "enroll", "uid": "alice", "id": "voice-profile"})
        self.assertEqual(provider.created, 1)
        self.assertEqual(repo.get("users/alice/voices/voice-profile")["status"], "awaitingApproval")
    def test_absent_uncertain_create_fails_closed(self):
        worker, repo, provider, _, _ = fixture(status="processing")
        repo.put("privateAccounts/alice/voices/voice-profile", {"providerVoice": None, "creationAttemptStarted": now(), "providerMarker": "unknown"})
        with self.assertRaises(SafeError) as error:
            worker.handle({"kind": "enroll", "uid": "alice", "id": "voice-profile"})
        self.assertEqual(error.exception.code, "voice_creation_unconfirmed")
        self.assertEqual(provider.created, 0)
    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg unavailable")
    def test_expired_voice_renewal_keeps_approval(self):
        worker, repo, provider, _, _ = fixture()
        provider.voices.clear()
        worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})
        self.assertEqual(provider.created, 1)
        self.assertEqual(repo.get("users/alice/voices/voice-profile")["status"], "ready")
    def test_existing_lease_prevents_duplicate_generation(self):
        worker, repo, provider, _, _ = fixture()
        repo.put("privateAccounts/alice/jobs/job", {"leaseToken": "other", "leaseUntil": now() + dt.timedelta(minutes=10)})
        with self.assertRaises(SafeError) as error:
            worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})
        self.assertTrue(error.exception.retryable)
        self.assertEqual(provider.generated, [])
    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg unavailable")
    def test_resume_uses_completed_chunk_checkpoint(self):
        worker, repo, provider, objects, _ = fixture(text="A rabbit saw the moon. " * 150)
        clock = [0]
        worker.monotonic = lambda: clock[0]
        provider.hook = lambda: clock.__setitem__(0, clock[0] + 700)
        with self.assertRaises(SafeError) as error:
            worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})
        self.assertEqual(error.exception.code, "job_continuing")
        self.assertEqual(len(provider.generated), 1)
        provider.hook = None
        worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})
        expected = len(text_chunks("A rabbit saw the moon. " * 150))
        self.assertEqual(len(provider.generated), expected)
        self.assertEqual(repo.get("users/alice/jobs/job")["state"], "ready")
    def test_account_deletion_preserves_tombstone_erases_data(self):
        worker, repo, provider, objects, accounts = fixture()
        repo.put("privateAccounts/alice", {"state": "deleting"})
        objects.outputs["users/alice/jobs/job/chapter.m4a"] = b"test"
        worker.handle({"kind": "deleteAccount", "uid": "alice", "id": "alice"})
        self.assertEqual(repo.get("privateAccounts/alice")["state"], "deleted")
        self.assertEqual(objects.outputs, {})
        self.assertEqual(accounts.deleted, ["alice"])
        self.assertEqual(provider.deleted, ["voice_initial"])
        self.assertIsNone(repo.get("users/alice/jobs/job"))
    def test_account_tombstone_cancels_late_jobs_without_recreation(self):
        worker, repo, provider, objects, _ = fixture()
        repo.put("privateAccounts/alice", {"state": "deleted"})
        repo.clear_children("privateAccounts/alice")
        repo.delete_tree("users/alice")
        self.assertEqual(worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})["status"], "cancelled")
        self.assertEqual(provider.generated, [])
        self.assertIsNone(repo.get("users/alice/jobs/job"))
    def test_final_quota_retry_is_visible_failure(self):
        worker, repo, provider, objects, _ = fixture()
        def exhausted(*args, **kwargs):
            raise ProviderError(429)
        provider.generate = exhausted
        with self.assertRaises(ProviderError) as error:
            worker.handle({"kind": "narrate", "uid": "alice", "id": "job"}, retry_count=29)
        self.assertFalse(error.exception.retryable)
        self.assertEqual(repo.get("users/alice/jobs/job")["state"], "failed")
        self.assertEqual(repo.get("users/alice/jobs/job")["errorCode"], "provider_quota")
        self.assertEqual(objects.outputs, {})
    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg unavailable")
    def test_uncertain_renewal_reuses_marker_and_preserves_approval(self):
        worker, repo, provider, objects, _ = fixture()
        provider.voices.clear()
        provider.ambiguous = True
        with self.assertRaises(ProviderError):
            worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})
        worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})
        self.assertEqual(provider.created, 1)
        self.assertEqual(repo.get("users/alice/voices/voice-profile")["status"], "ready")
        self.assertEqual(repo.get("users/alice/jobs/job")["state"], "ready")
    def test_expired_job_cleanup_never_recreates_deleted_account_metadata(self):
        worker, repo, _, objects, _ = fixture()
        # Scheduler obtained an expired snapshot before account deletion completed.
        repo.put("privateAccounts/alice/jobs/job", {"expiresAt": now() - dt.timedelta(seconds=1)})
        repo.put("privateAccounts/alice", {"state": "deleted"})
        repo.clear_children("privateAccounts/alice")
        repo.delete_tree("users/alice")
        worker.expire_job("alice", "job")
        self.assertIsNone(repo.get("privateAccounts/alice/jobs/job"))
        self.assertIsNone(repo.get("users/alice/jobs/job"))
        self.assertEqual(repo.get("privateAccounts/alice")["state"], "deleted")
    def test_expired_job_cleanup_erases_snapshot_only_when_unleased(self):
        worker, repo, _, objects, _ = fixture()
        job_path = "privateAccounts/alice/jobs/job"
        repo.put(job_path, {"expiresAt": now() - dt.timedelta(seconds=1), "leaseToken": "busy", "leaseUntil": now() + dt.timedelta(minutes=1)})
        objects.outputs["users/alice/jobs/job/chapter.m4a"] = b"audio"
        worker.expire_job("alice", "job")
        self.assertEqual(repo.get(job_path)["state"], "queued")
        self.assertTrue(objects.outputs)
        repo.put(job_path, {"leaseUntil": now() - dt.timedelta(seconds=1)})
        worker.expire_job("alice", "job")
        self.assertEqual(repo.get(job_path)["state"], "failed")
        self.assertEqual(repo.get(job_path)["chapters"], [])
        self.assertEqual(objects.outputs, {})
    def test_stopped_worker_cannot_recreate_jobs_when_account_deleted_after_claim(self):
        worker, repo, _, _, _ = fixture()
        token = worker.claim("alice", "narrate", "job")
        repo.put("privateAccounts/alice", {"state": "deleted"})
        repo.clear_children("privateAccounts/alice")
        repo.delete_tree("users/alice")
        worker.stopped_job("alice", "job", token)
        self.assertIsNone(repo.get("privateAccounts/alice/jobs/job"))
        self.assertIsNone(repo.get("users/alice/jobs/job"))
    def test_voice_delete_cannot_stamp_tombstone_after_account_final_sweep(self):
        worker, repo, provider, _, _ = fixture()
        repo.put("privateAccounts/alice/voices/voice-profile", {"status": "deleting"})
        delete_voice = provider.delete_voice
        def finish_account_deletion(voice):
            delete_voice(voice)
            repo.put("privateAccounts/alice", {"state": "deleted"})
            repo.clear_children("privateAccounts/alice")
            repo.delete_tree("users/alice")
        provider.delete_voice = finish_account_deletion
        worker.delete_voice("alice", "voice-profile")
        self.assertIsNone(repo.get("privateAccounts/alice/voices/voice-profile"))
        self.assertIsNone(repo.get("users/alice/voices/voice-profile"))
    def test_deletion_waits_for_upload_reservation_then_erases_all_recordings(self):
        worker, repo, provider, objects, accounts = fixture()
        path = "privateAccounts/alice/enrollments/pending"
        repo.put(path, {"uid": "alice", "enrollmentId": "pending", "uploads": {"reference": {"expiresAt": now() + dt.timedelta(minutes=2)}}})
        repo.put("privateAccounts/alice", {"state": "deleting"})
        objects.raw[("alice", "pending")] = b"ciphertext"
        with self.assertRaises(SafeError) as error:
            worker.delete_account("alice")
        self.assertEqual(error.exception.code, "deletion_waiting_for_upload")
        self.assertTrue(error.exception.retryable)
        self.assertEqual(accounts.deleted, [])
        self.assertEqual(provider.deleted, [])
        repo.put(path, {"uploads": {"reference": {"expiresAt": now() - dt.timedelta(seconds=1)}}})
        worker.delete_account("alice")
        self.assertEqual(objects.raw, {})
        self.assertEqual(repo.get("privateAccounts/alice")["state"], "deleted")
    def test_orphan_sweep_removes_lost_acknowledgement_and_late_deleted_account_writes(self):
        worker, repo, _, objects, _ = fixture()
        objects.raw[("alice", "missing-session")] = b"orphan-ciphertext"
        objects.raw[("alice", "voice-profile")] = b"retained-ciphertext"
        objects.raw[("bob", "late-upload")] = b"late-ciphertext"
        repo.put("privateAccounts/bob", {"state": "deleted"})
        worker.cleanup_orphan_recordings()
        self.assertEqual(objects.raw, {("alice", "voice-profile"): b"retained-ciphertext"})
        # A request can finish its storage write after a previous sweep. Permanent
        # tombstone sweeps must continue deleting later objects without Firestore children.
        objects.raw[("bob", "later-upload")] = b"ciphertext"
        objects.outputs["users/bob/jobs/late/chapter.m4a"] = b"audio"
        objects.chunks[("bob", "late", "chapter", 0)] = b"audio"
        worker.cleanup_deleted_accounts()
        self.assertFalse(any(key[0] == "bob" for key in objects.raw))
        self.assertFalse(any(key[0] == "bob" for key in objects.chunks))
        self.assertFalse(any(path.startswith("users/bob/") for path in objects.outputs))
    def test_expired_enrollments_wait_for_upload_then_remove_or_preserve_submitted_sources(self):
        worker, repo, _, objects, _ = fixture()
        path = "privateAccounts/alice/enrollments/pending"
        repo.put(path, {"uid": "alice", "enrollmentId": "pending", "state": "collecting", "expiresAt": now() - dt.timedelta(seconds=1),
                        "uploads": {"reference": {"expiresAt": now() + dt.timedelta(minutes=2)}}})
        objects.raw[("alice", "pending")] = b"ciphertext"
        worker.expire_enrollment("alice", "pending")
        self.assertEqual(repo.get(path)["state"], "collecting")
        repo.put(path, {"uploads": {}})
        worker.expire_enrollment("alice", "pending")
        self.assertIsNone(repo.get(path))
        self.assertNotIn(("alice", "pending"), objects.raw)
        submitted = "privateAccounts/alice/enrollments/voice-profile"
        repo.put(submitted, {"uid": "alice", "enrollmentId": "voice-profile", "state": "submitted", "expiresAt": now() - dt.timedelta(seconds=1)})
        objects.raw[("alice", "voice-profile")] = b"retained-ciphertext"
        worker.expire_enrollment("alice", "voice-profile")
        worker.cleanup_orphan_recordings()
        self.assertIsNone(repo.get(submitted))
        self.assertIn(("alice", "voice-profile"), objects.raw)
    def test_cleanup_recovers_voice_deletion_after_queue_retries_exhausted(self):
        worker, repo, provider, objects, accounts = fixture(status="deleting")
        repo.put("privateAccounts/alice/voices/voice-profile", {"dispatchPending": False})
        objects.raw[("alice", "voice-profile")] = b"encrypted-recording"
        original_delete = provider.delete_voice
        provider.delete_voice = lambda _: (_ for _ in ()).throw(ProviderError(503))
        with self.assertLogs("service", level="WARNING"):
            worker.cleanup_pending_deletions()
        self.assertEqual(repo.get("privateAccounts/alice/voices/voice-profile")["status"], "deleting")
        self.assertTrue(objects.raw)
        provider.delete_voice = original_delete
        worker.cleanup_pending_deletions()
        self.assertEqual(repo.get("privateAccounts/alice/voices/voice-profile")["status"], "deleted")
        self.assertEqual(provider.deleted, ["voice_initial"])
        self.assertEqual(provider.created, 0)
        self.assertEqual(objects.raw, {})
        self.assertEqual(accounts.deleted, [])
    def test_cleanup_recovers_account_deletion_without_another_queued_task(self):
        worker, repo, provider, objects, accounts = fixture()
        repo.put("privateAccounts/alice", {"state": "deleting", "dispatchPending": False})
        objects.raw[("alice", "voice-profile")] = b"encrypted-recording"
        original_delete = provider.delete_voice
        provider.delete_voice = lambda _: (_ for _ in ()).throw(ProviderError(503))
        with self.assertLogs("service", level="WARNING"):
            worker.cleanup_pending_deletions()
        self.assertEqual(repo.get("privateAccounts/alice")["state"], "deleting")
        self.assertEqual(accounts.deleted, [])
        provider.delete_voice = original_delete
        worker.cleanup_pending_deletions()
        self.assertEqual(repo.get("privateAccounts/alice")["state"], "deleted")
        self.assertEqual(accounts.deleted, ["alice"])
        self.assertEqual(provider.created, 0)
        self.assertIsNone(repo.get("users/alice/jobs/job"))
        self.assertEqual(objects.raw, {})
    def test_one_failed_deletion_does_not_prevent_other_voices_from_completing(self):
        worker, repo, provider, _, _ = fixture(status="deleting")
        other = copy.deepcopy(repo.get("privateAccounts/alice/voices/voice-profile"))
        other.update({"voiceId": "zz-other", "providerVoice": worker.envelope.encrypt(b"voice_other", "alice", "zz-other", "providerVoice")})
        repo.put("privateAccounts/alice/voices/zz-other", other)
        repo.put("users/alice/voices/zz-other", {"uid": "alice", "status": "deleting"})
        provider.voices["voice_other"] = "other"
        original_delete = provider.delete_voice
        def delete_when_available(voice):
            if voice == "voice_initial":
                raise ProviderError(503)
            original_delete(voice)
        provider.delete_voice = delete_when_available
        with self.assertLogs("service", level="WARNING") as logs:
            worker.cleanup_pending_deletions()
        self.assertEqual(repo.get("privateAccounts/alice/voices/voice-profile")["status"], "deleting")
        self.assertEqual(repo.get("privateAccounts/alice/voices/zz-other")["status"], "deleted")
        self.assertEqual(provider.deleted, ["voice_other"])
        self.assertNotIn("alice", " ".join(logs.output))
    def test_slow_delete_advances_cursor_so_next_scheduled_cleanup_serves_other_accounts(self):
        worker, repo, provider, _, accounts = fixture()
        repo.put("privateAccounts/alice", {"state": "deleting"})
        repo.put("privateAccounts/bob", {"state": "deleting"})
        clock = [0]
        worker.monotonic = lambda: clock[0]
        original_delete = provider.delete_voice
        def slow_unavailable(voice):
            clock[0] += 700
            raise ProviderError(503)
        provider.delete_voice = slow_unavailable
        with self.assertLogs("service", level="WARNING"):
            worker.cleanup_pending_deletions()
        self.assertEqual(accounts.deleted, [])
        clock[0] = 0
        # Alice remains unavailable; advancing the durable cursor gives Bob the first
        # attempt on the next run rather than repeating Alice until the deadline.
        with self.assertLogs("service", level="WARNING"):
            worker.cleanup_pending_deletions()
        self.assertEqual(accounts.deleted, ["bob"])
        self.assertEqual(repo.get("privateAccounts/bob")["state"], "deleted")
        self.assertEqual(repo.get("privateAccounts/alice")["state"], "deleting")
        provider.delete_voice = original_delete
    def test_internal_transport_error_is_private_and_next_deletion_still_completes(self):
        worker, repo, provider, _, accounts = fixture()
        repo.put("privateAccounts/alice", {"state": "deleting"})
        repo.put("privateAccounts/bob", {"state": "deleting"})
        provider.delete_voice = lambda _: (_ for _ in ()).throw(RuntimeError("raw-parent-recording-or-secret"))
        with self.assertLogs("service", level="WARNING") as logs:
            worker.cleanup_pending_deletions()
        self.assertEqual(accounts.deleted, ["bob"])
        self.assertNotIn("raw-parent-recording-or-secret", " ".join(logs.output))
        self.assertIn("internal_retry", " ".join(logs.output))
    def test_worker_enforces_book_and_preview_caps_before_any_provider_calls(self):
        for text, preview in [("a" * 50_001, False), ("a " * 5401, False), ("a" * 1501, True)]:
            with self.subTest(preview=preview, characters=len(text)):
                worker, _, provider, _, _ = fixture(text=text, preview=preview)
                with self.assertRaises(SafeError) as error:
                    worker.handle({"kind": "narrate", "uid": "alice", "id": "job"})
                self.assertEqual(error.exception.code, "snapshot_too_large")
                self.assertEqual(provider.generated, [])
                self.assertEqual(provider.created, 0)


class Response:
    def __init__(self, status, body=None):
        self.status_code, self.body = status, body
        self.content = json.dumps(body).encode() if body is not None else b""
    def json(self):
        return self.body


class Session:
    def __init__(self, responses):
        self.responses, self.requests = list(responses), []
    def request(self, method, url, **kwargs):
        self.requests.append((method, url, kwargs))
        return self.responses.pop(0)


class ProviderTests(unittest.TestCase):
    def test_exact_enterprise_create_contract(self):
        session = Session([Response(200, {"id": "voice_test"})])
        gemini = Gemini("bedtime-staging", session, sleep=lambda _: None)
        gemini.create_voice(wav(12), wav(8), "bedtime-id")
        method, url, kwargs = session.requests[0]
        self.assertTrue(url.endswith("v1beta1/projects/bedtime-staging/locations/global/voices"))
        self.assertEqual(kwargs["json"]["store"], True)
        self.assertEqual(kwargs["json"]["voice"]["type"], "VOICE_TYPE_REPLICATED")
        self.assertNotIn("model", kwargs["json"]["voice"])
    def test_generation_uses_only_fixed_model_and_owned_voice(self):
        session = Session([Response(200, {"candidates": [{"finishReason": "STOP", "content": {"parts": [{"inlineData": {"mimeType": "audio/wav", "data": base64.b64encode(wav()).decode()}}]}}]})])
        result = Gemini("bedtime", session).generate("voice_test", "Hello", "gentle")
        self.assertEqual(result, wav())
        _, url, kwargs = session.requests[0]
        self.assertIn(MODEL, url)
        self.assertEqual(kwargs["json"]["contents"][0]["parts"][0]["text"], "Hello")
        self.assertIn("speechMetadata", kwargs["json"]["contents"][0]["parts"][0])
    def test_incomplete_candidate_cannot_publish_partial_audio(self):
        session = Session([Response(200, {"candidates": [{"finishReason": "MAX_TOKENS", "content": {"parts": []}}]})])
        with self.assertRaises(SafeError):
            Gemini("bedtime", session).generate("voice_test", "Hello", "gentle")
    def test_transient_retry_and_uncertain_create_no_blind_retry(self):
        session = Session([Response(503), Response(429), Response(200, {"id": "voice_test"})])
        self.assertEqual(Gemini("bedtime", session, sleep=lambda _: None).get_voice("voice_test")["id"], "voice_test")
        self.assertEqual(len(session.requests), 3)
        session = Session([Response(503)])
        with self.assertRaises(ProviderError) as error:
            Gemini("bedtime", session).create_voice(wav(12), wav(8), "marker")
        self.assertTrue(error.exception.ambiguous)
        self.assertEqual(len(session.requests), 1)
    def test_provider_404_delete_is_idempotent(self):
        Gemini("bedtime", Session([Response(404)])).delete_voice("voice_missing")


if __name__ == "__main__":
    unittest.main()
