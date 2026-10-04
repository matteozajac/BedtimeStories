import test, { before, after } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { Firestore } from "firebase-admin/firestore";
import { initializeTestEnvironment, RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { CloudVoiceService } from "../service";
import { Principal, RecordingStore, TaskDispatcher, WorkerTask } from "../contracts";
import { BUILT_IN_VOICES } from "../voice-catalog";

let env: RulesTestEnvironment;
let db: Firestore;
const now = Date.now();
const principal = (uid: string): Principal => ({ uid, provider: "apple.com", authTime: now / 1000 });
const tasks: WorkerTask[] = [];
const recordings: RecordingStore = {
  save: async () => { throw new Error("Built-in narration must never request enrollment recordings."); },
  remove: async () => undefined,
};
const dispatcher: TaskDispatcher = { enqueue: async (task) => { tasks.push(task); } };
const api = (enabled = true) => new CloudVoiceService(db, recordings, dispatcher, { enabled: () => enabled, now: () => now });
const input = (voiceProfileId = "builtin-en-luna", language = "en-US", preview = false) => ({
  requestId: randomUUID(), voiceProfileId, language, preview,
  draftId: "draft", snapshotHash: "a".repeat(64),
  chapters: [{ id: "chapter", title: "Moon", paragraphs: [{ text: "A little rabbit found the moon.", style: "gentle" }] }],
});

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
    throw new Error("These isolation tests require Firebase emulators and must never target production.");
  }
  const projectId = "demo-bedtime-cloud";
  env = await initializeTestEnvironment({
    projectId,
    firestore: { rules: readFileSync(resolve("..", "firestore.rules"), "utf8") },
    storage: { rules: readFileSync(resolve("..", "storage.rules"), "utf8") },
  });
  db = new Firestore({ projectId });
});
after(async () => { await db?.terminate(); await env?.cleanup(); });

test("built-in narrators work without an enrolled voice and keep provider names out of client metadata", async () => {
  for (const voice of BUILT_IN_VOICES) {
    const uid = `builtin-${voice.id}`;
    const { jobId } = await api().startNarration(principal(uid), input(voice.id, voice.language));
    const job = (await db.doc(`privateAccounts/${uid}/jobs/${jobId}`).get()).data()!;
    const publicJob = (await db.doc(`users/${uid}/jobs/${jobId}`).get()).data()!;
    assert.equal(job.voiceProfileId, voice.id);
    assert.equal(job.language, voice.language);
    assert.equal(publicJob.state, "queued");
    assert.ok(!JSON.stringify(publicJob).includes(voice.providerVoice));
    assert.equal((await db.collection(`privateAccounts/${uid}/voices`).get()).empty, true);
    assert.equal((await db.doc(`privateAccounts/${uid}`).get()).get("limits.books"), 1);
  }
});

test("built-in requests preserve authentication, exact catalog, language and account tombstone gates", async () => {
  const startCount = tasks.length;
  await assert.rejects(api().startNarration(undefined, input()), { code: "unauthenticated" });
  await assert.rejects(api().startNarration({ ...principal("builtin-anon"), provider: "anonymous" }, input()), { code: "unauthenticated" });
  await assert.rejects(api(false).startNarration(principal("builtin-off"), input()), { code: "failed-precondition" });
  for (const request of [input("builtin-en-injected"), input("builtin-pl-luna", "en-US"), input("voice_stolen"), { ...input(), providerVoice: "Sulafat" }]) {
    await assert.rejects(api().startNarration(principal("builtin-injection"), request), { code: "invalid-argument" });
  }
  await assert.rejects(api().startNarration(principal("builtin-provider-name"), input("Sulafat")), { code: "not-found" });
  await db.doc("privateAccounts/builtin-deleted").set({ state: "deleted" });
  await assert.rejects(api().startNarration(principal("builtin-deleted"), input()), { code: "permission-denied" });
  assert.equal(tasks.length, startCount);
});

test("built-in narration charges once, permits cancellation, and stays isolated across accounts", async () => {
  const uid = "builtin-idempotent";
  const request = input();
  const first = await api().startNarration(principal(uid), request);
  const second = await api().startNarration(principal(uid), request);
  assert.equal(second.jobId, first.jobId);
  assert.equal((await db.doc(`privateAccounts/${uid}`).get()).get("limits.books"), 1);
  await assert.rejects(api().startNarration(principal(uid), input("builtin-en-milo")), { code: "resource-exhausted" });
  await assert.rejects(api().cancelNarration(principal("builtin-other"), { jobId: first.jobId }), { code: "not-found" });
  await api().cancelNarration(principal(uid), { jobId: first.jobId });
  const third = await api().startNarration(principal(uid), input("builtin-en-milo"));
  assert.notEqual(third.jobId, first.jobId);
  assert.equal((await db.doc(`privateAccounts/${uid}`).get()).get("limits.books"), 2);
});

test("personal voice ownership and approval remain mandatory beside the built-in catalog", async () => {
  await db.doc("privateAccounts/builtin-personal-owner").set({ state: "active" });
  await db.doc("privateAccounts/builtin-personal-owner/voices/owned-profile").set({
    uid: "builtin-personal-owner", voiceId: "owned-profile", status: "awaitingApproval", providerVoice: { ciphertext: "encrypted" },
  });
  await assert.rejects(api().startNarration(principal("builtin-personal-owner"), input("owned-profile")), { code: "failed-precondition" });
  await assert.rejects(api().startNarration(principal("builtin-personal-foreign"), input("owned-profile", "en-US", true)), { code: "not-found" });
  await api().startNarration(principal("builtin-personal-owner"), input("owned-profile", "en-US", true));
  await assert.rejects(api().deleteVoice(principal("builtin-personal-owner"), { profileId: "builtin-en-luna" }), { code: "not-found" });
});
