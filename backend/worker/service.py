"""Private task runner with owner checks, fenced leases, resumable chunks, and deletion."""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import logging
import time
import uuid

from cloud import now
from core import (SafeError, Stopped, assert_owner, assemble_m4a, chapter_chunks,
                  BUILT_IN_VOICES, built_in_voice, chunk_hash, identity, provider_identity, validate_task, wav_pcm)
from provider import ProviderError
from diagnostics import connection, event, observed, operation_context, task_key

LEASE_SECONDS = 1200
WORK_SECONDS = 600
MAX_CLEANUP_DELETIONS = 20
DELETION_CURSOR_PATH = "privateMaintenance/deletionCleanup"
LOGGER = logging.getLogger(__name__)
TERMINAL = {"ready", "failed", "cancelled", "deleted", "expired"}


class Worker:
    def __init__(self, repository, objects, envelope, provider, accounts, monotonic=time.monotonic):
        self.repo, self.objects, self.envelope = repository, objects, envelope
        self.provider, self.accounts, self.monotonic = provider, accounts, monotonic

    @staticmethod
    def paths(uid, kind, item_id):
        collection = "voices" if kind == "enroll" else "jobs"
        return f"privateAccounts/{uid}/{collection}/{item_id}", f"users/{uid}/{collection}/{item_id}"

    def account_active(self, uid):
        account = self.repo.get(f"privateAccounts/{uid}")
        if not account or account.get("state") != "active":
            raise Stopped()

    @observed("worker", "claim_lease")
    def claim(self, uid, kind, item_id, renewal=False):
        private_path, public_path = self.paths(uid, kind, item_id)
        account_path = f"privateAccounts/{uid}"
        token = uuid.uuid4().hex
        def operation(documents):
            account = documents[account_path]
            if not account or account.get("state") != "active":
                raise Stopped()
            private = assert_owner(documents[private_path], uid, item_id, "voiceId" if kind == "enroll" else "jobId")
            public = documents[public_path]
            if not public or public.get("uid") != uid:
                raise SafeError("ownership_mismatch")
            state_field = "status" if kind == "enroll" else "state"
            state = private.get(state_field)
            if private.get("cancelRequested") or state in {"deleting", "deleted", "cancelled"}:
                raise Stopped()
            if not renewal and (state in TERMINAL or state == "awaitingApproval"):
                return {}, None
            lease = private.get("leaseUntil")
            if lease and lease > now():
                raise SafeError("lease_busy", retryable=True)
            values = {"leaseToken": token, "leaseUntil": now() + dt.timedelta(seconds=LEASE_SECONDS),
                      "dispatchPending": False, "updatedAt": now()}
            if not renewal:
                values[state_field] = "processing"
            writes = {private_path: values}
            if not renewal:
                writes[public_path] = {state_field: "processing", "updatedAt": now(), "errorCode": None}
            return writes, token
        return self.repo.atomic([account_path, private_path, public_path], operation)

    def live_voice(self, uid, voice_id, preview=False):
        self.account_active(uid)
        private_path, public_path = self.paths(uid, "enroll", voice_id)
        private = assert_owner(self.repo.get(private_path), uid, voice_id, "voiceId")
        public = self.repo.get(public_path)
        allowed = {"ready", "awaitingApproval"} if preview else {"ready"}
        if not public or public.get("uid") != uid or private.get("status") not in allowed or public.get("status") not in allowed:
            raise Stopped()
        if not private.get("retentionAccepted") or private.get("deletedAt"):
            raise Stopped()
        return private

    @observed("worker", "fenced_update")
    def fenced_update(self, uid, kind, item_id, token, private_values, public_values=None, require_voice=None):
        private_path, public_path = self.paths(uid, kind, item_id)
        account_path = f"privateAccounts/{uid}"
        paths = [account_path, private_path, public_path]
        if require_voice and require_voice[0] not in BUILT_IN_VOICES:
            voice_id, preview = require_voice
            voice_private, voice_public = self.paths(uid, "enroll", voice_id)
            paths += [voice_private, voice_public]
        def operation(documents):
            if not documents[account_path] or documents[account_path].get("state") != "active":
                raise Stopped()
            private = assert_owner(documents[private_path], uid, item_id, "voiceId" if kind == "enroll" else "jobId")
            if private.get("leaseToken") != token or private.get("leaseUntil", now()) <= now():
                raise SafeError("lease_lost", retryable=True)
            if private.get("cancelRequested") or private.get("state", private.get("status")) in {"deleting", "deleted", "cancelled"}:
                raise Stopped()
            public = documents[public_path]
            if not public or public.get("uid") != uid:
                raise SafeError("ownership_mismatch")
            if require_voice:
                voice_id, preview = require_voice
                if private.get("expiresAt", now()) <= now():
                    raise SafeError("job_expired")
                if private.get("voiceProfileId") != voice_id or bool(private.get("preview")) != preview:
                    raise Stopped()
                if voice_id in BUILT_IN_VOICES:
                    built_in_voice(voice_id, private.get("language"))
                else:
                    voice = assert_owner(documents[voice_private], uid, voice_id, "voiceId")
                    permitted = {"ready", "awaitingApproval"} if preview else {"ready"}
                    if voice.get("status") not in permitted or not documents[voice_public] or documents[voice_public].get("status") not in permitted:
                        raise Stopped()
            writes = {private_path: {**private_values, "updatedAt": now()}}
            if public_values is not None:
                writes[public_path] = {**public_values, "updatedAt": now()}
            return writes, None
        self.repo.atomic(paths, operation)

    def heartbeat(self, uid, kind, item_id, token, require_voice=None):
        self.fenced_update(uid, kind, item_id, token,
                           {"leaseUntil": now() + dt.timedelta(seconds=LEASE_SECONDS)}, require_voice=require_voice)

    @observed("worker", "release_lease")
    def release(self, uid, kind, item_id, token):
        private_path, _ = self.paths(uid, kind, item_id)
        def operation(documents):
            private = documents[private_path]
            if not private or private.get("leaseToken") != token:
                return {}, None
            return {private_path: {"leaseToken": None, "leaseUntil": now()}}, None
        self.repo.atomic([private_path], operation)

    def _provider_voice(self, uid, voice_id, token, renewal=False):
        private_path, _ = self.paths(uid, "enroll", voice_id)
        private = assert_owner(self.repo.get(private_path), uid, voice_id, "voiceId")
        if private.get("providerVoice"):
            return provider_identity(self.envelope.decrypt(private["providerVoice"], uid, voice_id, "providerVoice").decode())
        if not private.get("retentionAccepted") or private.get("consentVersion") != "2026-10-01":
            raise SafeError("consent_required")
        marker = private.get("providerMarker")
        if not marker:
            marker = "bedtime-" + uuid.uuid4().hex
            self.fenced_update(uid, "enroll", voice_id, token, {"providerMarker": marker})
        existing = self.provider.find_voices(marker)
        event(LOGGER, logging.DEBUG, "voice_reconciliation_completed", matching_voices=len(existing), renewal=renewal)
        if len(existing) > 1:
            raise SafeError("voice_reconciliation_required")
        if existing:
            provider_voice = existing[0]
        else:
            private = self.repo.get(private_path)
            if private.get("creationAttemptStarted"):
                # A previous uncertain POST could still commit. Keep its marker for reconciliation.
                raise SafeError("voice_creation_unconfirmed", retryable=True)
            reference = self.envelope.decrypt(self.objects.read_envelope(uid, voice_id, "reference", private.get("referenceObject")), uid, voice_id, "reference")
            consent = self.envelope.decrypt(self.objects.read_envelope(uid, voice_id, "consent", private.get("consentObject")), uid, voice_id, "consent")
            wav_pcm(reference, 10, 30)
            wav_pcm(consent, 2, 60)
            self.fenced_update(uid, "enroll", voice_id, token, {"creationAttemptStarted": now()})
            try:
                provider_voice = self.provider.create_voice(reference, consent, marker)
            except ProviderError as error:
                if not error.ambiguous:
                    self.fenced_update(uid, "enroll", voice_id, token, {"creationAttemptStarted": None})
                raise
        try:
            encrypted = self.envelope.encrypt(provider_voice.encode(), uid, voice_id, "providerVoice")
            self.fenced_update(uid, "enroll", voice_id, token,
                               {"providerVoice": encrypted, "providerCreatedAt": now(), "creationAttemptStarted": None})
        except Stopped:
            event(LOGGER, logging.DEBUG, "voice_creation_cancelled", recovery="delete_unattached_voice")
            self.provider.delete_voice(provider_voice)
            raise
        return provider_voice

    def enroll(self, uid, voice_id, token):
        self._provider_voice(uid, voice_id, token)
        self.fenced_update(uid, "enroll", voice_id, token,
                           {"status": "awaitingApproval", "lastUsedAt": now()},
                           {"status": "awaitingApproval", "errorCode": None})

    def ensured_voice(self, uid, voice_id, preview, language=None):
        built_in = built_in_voice(voice_id, language)
        if built_in:
            self.account_active(uid)
            return built_in
        voice = self.live_voice(uid, voice_id, preview)
        if voice.get("providerVoice"):
            provider_voice = provider_identity(self.envelope.decrypt(voice["providerVoice"], uid, voice_id, "providerVoice").decode())
            if self.provider.get_voice(provider_voice) is not None:
                return provider_voice
        token = self.claim(uid, "enroll", voice_id, renewal=True)
        event(LOGGER, logging.WARNING, "voice_renewal_started", recovery="retained_recordings")
        try:
            voice = self.live_voice(uid, voice_id, preview)
            # Expired stored voices are recreated only from retained, consented recordings.
            # Preserve an in-flight renewal marker after a transient failure.
            if voice.get("providerVoice"):
                current = provider_identity(self.envelope.decrypt(voice["providerVoice"], uid, voice_id, "providerVoice").decode())
                if self.provider.get_voice(current) is not None:
                    return current
                self.fenced_update(uid, "enroll", voice_id, token,
                                   {"providerVoice": None, "providerMarker": "bedtime-" + uuid.uuid4().hex,
                                    "creationAttemptStarted": None})
            provider_voice = self._provider_voice(uid, voice_id, token, renewal=True)
            self.live_voice(uid, voice_id, preview)
            return provider_voice
        finally:
            self.release(uid, "enroll", voice_id, token)

    def narrate(self, uid, job_id, token):
        started = self.monotonic()
        private_path, _ = self.paths(uid, "narrate", job_id)
        job = assert_owner(self.repo.get(private_path), uid, job_id, "jobId")
        voice_id, preview = identity(job.get("voiceProfileId")), bool(job.get("preview"))
        expires_at = job.get("expiresAt")
        if not isinstance(expires_at, dt.datetime) or expires_at <= now():
            raise SafeError("job_expired")
        chapters = job.get("chapters")
        if not isinstance(chapters, list) or not 1 <= len(chapters) <= 50:
            raise SafeError("invalid_snapshot")
        if any(not isinstance(chapter, dict) for chapter in chapters):
            raise SafeError("invalid_snapshot")
        ids = [identity(chapter.get("id")) for chapter in chapters]
        if len(set(ids)) != len(ids):
            raise SafeError("invalid_snapshot")
        planned = [(chapter, chapter_chunks(chapter)) for chapter in chapters]
        characters = sum(len(chunk["text"]) for _, chunks in planned for chunk in chunks)
        words = sum(len(paragraph["text"].split()) for chapter in chapters for paragraph in chapter["paragraphs"])
        if characters > (1500 if preview else 50_000) or (not preview and words > 5400):
            raise SafeError("snapshot_too_large")
        provider_voice = self.ensured_voice(uid, voice_id, preview, job.get("language"))
        expected_voice = (voice_id, preview)
        total = sum(len(chunks) for _, chunks in planned)
        event(LOGGER, logging.DEBUG, "narration_plan_validated", chapter_count=len(planned), chunk_count=total, preview=preview)
        checkpoints = dict(job.get("checkpoints") or {})
        completed = 0
        outputs = []
        for chapter_index, (chapter, chunks) in enumerate(planned):
            event(LOGGER, logging.DEBUG, "narration_chapter_started", chapter_index=chapter_index, chunk_count=len(chunks))
            for index, chunk in enumerate(chunks):
                self.heartbeat(uid, "narrate", job_id, token, expected_voice)
                key = f"{chapter['id']}:{index}"
                if checkpoints.get(key) == chunk_hash(chunk):
                    clip = self.objects.read_checkpoint(uid, job_id, chapter["id"], index)
                else:
                    clip = None
                if clip is None:
                    if self.monotonic() - started >= WORK_SECONDS:
                        event(LOGGER, logging.DEBUG, "narration_continuation_requested", completed_chunks=completed, chunk_count=total)
                        raise SafeError("job_continuing", retryable=True)
                    event(LOGGER, logging.DEBUG, "narration_chunk_started", chapter_index=chapter_index, chunk_index=index)
                    clip = self.provider.generate(provider_voice, chunk["text"], chunk["style"], language=job.get("language"))
                    self.heartbeat(uid, "narrate", job_id, token, expected_voice)
                    self.objects.checkpoint(uid, job_id, chapter["id"], index, clip)
                    checkpoints[key] = chunk_hash(chunk)
                else:
                    event(LOGGER, logging.DEBUG, "narration_checkpoint_reused", chapter_index=chapter_index, chunk_index=index)
                wav_pcm(clip)
                completed += 1
                self.fenced_update(uid, "narrate", job_id, token,
                                   {"checkpoints": checkpoints, "progress": completed / total},
                                   {"progress": completed / total}, expected_voice)
                event(LOGGER, logging.DEBUG, "narration_chunk_completed", chapter_index=chapter_index, chunk_index=index,
                      completed_chunks=completed, chunk_count=total)
            self.heartbeat(uid, "narrate", job_id, token, expected_voice)
            # Read one validated checkpoint at a time; slow long-form delivery can otherwise
            # accumulate gigabytes of WAV clips before the chapter duration check runs.
            clips = (self.objects.read_checkpoint(uid, job_id, chapter["id"], index) for index in range(len(chunks)))
            encoded, duration = assemble_m4a(clips)
            self.heartbeat(uid, "narrate", job_id, token, expected_voice)
            path = self.objects.output(uid, job_id, chapter["id"], encoded, expires_at)
            self.heartbeat(uid, "narrate", job_id, token, expected_voice)
            outputs.append({"chapterId": chapter["id"], "path": path, "sha256": hashlib.sha256(encoded).hexdigest(),
                            "duration": duration, "bytes": len(encoded)})
            event(LOGGER, logging.DEBUG, "narration_chapter_published", chapter_index=chapter_index, audio_bytes=len(encoded), duration_seconds=round(duration, 3))
        self.fenced_update(uid, "narrate", job_id, token,
                           {"state": "ready", "outputs": outputs, "progress": 1, "chapters": [], "checkpoints": {}},
                           {"state": "ready", "outputs": outputs, "progress": 1, "errorCode": None}, expected_voice)
        # Internal chunks and the frozen manuscript are deleted only after successful publication.
        self.objects.delete_prefix(self.objects.voice_bucket, f"chunks/{uid}/{job_id}/")

    def deletion_wait(self, uid, voice_id=None):
        for collection in ["voices", "jobs"]:
            for item_id, document in self.repo.collection(f"privateAccounts/{uid}/{collection}"):
                if voice_id and not (collection == "voices" and item_id == voice_id or collection == "jobs" and document.get("voiceProfileId") == voice_id):
                    continue
                if document.get("leaseToken") and document.get("leaseUntil", now()) > now():
                    raise SafeError("deletion_waiting_for_worker", retryable=True)
        for enrollment_id, document in self.repo.collection(f"privateAccounts/{uid}/enrollments"):
            if voice_id and enrollment_id != voice_id:
                continue
            if self.upload_active(document):
                raise SafeError("deletion_waiting_for_upload", retryable=True)

    @staticmethod
    def upload_active(enrollment):
        return any(isinstance(upload, dict) and isinstance(upload.get("expiresAt"), dt.datetime)
                   and upload["expiresAt"] > now()
                   for upload in (enrollment or {}).get("uploads", {}).values())

    def delete_voice(self, uid, voice_id):
        private_path, public_path = self.paths(uid, "enroll", voice_id)
        voice = self.repo.get(private_path)
        if not voice:
            return
        assert_owner(voice, uid, voice_id, "voiceId")
        account = self.repo.get(f"privateAccounts/{uid}")
        if voice.get("status") not in {"deleting", "deleted"} and (not account or account.get("state") not in {"deleting", "deleted"}):
            raise SafeError("deletion_not_requested")
        self.deletion_wait(uid, voice_id)
        provider_voices = []
        if voice.get("providerVoice"):
            provider_voices.append(provider_identity(self.envelope.decrypt(voice["providerVoice"], uid, voice_id, "providerVoice").decode()))
        if voice.get("providerMarker"):
            provider_voices.extend(self.provider.find_voices(voice["providerMarker"]))
        if voice.get("creationAttemptStarted") and not provider_voices:
            raise SafeError("voice_deletion_unconfirmed", retryable=True)
        for provider_voice in set(provider_voices):
            self.provider.delete_voice(provider_voice)
        self.objects.delete_recordings(uid, voice_id)
        for job_id, job in self.repo.collection(f"privateAccounts/{uid}/jobs"):
            if job.get("voiceProfileId") == voice_id and job.get("state") != "ready":
                self.objects.delete_job(uid, job_id)
                self.cancel_deleted_voice_job(uid, job_id, voice_id)
        self.repo.delete_tree(private_path)
        account_path = f"privateAccounts/{uid}"
        def mark_deleted(documents):
            account = documents[account_path]
            # A simultaneous account deletion may have completed the final metadata sweep.
            if not account or account.get("state") not in {"active", "deleting"}:
                return {}, None
            writes = {private_path: {"uid": uid, "voiceId": voice_id, "status": "deleted", "deletedAt": now()}}
            public = documents[public_path]
            if public and public.get("uid") == uid:
                writes[public_path] = {"status": "deleted", "deletedAt": now(), "errorCode": None}
            return writes, None
        self.repo.atomic([account_path, public_path], mark_deleted)

    def cancel_deleted_voice_job(self, uid, job_id, voice_id):
        private_path, public_path = self.paths(uid, "narrate", job_id)
        account_path = f"privateAccounts/{uid}"
        def operation(documents):
            account, private, public = [documents[path] for path in [account_path, private_path, public_path]]
            if not account or account.get("state") not in {"active", "deleting"} or not private:
                return {}, None
            assert_owner(private, uid, job_id, "jobId")
            if private.get("voiceProfileId") != voice_id or private.get("state") == "ready":
                return {}, None
            writes = {private_path: {"state": "cancelled", "chapters": [], "checkpoints": {}, "outputs": [], "cancelRequested": True}}
            if public and public.get("uid") == uid:
                writes[public_path] = {"state": "cancelled", "errorCode": "voice_deleted", "outputs": []}
            return writes, None
        self.repo.atomic([account_path, private_path, public_path], operation)

    def delete_account(self, uid):
        account = self.repo.get(f"privateAccounts/{uid}")
        if not account or account.get("state") not in {"deleting", "deleted"}:
            raise SafeError("deletion_not_requested")
        self.deletion_wait(uid)
        for voice_id, _ in self.repo.collection(f"privateAccounts/{uid}/voices"):
            self.delete_voice(uid, voice_id)
        self.objects.delete_account(uid)
        self.accounts.delete(uid)
        # Publish the permanent fence before the final sweep so simultaneous voice deletes
        # and expired-job cleanup cannot recreate metadata after the sweep.
        account_path = f"privateAccounts/{uid}"
        def mark_deleted(documents):
            account = documents[account_path]
            if not account or account.get("state") not in {"deleting", "deleted"}:
                raise SafeError("deletion_not_requested")
            return {account_path: {"state": "deleted", "deletedAt": now(), "limits": {}, "dispatchPending": False}}, None
        self.repo.atomic([account_path], mark_deleted)
        self.repo.delete_tree(f"users/{uid}")
        # Retain only a permanent account tombstone to prevent stale tasks from recreating data.
        self.repo.clear_children(f"privateAccounts/{uid}")

    def expire_job(self, uid, job_id):
        private_path, public_path = self.paths(uid, "narrate", job_id)
        account_path = f"privateAccounts/{uid}"
        def operation(documents):
            account, private, public = [documents[path] for path in [account_path, private_path, public_path]]
            if not account or account.get("state") != "active" or not private:
                return {}, False
            assert_owner(private, uid, job_id, "jobId")
            if not isinstance(private.get("expiresAt"), dt.datetime) or private["expiresAt"] > now():
                return {}, False
            if private.get("leaseToken") and private.get("leaseUntil", now()) > now():
                return {}, False
            writes = {private_path: {"state": "failed", "chapters": [], "checkpoints": {}, "outputs": [], "errorCode": "output_expired"}}
            if public and public.get("uid") == uid:
                writes[public_path] = {"state": "failed", "outputs": [], "errorCode": "output_expired"}
            return writes, True
        if self.repo.atomic([account_path, private_path, public_path], operation):
            self.objects.delete_job(uid, job_id)

    def expire_enrollment(self, uid, enrollment_id):
        path = f"privateAccounts/{uid}/enrollments/{enrollment_id}"
        def operation(documents):
            enrollment = documents[path]
            if not enrollment or enrollment.get("uid") != uid or enrollment.get("enrollmentId") != enrollment_id:
                return {}, None
            expires_at = enrollment.get("expiresAt")
            if not isinstance(expires_at, dt.datetime) or expires_at > now() or self.upload_active(enrollment):
                return {}, None
            state = enrollment.get("state")
            if state in {"collecting", "expired"}:
                # Fence the API before deleting objects; an upload cannot attach to this session.
                return {path: {"state": "expired"}}, "remove_recordings"
            if state == "submitted":
                return {path: None}, "retain_recordings"
            return {}, None
        action = self.repo.atomic([path], operation)
        if action == "remove_recordings":
            self.objects.delete_recordings(uid, enrollment_id)
            self.repo.atomic([path], lambda docs: ({path: None}, None) if docs[path] and docs[path].get("state") == "expired" else ({}, None))

    def cleanup_orphan_recordings(self):
        for uid, enrollment_id in self.objects.recording_enrollments():
            account = self.repo.get(f"privateAccounts/{uid}")
            # A deleted-account sweep catches a write that completed after the original deletion.
            if account and account.get("state") == "deleted":
                self.objects.delete_recordings(uid, enrollment_id)
                continue
            enrollment = self.repo.get(f"privateAccounts/{uid}/enrollments/{enrollment_id}")
            if enrollment and enrollment.get("uid") == uid and enrollment.get("enrollmentId") == enrollment_id:
                # Expired sessions are handled under a transaction fence above. Live reservations
                # and collecting sessions must survive lost upload acknowledgements for retries.
                if enrollment.get("state") != "expired":
                    continue
            voice = self.repo.get(f"privateAccounts/{uid}/voices/{enrollment_id}")
            if voice and voice.get("uid") == uid and voice.get("voiceId") == enrollment_id and voice.get("status") != "deleted":
                continue
            # Object creation requires an existing enrollment reservation. Missing/expired
            # enrollment and voice documents cannot become a new profile, so this is an orphan.
            self.objects.delete_recordings(uid, enrollment_id)

    def stopped_job(self, uid, job_id, token):
        if not token:
            return
        private_path, public_path = self.paths(uid, "narrate", job_id)
        account_path = f"privateAccounts/{uid}"
        def operation(documents):
            account, private, public = [documents[path] for path in [account_path, private_path, public_path]]
            if not account or account.get("state") != "active" or not private or private.get("leaseToken") != token:
                return {}, None
            assert_owner(private, uid, job_id, "jobId")
            writes = {private_path: {"state": "cancelled", "chapters": [], "checkpoints": {}, "outputs": []}}
            if public and public.get("uid") == uid:
                writes[public_path] = {"state": "cancelled", "outputs": [], "errorCode": "cancelled"}
            return writes, None
        self.repo.atomic([account_path, private_path, public_path], operation)

    @observed("worker", "cleanup")
    def cleanup(self):
        self.objects.cleanup_expired_objects()
        # Single-field collection-group scan: no manuscript or provider ID enters logs.
        with connection(LOGGER, "firestore", "scan_expired_jobs"):
            for snapshot in self.repo.db.collection_group("jobs").where("expiresAt", "<=", now()).stream():
                path = snapshot.reference.path
                parts = path.split("/")
                if len(parts) != 4 or parts[0] != "privateAccounts":
                    continue
                uid, job_id = identity(parts[1]), identity(parts[3])
                self.expire_job(uid, job_id)
        with connection(LOGGER, "firestore", "scan_expired_enrollments"):
            for snapshot in self.repo.db.collection_group("enrollments").where("expiresAt", "<=", now()).stream():
                parts = snapshot.reference.path.split("/")
                if len(parts) != 4 or parts[0] != "privateAccounts":
                    continue
                uid, enrollment_id = identity(parts[1]), identity(parts[3])
                self.expire_enrollment(uid, enrollment_id)
        self.cleanup_orphan_recordings()
        self.cleanup_pending_deletions()
        self.cleanup_deleted_accounts()

    def cleanup_pending_deletions(self):
        """Recover durable deletion intent independently of finite Cloud Tasks retries.

        Advance a server-only cursor before each bounded attempt. A slow/unavailable
        provider or interrupted Scheduler run must not repeatedly starve later owners.
        No provider voice is created or renewed by these paths.
        """
        candidates = []
        for uid, account in self.repo.collection("privateAccounts"):
            identity(uid)
            if account.get("state") == "deleting":
                candidates.append((f"{uid}/account", uid, None))
            elif account.get("state") == "active":
                for voice_id, voice in self.repo.collection(f"privateAccounts/{uid}/voices"):
                    if voice.get("status") == "deleting":
                        identity(voice_id)
                        candidates.append((f"{uid}/voice/{voice_id}", uid, voice_id))
        if not candidates:
            return
        candidates.sort()
        cursor = (self.repo.get(DELETION_CURSOR_PATH) or {}).get("lastKey", "")
        if not isinstance(cursor, str):
            cursor = ""
        candidates = [candidate for candidate in candidates if candidate[0] > cursor] + [candidate for candidate in candidates if candidate[0] <= cursor]
        started = self.monotonic()
        for key, uid, voice_id in candidates[:MAX_CLEANUP_DELETIONS]:
            if self.monotonic() - started >= WORK_SECONDS:
                break
            self.repo.put(DELETION_CURSOR_PATH, {"lastKey": key, "updatedAt": now()})
            kind, item_id = ("deleteAccount", uid) if voice_id is None else ("deleteVoice", voice_id)
            with operation_context(task_kind=kind, task_key=task_key(kind, uid, item_id)):
                event(LOGGER, logging.DEBUG, "voice_cleanup_delete_started")
                try:
                    if voice_id is None:
                        self.delete_account(uid)
                    else:
                        self.delete_voice(uid, voice_id)
                    event(LOGGER, logging.DEBUG, "voice_cleanup_delete_completed")
                except SafeError as error:
                    # The durable tombstone remains available for a future cleanup attempt.
                    event(LOGGER, logging.WARNING, "voice_cleanup_delete_deferred", error=error, code=error.code)
                except Exception as error:
                    event(LOGGER, logging.WARNING, "voice_cleanup_delete_deferred", error=error, code="internal_retry")

    def cleanup_deleted_accounts(self):
        for uid, account in self.repo.collection("privateAccounts"):
            if account.get("state") == "deleted":
                # Retry this sweep forever while the permanent tombstone exists. It erases
                # late object writes and metadata left by interrupted deletion attempts.
                identity(uid)
                self.objects.delete_account(uid)
                self.repo.delete_tree(f"users/{uid}")
                self.repo.clear_children(f"privateAccounts/{uid}")

    @observed("worker", "handle_task")
    def handle(self, payload, retry_count=0):
        kind, uid, item_id = validate_task(payload)
        if kind == "deleteVoice":
            self.delete_voice(uid, item_id)
            return {"status": "complete"}
        if kind == "deleteAccount":
            self.delete_account(uid)
            return {"status": "complete"}
        token = None
        try:
            token = self.claim(uid, kind, item_id)
            if token is None:
                event(LOGGER, logging.DEBUG, "voice_task_already_terminal")
                return {"status": "complete"}
            if kind == "enroll":
                self.enroll(uid, item_id, token)
            else:
                self.narrate(uid, item_id, token)
            return {"status": "complete"}
        except Stopped:
            event(LOGGER, logging.DEBUG, "voice_task_cancelled")
            if kind == "narrate":
                self.objects.delete_job(uid, item_id)
                self.stopped_job(uid, item_id, token)
            return {"status": "cancelled"}
        except SafeError as error:
            if error.retryable and retry_count >= 29 and error.code in {"provider_quota", "provider_unavailable", "job_continuing"}:
                # A exhausted provider retry must become an observable terminal state.
                error.retryable = False
                event(LOGGER, logging.DEBUG, "voice_task_retries_exhausted", queue_retry_count=retry_count, code=error.code)
            if token and not error.retryable:
                try:
                    field = "status" if kind == "enroll" else "state"
                    private_values = {field: "failed", "errorCode": error.code}
                    if kind == "narrate":
                        self.objects.delete_job(uid, item_id)
                        private_values.update({"chapters": [], "checkpoints": {}, "outputs": []})
                    self.fenced_update(uid, kind, item_id, token, private_values, {field: "failed", "errorCode": error.code, "outputs": []} if kind == "narrate" else {field: "failed", "errorCode": error.code})
                except Stopped:
                    event(LOGGER, logging.DEBUG, "voice_failure_state_cancelled")
            raise
        finally:
            if token:
                self.release(uid, kind, item_id, token)
