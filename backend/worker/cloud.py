"""Narrow cloud adapters. All paths are assembled from validated identity components."""
from __future__ import annotations

import datetime as dt
import json

from core import SafeError, assert_owner, identity

UTC = dt.timezone.utc


def now():
    return dt.datetime.now(UTC)


class Repository:
    def __init__(self, project: str, database=None):
        from google.cloud import firestore
        self.firestore = firestore
        self.db = database or firestore.Client(project=project)

    def get(self, path: str) -> dict | None:
        snapshot = self.db.document(path).get()
        return snapshot.to_dict() if snapshot.exists else None

    def put(self, path: str, values: dict):
        self.db.document(path).set(values, merge=True)

    def delete(self, path: str):
        self.db.document(path).delete()

    def collection(self, path: str) -> list[tuple[str, dict]]:
        return [(document.id, document.to_dict()) for document in self.db.collection(path).stream()]

    def atomic(self, paths: list[str], operation):
        @self.firestore.transactional
        def execute(transaction):
            documents = {}
            for path in paths:
                snapshot = self.db.document(path).get(transaction=transaction)
                documents[path] = snapshot.to_dict() if snapshot.exists else None
            writes, result = operation(documents)
            for path, values in writes.items():
                if values is None:
                    transaction.delete(self.db.document(path))
                else:
                    transaction.set(self.db.document(path), values, merge=True)
            return result
        return execute(self.db.transaction())

    def delete_tree(self, path: str):
        """Erase private/public subcollections after active workers have stopped."""
        reference = self.db.document(path)
        for collection in reference.collections():
            for document in collection.stream():
                self.delete_tree(document.reference.path)
        reference.delete()

    def clear_children(self, path: str):
        for collection in self.db.document(path).collections():
            for document in collection.stream():
                self.delete_tree(document.reference.path)


class Objects:
    def __init__(self, project: str, voice_bucket: str, output_bucket: str, storage=None):
        from google.cloud import storage as cloud_storage
        self.storage = storage or cloud_storage.Client(project=project)
        self.voice_bucket, self.output_bucket = voice_bucket, output_bucket

    def read_envelope(self, uid: str, voice_id: str, kind: str, supplied_path: str) -> dict:
        expected = f"enrollments/{identity(uid)}/{identity(voice_id)}/{kind}.json"
        if supplied_path != expected or kind not in {"reference", "consent"}:
            raise SafeError("invalid_recording_path")
        blob = self.storage.bucket(self.voice_bucket).blob(expected)
        blob.reload()
        if not blob.size or blob.size > 4_500_000:
            raise SafeError("invalid_recording_size")
        try:
            return json.loads(blob.download_as_bytes(if_generation_match=blob.generation))
        except (ValueError, TypeError) as error:
            raise SafeError("invalid_envelope") from error

    def read_checkpoint(self, uid: str, job_id: str, chapter_id: str, index: int) -> bytes | None:
        path = self.chunk_path(uid, job_id, chapter_id, index)
        blob = self.storage.bucket(self.voice_bucket).blob(path)
        if not blob.exists():
            return None
        blob.reload()
        if not blob.size or blob.size > 20_000_000:
            raise SafeError("invalid_checkpoint")
        return blob.download_as_bytes(if_generation_match=blob.generation)

    @staticmethod
    def chunk_path(uid: str, job_id: str, chapter_id: str, index: int) -> str:
        if not isinstance(index, int) or index < 0 or index > 2000:
            raise SafeError("invalid_checkpoint")
        return f"chunks/{identity(uid)}/{identity(job_id)}/{identity(chapter_id)}/{index}.wav"

    def checkpoint(self, uid: str, job_id: str, chapter_id: str, index: int, audio: bytes):
        blob = self.storage.bucket(self.voice_bucket).blob(self.chunk_path(uid, job_id, chapter_id, index))
        blob.metadata = {"uid": uid, "jobId": job_id}
        blob.upload_from_string(audio, content_type="audio/wav")

    def output(self, uid: str, job_id: str, chapter_id: str, audio: bytes, expires_at: dt.datetime) -> str:
        path = f"users/{identity(uid)}/jobs/{identity(job_id)}/{identity(chapter_id)}.m4a"
        blob = self.storage.bucket(self.output_bucket).blob(path)
        # Explicit metadata replacement prevents any inherited Firebase download token.
        blob.metadata = {"uid": uid, "jobId": job_id, "expiresAt": expires_at.isoformat()}
        blob.cache_control = "private, no-store"
        blob.upload_from_string(audio, content_type="audio/mp4")
        return path

    def delete_prefix(self, bucket: str, prefix: str):
        from google.api_core.exceptions import NotFound
        for blob in self.storage.list_blobs(bucket, prefix=prefix):
            try:
                blob.delete(if_generation_match=blob.generation)
            except NotFound:
                pass

    def delete_job(self, uid: str, job_id: str):
        self.delete_prefix(self.voice_bucket, f"chunks/{identity(uid)}/{identity(job_id)}/")
        self.delete_prefix(self.output_bucket, f"users/{identity(uid)}/jobs/{identity(job_id)}/")

    def delete_recordings(self, uid: str, voice_id: str):
        self.delete_prefix(self.voice_bucket, f"enrollments/{identity(uid)}/{identity(voice_id)}/")

    def delete_account(self, uid: str):
        self.delete_prefix(self.voice_bucket, f"enrollments/{identity(uid)}/")
        self.delete_prefix(self.voice_bucket, f"chunks/{identity(uid)}/")
        self.delete_prefix(self.output_bucket, f"users/{identity(uid)}/")

    def cleanup_expired_objects(self):
        from google.api_core.exceptions import NotFound
        for blob in self.storage.list_blobs(self.output_bucket, prefix="users/"):
            expires = (blob.metadata or {}).get("expiresAt")
            if expires:
                try:
                    expired = dt.datetime.fromisoformat(expires) <= now()
                except (ValueError, TypeError):
                    expired = False
                if expired:
                    try:
                        blob.delete(if_generation_match=blob.generation)
                    except NotFound:
                        pass  # A simultaneous account/voice cleanup already erased it.

    def recording_enrollments(self) -> list[tuple[str, str]]:
        """Find immutable recording prefixes, including writes whose Firestore acknowledgement was lost."""
        prefixes = set()
        for blob in self.storage.list_blobs(self.voice_bucket, prefix="enrollments/"):
            parts = blob.name.split("/")
            if len(parts) != 4 or parts[0] != "enrollments" or parts[3] not in {"reference.json", "consent.json"}:
                continue
            try:
                prefixes.add((identity(parts[1]), identity(parts[2])))
            except SafeError:
                continue
        return sorted(prefixes)


class Accounts:
    def __init__(self, project: str):
        import firebase_admin
        from firebase_admin import auth
        try:
            self.app = firebase_admin.get_app()
        except ValueError:
            self.app = firebase_admin.initialize_app(options={"projectId": project})
        self.auth = auth

    def delete(self, uid: str):
        try:
            self.auth.revoke_refresh_tokens(identity(uid), app=self.app)
            self.auth.delete_user(uid, app=self.app)
        except self.auth.UserNotFoundError:
            pass
