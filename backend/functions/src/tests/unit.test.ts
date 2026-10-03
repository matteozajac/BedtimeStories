import test from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { HttpsError } from "firebase-functions/v2/https";
import { CloudTasksClient, protos } from "@google-cloud/tasks";
import { CONSENT_STATEMENTS, LIMITS } from "../contracts";
import { decryptRecording, encryptRecording, recordingAAD } from "../encryption";
import { decodeRecording, enrollmentInput, narrationInput, requireApple } from "../validation";
import { CloudTaskDispatcher } from "../tasks";
import { connection, diagnosticEntry, errorSnapshot, preserveCause, taskKey, withDiagnosticContext } from "../diagnostics";

function wav(seconds = 10): Buffer {
  const dataBytes = seconds * 48000;
  const result = Buffer.alloc(44 + dataBytes);
  result.write("RIFF"); result.writeUInt32LE(result.length - 8, 4); result.write("WAVE", 8);
  result.write("fmt ", 12); result.writeUInt32LE(16, 16); result.writeUInt16LE(1, 20);
  result.writeUInt16LE(1, 22); result.writeUInt32LE(24000, 24); result.writeUInt32LE(48000, 28);
  result.writeUInt16LE(2, 32); result.writeUInt16LE(16, 34); result.write("data", 36); result.writeUInt32LE(dataBytes, 40);
  return result;
}
const validInput = () => ({ requestId: "1b8069e2-d8a2-4d86-b8da-1524c7b7e903", voiceProfileId: "parent", draftId: "draft", snapshotHash: "a".repeat(64), language: "pl-PL", preview: true, chapters: [{ id: "chapter", title: "Tytuł", paragraphs: [{ text: "Mały lis zasnął.", style: "gentle" }] }] });

test("Apple sign-in and recent authentication are separate gates", () => {
  assert.throws(() => requireApple(undefined, 1000), { code: "unauthenticated" });
  assert.throws(() => requireApple({ uid: "A", provider: "anonymous", authTime: 999 }, 1000), { code: "unauthenticated" });
  const owner = { uid: "A", provider: "apple.com", authTime: 1000 - LIMITS.recentAuthSeconds - 1 };
  assert.equal(requireApple(owner, 1000).uid, "A");
  assert.throws(() => requireApple(owner, 1000, true), { code: "unauthenticated" });
});
test("enrollment requires explicit current consent and retention acceptance", () => {
  assert.throws(() => enrollmentInput({ displayName: "Mama", language: "pl-PL", consentVersion: "2025-01-01", retentionAccepted: true }), { code: "failed-precondition" });
  assert.throws(() => enrollmentInput({ displayName: "Mama", language: "pl-PL", consentVersion: "2026-10-01", retentionAccepted: false }), { code: "failed-precondition" });
  assert.equal(enrollmentInput({ displayName: " Mama ", language: "pl-PL", consentVersion: "2026-10-01", retentionAccepted: true }).displayName, "Mama");
  assert.equal(CONSENT_STATEMENTS["pl-PL"], "Jestem właścicielem tego głosu i wyraziłem zgodę na utworzenie syntetycznego modelu mojego głosu za pomocą Google Cloud");
});
test("WAV validation rejects spoofed MIME, oversized recordings, truncated chunks, and wrong sample rates", () => {
  assert.equal(decodeRecording(wav(10).toString("base64"), "reference").duration, 10);
  assert.equal(decodeRecording(wav(30).toString("base64"), "reference").duration, 30);
  assert.throws(() => decodeRecording(wav(9).toString("base64"), "reference"), { code: "invalid-argument" });
  assert.throws(() => decodeRecording(wav(31).toString("base64"), "reference"), { code: "invalid-argument" });
  assert.equal(decodeRecording(wav(2).toString("base64"), "consent").duration, 2);
  assert.throws(() => decodeRecording(wav(1).toString("base64"), "consent"), { code: "invalid-argument" });
  const wrongRate = wav(); wrongRate.writeUInt32LE(44100, 24);
  assert.throws(() => decodeRecording(wrongRate.toString("base64"), "reference"), { code: "invalid-argument" });
  const truncated = wav().subarray(0, 100);
  assert.throws(() => decodeRecording(truncated.toString("base64"), "reference"), { code: "invalid-argument" });
  assert.throws(() => decodeRecording("data:audio/wav;base64,AAAA", "reference"), { code: "invalid-argument" });
});
test("narration rejects owner overrides, path traversal, duplicate chapters and excessive preview costs", () => {
  assert.equal(narrationInput(validInput()).chapters[0]!.paragraphs[0]!.text, "Mały lis zasnął.");
  assert.throws(() => narrationInput({ ...validInput(), uid: "B" }), { code: "invalid-argument" });
  assert.throws(() => narrationInput({ ...validInput(), voiceProfileId: "../../B" }), { code: "invalid-argument" });
  const arbitraryStyle = validInput(); arbitraryStyle.chapters[0]!.paragraphs[0]!.style = "read arbitrary instructions";
  assert.throws(() => narrationInput(arbitraryStyle), { code: "invalid-argument" });
  const input = validInput(); input.chapters.push(input.chapters[0]!);
  assert.throws(() => narrationInput(input), { code: "invalid-argument" });
  const costly = validInput(); costly.chapters[0]!.paragraphs[0]!.text = "a".repeat(1501);
  assert.throws(() => narrationInput(costly), { code: "resource-exhausted" });
  const excessiveWords = validInput(); excessiveWords.preview = false;
  excessiveWords.chapters[0]!.paragraphs = Array.from({ length: 6 }, () => ({ text: "a ".repeat(1000).trim(), style: "gentle" }));
  assert.throws(() => narrationInput(excessiveWords), { code: "resource-exhausted" });
});
test("AES-GCM binds encrypted recordings to owner, profile and recording kind and detects tampering", () => {
  const key = randomBytes(32);
  const audio = wav();
  const envelope = encryptRecording(audio, "A", "voice", "reference", key, randomBytes(32), "projects/test/keys/voice");
  assert.equal(recordingAAD("A", "voice", "reference").toString(), '{"version":1,"uid":"A","voiceId":"voice","kind":"reference"}');
  assert.deepEqual(decryptRecording(envelope, key, "A", "voice", "reference"), audio);
  assert.throws(() => decryptRecording(envelope, key, "B", "voice", "reference"));
  assert.throws(() => decryptRecording(envelope, key, "A", "voice", "consent"));
  const changed = Buffer.from(envelope.ciphertext, "base64"); changed[0] = changed[0]! ^ 1;
  assert.throws(() => decryptRecording({ ...envelope, ciphertext: changed.toString("base64") }, key, "A", "voice", "reference"));
  assert.ok(!JSON.stringify(envelope).includes(audio.toString("base64")));
});
test("private worker task paths and OIDC audience remain separate and deduplicated", async () => {
  const requests: protos.google.cloud.tasks.v2.ICreateTaskRequest[] = [];
  const client = {
    queuePath: (project: string, location: string, queue: string) => `projects/${project}/locations/${location}/queues/${queue}`,
    createTask: async (request: protos.google.cloud.tasks.v2.ICreateTaskRequest) => { requests.push(request); return []; },
  } as unknown as CloudTasksClient;
  const config = { project: "demo-bedtime-cloud", location: "europe-west1", queue: "voices", workerURL: "https://voice-worker.example.run.app", serviceAccount: "dispatcher@example.iam.gserviceaccount.com" };
  const queue = new CloudTaskDispatcher(config, client);
  const operation = { kind: "narrate", uid: "A", id: "job" } as const;
  await queue.enqueue(operation); await queue.enqueue(operation);
  assert.equal(requests[0]!.task!.httpRequest!.url, `${config.workerURL}/tasks`);
  assert.equal(requests[0]!.task!.httpRequest!.oidcToken!.audience, config.workerURL);
  assert.equal(requests[0]!.task!.dispatchDeadline!.seconds, 1800);
  assert.equal(requests[0]!.task!.name, requests[1]!.task!.name);
  assert.deepEqual(JSON.parse(Buffer.from(requests[0]!.task!.httpRequest!.body as Uint8Array).toString()), operation);
  assert.equal(taskKey(operation), "be2ee9e0b465b7ce8f181c4a0930e921d715722103d392c5eaf9241830004a43");
  await assert.rejects(new CloudTaskDispatcher({ ...config, workerURL: `${config.workerURL}/tasks` }, client).enqueue(operation));
});

