"""AES-GCM envelope encryption compatible with the Functions enrollment uploader."""
from __future__ import annotations

import base64
import os

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from core import SafeError, canonical_aad
from diagnostics import observed


class Envelope:
    @observed("kms", "initialize")
    def __init__(self, kms_key_name: str, kms=None):
        if kms is None:
            from google.cloud import kms as cloud_kms
            kms = cloud_kms.KeyManagementServiceClient()
        self.kms, self.key_name = kms, kms_key_name

    @observed("kms", "encrypt_envelope")
    def encrypt(self, plaintext: bytes, uid: str, voice_id: str, kind: str) -> dict:
        key, iv = AESGCM.generate_key(bit_length=256), os.urandom(12)
        aad = canonical_aad(uid, voice_id, kind)
        wrapped = self.kms.encrypt(request={"name": self.key_name, "plaintext": key}).ciphertext
        return {"version": 1, "uid": uid, "voiceId": voice_id, "kind": kind, "kmsKeyName": self.key_name,
                "wrappedKey": base64.b64encode(wrapped).decode(), "iv": base64.b64encode(iv).decode(),
                "ciphertext": base64.b64encode(AESGCM(key).encrypt(iv, plaintext, aad)).decode()}

    @observed("kms", "decrypt_envelope")
    def decrypt(self, envelope: dict, uid: str, voice_id: str, kind: str) -> bytes:
        if not isinstance(envelope, dict) or any(envelope.get(field) != value for field, value in {
                "version": 1, "uid": uid, "voiceId": voice_id, "kind": kind, "kmsKeyName": self.key_name}.items()):
            raise SafeError("envelope_owner_mismatch")
        try:
            wrapped, iv, encrypted = [base64.b64decode(envelope[field], validate=True)
                                      for field in ["wrappedKey", "iv", "ciphertext"]]
            if len(iv) != 12 or len(encrypted) < 16:
                raise ValueError()
            key = self.kms.decrypt(request={"name": self.key_name, "ciphertext": wrapped}).plaintext
            if len(key) != 32:
                raise ValueError()
            return AESGCM(key).decrypt(iv, encrypted, canonical_aad(uid, voice_id, kind))
        except (KeyError, ValueError, TypeError, InvalidTag) as error:
            raise SafeError("invalid_envelope") from error
