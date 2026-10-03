import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";
import { KeyManagementServiceClient } from "@google-cloud/kms";
import { Storage } from "@google-cloud/storage";
import { EncryptedRecording, RecordingKind, RecordingObject, RecordingStore } from "./contracts";
import { connection, diagnostic } from "./diagnostics";

export function recordingAAD(uid: string, voiceId: string, kind: RecordingKind): Buffer {
  return Buffer.from(JSON.stringify({ version: 1, uid, voiceId, kind }), "utf8");
}
export function encryptRecording(audio: Buffer, uid: string, voiceId: string, kind: RecordingKind, key: Buffer, wrappedKey: Buffer, kmsKeyName: string): EncryptedRecording {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  cipher.setAAD(recordingAAD(uid, voiceId, kind));
  const ciphertext = Buffer.concat([cipher.update(audio), cipher.final(), cipher.getAuthTag()]);
  return { version: 1, uid, voiceId, kind, kmsKeyName, wrappedKey: wrappedKey.toString("base64"), iv: iv.toString("base64"), ciphertext: ciphertext.toString("base64") };
}
// Also used by cross-language contract tests; production decryption belongs to the private worker.
export function decryptRecording(envelope: EncryptedRecording, key: Buffer, uid: string, voiceId: string, kind: RecordingKind): Buffer {
  if (envelope.version !== 1 || envelope.uid !== uid || envelope.voiceId !== voiceId || envelope.kind !== kind) throw new Error("Recording context mismatch");
  const ciphertext = Buffer.from(envelope.ciphertext, "base64");
  const decipher = createDecipheriv("aes-256-gcm", key, Buffer.from(envelope.iv, "base64"));
  decipher.setAAD(recordingAAD(uid, voiceId, kind));
  decipher.setAuthTag(ciphertext.subarray(-16));
  return Buffer.concat([decipher.update(ciphertext.subarray(0, -16)), decipher.final()]);
}

export class KMSRecordingStore implements RecordingStore {
  constructor(private bucket: string, private kmsKeyName: string, private kms = new KeyManagementServiceClient(), private storage = new Storage()) {}
  async save(uid: string, enrollmentId: string, kind: RecordingKind, audio: Buffer): Promise<RecordingObject> {
    const key = randomBytes(32);
    try {
      const [wrapped] = await connection("kms", "wrap_recording_key", () => this.kms.encrypt({ name: this.kmsKeyName, plaintext: key }));
      if (!wrapped.ciphertext) throw new Error("KMS returned no encrypted key");
      const envelope = encryptRecording(audio, uid, enrollmentId, kind, key, Buffer.from(wrapped.ciphertext), this.kmsKeyName);
      const sha256 = createHash("sha256").update(audio).digest("hex");
      const path = `enrollments/${uid}/${enrollmentId}/${kind}.json`;
      const file = this.storage.bucket(this.bucket).file(path);
      try {
        await connection("storage", "write_recording", () => file.save(JSON.stringify(envelope), {
          resumable: false,
          metadata: { contentType: "application/json", cacheControl: "private, no-store", metadata: { sha256 } },
          preconditionOpts: { ifGenerationMatch: 0 },
        }), { recording_kind: kind, audio_bytes: audio.length });
      } catch (error) {
        if ((error as { code?: number }).code !== 412) throw error;
        diagnostic("debug", "recording_upload_reconciliation_started", { recording_kind: kind, http_status: 412 });
        // Recover an upload whose object write completed before its Firestore acknowledgement.
        const [metadata] = await connection("storage", "reconcile_recording_metadata", () => file.getMetadata());
        if (metadata.metadata?.sha256 !== sha256) throw new Error("An immutable recording already exists");
      }
      return { path, sha256, bytes: audio.length, duration: 0 };
    } finally {
      key.fill(0);
    }
  }
  async remove(path: string): Promise<void> {
    await connection("storage", "delete_recording", () => this.storage.bucket(this.bucket).file(path).delete({ ignoreNotFound: true }));
  }
}