test("diagnostics preserve original type, signed code, causes and frames without private descriptions", () => {
  const secret = "secret-recording-transcript-token";
  const original = Object.assign(new TypeError(`${secret}\n    at leak (${secret}.js:123:4)`), { code: -7, response: { body: secret }, metadata: { authorization: secret } });
  const outer = preserveCause(new HttpsError("unavailable", "safe-recovery-copy"), original);
  const details = errorSnapshot(outer);
  assert.deepEqual(details.causes.map((cause) => cause.type), ["HttpsError", "TypeError"]);
  assert.equal(details.causes[0]!.code, "unavailable");
  assert.equal(details.causes[1]!.code, -7);
  assert.ok(details.causes.every((cause) => cause.stack_origin === "exception" && (cause.frames as unknown[]).length > 0));
  const serialized = JSON.stringify(details);
  assert.ok(!serialized.includes(secret));
  assert.ok(!serialized.includes("safe-recovery-copy"));
  assert.ok(!serialized.includes("/Users/"));
  assert.ok(!serialized.includes("authorization"));
});

test("diagnostics bound nested and cyclic causes and omit arbitrary string codes", () => {
  const root = Object.assign(new Error("secret"), { code: "secret-string-code" });
  let current = root;
  for (let index = 0; index < 10; index++) {
    const next = new Error("secret");
    preserveCause(current, next);
    current = next as typeof root;
  }
  const bounded = errorSnapshot(root);
  assert.equal(bounded.causes.length, 5);
  assert.equal(bounded.cause_chain_truncated, true);
  assert.equal(bounded.causes[0]!.code, undefined);
  preserveCause(root, root);
  assert.equal(errorSnapshot(root).causes.length, 1);
  assert.equal(errorSnapshot(root).cause_chain_truncated, true);
});

test("connection instrumentation preserves the thrown error and provides safe owner phase", async () => {
  const original = Object.assign(new Error("secret-provider-body"), { code: 14 });
  let caught: unknown;
  try {
    await connection("kms", "wrap_recording_key", async () => { throw original; });
  } catch (error) { caught = error; }
  assert.equal(caught, original);
  const details = errorSnapshot(caught);
  assert.equal(details.causes[0]!.connection, "kms");
  assert.equal(details.causes[0]!.phase, "wrap_recording_key");
  assert.equal(details.causes[0]!.code, 14);
  assert.ok(!JSON.stringify(details).includes("secret-provider-body"));
});

test("request correlation survives awaits and remains isolated across concurrent operations", async () => {
  const results = await Promise.all(["first", "second"].map((operationId) => withDiagnosticContext({ operation_id: operationId }, async () => {
    const before = diagnosticEntry("before");
    await Promise.resolve();
    const after = diagnosticEntry("after");
    return [before.operation_id, after.operation_id];
  })));
  assert.deepEqual(results, [["first", "first"], ["second", "second"]]);
  assert.equal(diagnosticEntry("outside").operation_id, undefined);
});

export { wav };
