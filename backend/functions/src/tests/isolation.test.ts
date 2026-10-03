import test, { before, after } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { initializeTestEnvironment, RulesTestEnvironment, assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, collection, getDocs } from "firebase/firestore";
import { ref, getBytes, uploadBytes, listAll } from "firebase/storage";
import { Firestore, Timestamp } from "firebase-admin/firestore";
import { CloudVoiceService } from "../service";
import { Principal, RecordingStore, TaskDispatcher, WorkerTask } from "../contracts";

const projectId = "demo-bedtime-cloud";
let env: RulesTestEnvironment;
let db: Firestore;
const now = Date.now();
const principal = (uid: string): Principal => ({ uid, provider: "apple.com", authTime: now / 1000 });
const tasks: WorkerTask[] = [];
const recordings: RecordingStore = {
  save: async (uid, id, kind, audio) => ({ path: `enrollments/${uid}/${id}/${kind}.json`, sha256: "a".repeat(64), bytes: audio.length, duration: 10 }),
  remove: async () => undefined,
};
const dispatcher: TaskDispatcher = { enqueue: async (task) => { tasks.push(task); } };
const api = (enabled = true) => new CloudVoiceService(db, recordings, dispatcher, { enabled: () => enabled, now: () => now });
const context = (uid: string, provider: "apple.com" | "anonymous" = "apple.com") => env.authenticatedContext(uid, { firebase: { sign_in_provider: provider } });
const input = (voiceProfileId: string, preview = false) => ({ requestId: randomUUID(), voiceProfileId, draftId: "draft", snapshotHash: "a".repeat(64), language: "en-US", preview, chapters: [{ id: "chapter", title: "A story", paragraphs: [{ text: "A fox slept under the stars.", style: "gentle" }] }] });
async function seedVoice(uid: string, id = "voice", status = "ready") {
  await db.doc(`privateAccounts/${uid}`).set({ state: "active" });
  await db.doc(`privateAccounts/${uid}/voices/${id}`).set({ uid, voiceId: id, status, providerVoice: { ciphertext: "encrypted" } });
  await db.doc(`users/${uid}/voices/${id}`).set({ id, displayName: "Parent", status });
}
before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) throw new Error("Run through firebase emulators:exec. These tests must never target production.");
  env = await initializeTestEnvironment({ projectId, firestore: { rules: readFileSync(resolve("..", "firestore.rules"), "utf8") }, storage: { rules: readFileSync(resolve("..", "storage.rules"), "utf8") } });
  db = new Firestore({ projectId });
});
after(async () => { await db?.terminate(); await env?.cleanup(); });

test("Firestore: A can read its public metadata but cannot read/list/write B or any private mapping", async () => {
  await seedVoice("rulesA"); await seedVoice("rulesB");
  const a = context("rulesA").firestore();
  await assertSucceeds(getDoc(doc(a, "users/rulesA/voices/voice")));
  await assertSucceeds(getDocs(collection(a, "users/rulesA/voices")));
  await assertFails(getDoc(doc(a, "users/rulesB/voices/voice")));
  await assertFails(getDocs(collection(a, "users/rulesB/voices")));
  await assertFails(setDoc(doc(a, "users/rulesA/voices/voice"), { status: "ready", providerVoice: "stolen" }));
  await assertFails(getDoc(doc(a, "privateAccounts/rulesA/voices/voice")));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "users/rulesA/voices/voice")));
  await assertFails(getDoc(doc(context("rulesA", "anonymous").firestore(), "users/rulesA/voices/voice")));
});
test("Storage: only authenticated owner can fetch ready unexpired output; sources/writes/list are private", async () => {
  await db.doc("privateAccounts/storageA").set({ state: "active" });
  await db.doc("users/storageA/jobs/job").set({ state: "ready", expiresAt: Timestamp.fromMillis(now + 600000) });
  await env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), "users/storageA/jobs/job/chapter.m4a"), Buffer.from("private audio"));
    await uploadBytes(ref(ctx.storage(), "enrollments/storageA/voice/reference.json"), Buffer.from("encrypted"));
  });
  await assertSucceeds(getBytes(ref(context("storageA").storage(), "users/storageA/jobs/job/chapter.m4a")));
  await assertFails(getBytes(ref(context("storageB").storage(), "users/storageA/jobs/job/chapter.m4a")));
  await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), "users/storageA/jobs/job/chapter.m4a")));
  await assertFails(getBytes(ref(context("storageA").storage(), "enrollments/storageA/voice/reference.json")));
  await assertFails(uploadBytes(ref(context("storageA").storage(), "users/storageA/jobs/job/chapter.m4a"), Buffer.from("overwrite")));
  await assertFails(listAll(ref(context("storageA").storage(), "users/storageA/jobs/job")));
  await db.doc("users/storageA/jobs/job").update({ expiresAt: Timestamp.fromMillis(now - 1) });
  await assertFails(getBytes(ref(context("storageA").storage(), "users/storageA/jobs/job/chapter.m4a")));
});
test("Callable service: foreign IDs and owner overrides never reach task dispatch", async () => {
  await seedVoice("apiB", "bVoice");
  const startCount = tasks.length;
  await assert.rejects(api().startNarration(principal("apiA"), input("bVoice")), { code: "not-found" });
  await assert.rejects(api().deleteVoice(principal("apiA"), { profileId: "bVoice" }), { code: "not-found" });
  await assert.rejects(api().startNarration(principal("apiB"), { ...input("bVoice"), uid: "apiA" }), { code: "invalid-argument" });
  assert.equal(tasks.length, startCount);
});
test("Narration idempotency freezes payload and charges quota once", async () => {
  await seedVoice("idempotent");
  const request = input("voice");
  const first = await api().startNarration(principal("idempotent"), request);
  const second = await api().startNarration(principal("idempotent"), request);
  assert.equal(first.jobId, second.jobId);
  assert.equal((await db.doc("privateAccounts/idempotent").get()).get("limits.books"), 1);
  await assert.rejects(api().startNarration(principal("idempotent"), { ...request, draftId: "another" }), { code: "already-exists" });
});
test("One active full book prevents different request IDs from duplicating chargeable work; previews are separate", async () => {
  await seedVoice("singleBook");
  const { jobId } = await api().startNarration(principal("singleBook"), input("voice"));
  await assert.rejects(api().startNarration(principal("singleBook"), input("voice")), { code: "resource-exhausted" });
  const preview = await api().startNarration(principal("singleBook"), input("voice", true));
  assert.equal((await db.doc(`users/singleBook/jobs/${preview.jobId}`).get()).get("preview"), true);
  assert.equal((await db.doc(`privateAccounts/singleBook`).get()).get("limits.books"), 1);
  await api().cancelNarration(principal("singleBook"), { jobId });
  await api().startNarration(principal("singleBook"), input("voice"));
});
test("Concurrent full-book requests serialize through account quota without duplicate work", async () => {
  await seedVoice("concurrentBook");
  const results = await Promise.allSettled([
    api().startNarration(principal("concurrentBook"), input("voice")),
    api().startNarration(principal("concurrentBook"), input("voice")),
  ]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal((await db.doc("privateAccounts/concurrentBook").get()).get("limits.books"), 1);
});
test("Enrollment uses numeric expiry, checks ownership and requires immutable dual recordings before one profile", async () => {
  const enrollment = await api().beginVoiceEnrollment(principal("enrollment"), { displayName: "Parent", language: "en-US", consentVersion: "2026-10-01", retentionAccepted: true });
  assert.equal(enrollment.expiresAt, now / 1000 + 3600);
  const bytes = Buffer.alloc(44 + 10 * 48000);
  bytes.write("RIFF"); bytes.writeUInt32LE(bytes.length - 8, 4); bytes.write("WAVE", 8);
  bytes.write("fmt ", 12); bytes.writeUInt32LE(16, 16); bytes.writeUInt16LE(1, 20); bytes.writeUInt16LE(1, 22);
  bytes.writeUInt32LE(24000, 24); bytes.writeUInt32LE(48000, 28); bytes.writeUInt16LE(2, 32); bytes.writeUInt16LE(16, 34);
  bytes.write("data", 36); bytes.writeUInt32LE(bytes.length - 44, 40);
  const reference = { enrollmentId: enrollment.enrollmentId, kind: "reference", audioBase64: bytes.toString("base64") };
  await assert.rejects(api().uploadEnrollmentRecording(principal("foreignEnrollment"), reference), { code: "not-found" });
  await api().uploadEnrollmentRecording(principal("enrollment"), reference);
  await api().uploadEnrollmentRecording(principal("enrollment"), reference);
  await assert.rejects(api().completeVoiceEnrollment(principal("enrollment"), { enrollmentId: enrollment.enrollmentId }), { code: "failed-precondition" });
  const changed = Buffer.from(bytes); changed[44] = 1;
  await assert.rejects(api().uploadEnrollmentRecording(principal("enrollment"), { ...reference, audioBase64: changed.toString("base64") }), { code: "failed-precondition" });
  await api().uploadEnrollmentRecording(principal("enrollment"), { ...reference, kind: "consent" });
  const first = await api().completeVoiceEnrollment(principal("enrollment"), { enrollmentId: enrollment.enrollmentId });
  const again = await api().completeVoiceEnrollment(principal("enrollment"), { enrollmentId: enrollment.enrollmentId });
  assert.equal(first.profileId, again.profileId);
  const publicProfile = (await db.doc(`users/enrollment/voices/${first.profileId}`).get()).data();
  assert.equal(publicProfile!.uid, "enrollment");
  assert.equal(publicProfile!.providerVoice, undefined);
  assert.equal(publicProfile!.referenceObject, undefined);
});
test("Awaiting approval permits preview, blocks full narration, and approval is owner-only", async () => {
  await seedVoice("approval", "voice", "awaitingApproval");
  await assert.rejects(api().startNarration(principal("approval"), input("voice")), { code: "failed-precondition" });
  await api().startNarration(principal("approval"), input("voice", true));
  await assert.rejects(api().approveVoice(principal("another"), { profileId: "voice" }), { code: "not-found" });
  await api().approveVoice(principal("approval"), { profileId: "voice" });
  await api().startNarration(principal("approval"), input("voice"));
  assert.equal((await db.doc("users/approval/voices/voice").get()).get("status"), "ready");
});
test("A tombstone closes API/rule access immediately and deletion requires recent authentication", async () => {
  await seedVoice("deletion");
  const stale = { ...principal("deletion"), authTime: now / 1000 - 301 };
  await assert.rejects(api().deleteAccount(stale, {}), { code: "unauthenticated" });
  await api().deleteAccount(principal("deletion"), {});
  await assert.rejects(api().startNarration(principal("deletion"), input("voice")), { code: "permission-denied" });
  await assert.rejects(api().beginVoiceEnrollment(principal("deletion"), { displayName: "Parent", language: "en-US", consentVersion: "2026-10-01", retentionAccepted: true }), { code: "permission-denied" });
  await assertFails(getDoc(doc(context("deletion").firestore(), "users/deletion/voices/voice")));
});
test("feature switch stops new expensive operations while cancellation remains available", async () => {
  await seedVoice("flag");
  await assert.rejects(api(false).startNarration(principal("flag"), input("voice")), { code: "failed-precondition" });
  const { jobId } = await api().startNarration(principal("flag"), input("voice"));
  await api(false).cancelNarration(principal("flag"), { jobId });
  assert.equal((await db.doc(`privateAccounts/flag/jobs/${jobId}`).get()).get("cancelRequested"), true);
});
test("dispatch failure keeps durable outbox and scheduled retry repairs it", async () => {
  await seedVoice("outbox");
  const broken = new CloudVoiceService(db, recordings, { enqueue: async () => { throw new Error("temporary queue failure"); } }, { enabled: () => true, now: () => now });
  const { jobId } = await broken.startNarration(principal("outbox"), input("voice"));
  const reference = db.doc(`privateAccounts/outbox/jobs/${jobId}`);
  assert.equal((await reference.get()).get("dispatchPending"), true);
  await api().retryPendingDispatches();
  assert.equal((await reference.get()).get("dispatchPending"), false);
});
test("a late enrollment dispatch cannot erase a newer voice deletion outbox", async () => {
  await seedVoice("outboxDeletionRace", "voice", "processing");
  const profile = db.doc("privateAccounts/outboxDeletionRace/voices/voice");
  await profile.update({ taskKind: "enroll", dispatchPending: true });
  const racing = new CloudVoiceService(db, recordings, { enqueue: async (task) => {
    if (task.uid === "outboxDeletionRace" && task.kind === "enroll") {
      await profile.update({ status: "deleting", taskKind: "deleteVoice", dispatchPending: true });
    }
  } }, { enabled: () => true, now: () => now });
  await racing.retryPendingDispatches();
  assert.equal((await profile.get()).get("dispatchPending"), true);
  assert.equal((await profile.get()).get("taskKind"), "deleteVoice");
  await api().retryPendingDispatches();
  assert.equal((await profile.get()).get("dispatchPending"), false);
  assert.ok(tasks.some((task) => task.uid === "outboxDeletionRace" && task.kind === "deleteVoice"));
});

test("Story service: Apple auth, independent owner quotas and concurrent lease fence", async () => {
  const { StoryGenerationService } = await import("../story");
  let finish!: (value: unknown) => void, started!: () => void;
  const pending = new Promise<unknown>((resolve) => { finish = resolve; });
  const ready = new Promise<void>((resolve) => { started = resolve; });
  let calls = 0;
  const provider = { generate: async (input: { description: string }) => { calls++; if (input.description === "held") { started(); return pending; } return storyBook(); } };
  const service = new StoryGenerationService(db, provider, { enabled: () => true, now: () => now });
  await assert.rejects(service.generate(undefined, storyRequest()), { code: "unauthenticated" });
  const a = service.generate(principal("storyA"), { ...storyRequest(), description: "held" });
  await ready;
  await assert.rejects(service.generate(principal("storyA"), storyRequest()), { code: "resource-exhausted" });
  assert.equal(calls, 1);
  assert.equal((await db.doc("privateAccounts/storyA").get()).get("storyUsage.count"), 1);
  assert.equal((await service.generate(principal("storyB"), storyRequest())).title, "Lis i księżyc");
  finish(storyBook()); await a;
  assert.equal((await db.doc("privateAccounts/storyA").get()).get("storyGeneration"), undefined);
  await db.doc("privateAccounts/storyB").set({ storyUsage: { day: new Date(now).toISOString().slice(0, 10), count: 10 }, limits: { day: "old", books: 3 } }, { merge: true });
  await assert.rejects(service.generate(principal("storyB"), storyRequest()), { code: "resource-exhausted" });
  const tomorrow = new StoryGenerationService(db, provider, { enabled: () => true, now: () => now + 86400000 });
  await tomorrow.generate(principal("storyB"), storyRequest());
  const account = await db.doc("privateAccounts/storyB").get();
  assert.equal(account.get("storyUsage.count"), 1); assert.equal(account.get("limits.books"), 3);
});

test("Story service: deletion during inference rejects result without reviving account", async () => {
  const { StoryGenerationService } = await import("../story");
  let finish!: (value: unknown) => void, started!: () => void;
  const pending = new Promise<unknown>((resolve) => { finish = resolve; });
  const ready = new Promise<void>((resolve) => { started = resolve; });
  const service = new StoryGenerationService(db, { generate: async () => { started(); return pending; } }, { enabled: () => true, now: () => now });
  const result = service.generate(principal("storyDelete"), storyRequest());
  await ready;
  await api().deleteAccount(principal("storyDelete"), {});
  finish(storyBook()); await assert.rejects(result, { code: "permission-denied" });
  const account = await db.doc("privateAccounts/storyDelete").get();
  assert.equal(account.get("state"), "deleting"); assert.equal(account.get("storyUsage"), undefined); assert.equal(account.get("storyGeneration"), undefined);
});

test("Story service: safe provider failure releases lease and incomplete output retries once", async () => {
  const { StoryGenerationService } = await import("../story");
  const failing = new StoryGenerationService(db, { generate: async () => { throw new Error("private provider details"); } }, { enabled: () => true, now: () => now });
  await assert.rejects(failing.generate(principal("storyFailure"), storyRequest()), (error: unknown) => (error as { code: string; message: string }).code === "unavailable" && !(error as Error).message.includes("private"));
  assert.equal((await db.doc("privateAccounts/storyFailure").get()).get("storyGeneration"), undefined);
  const counts: (number | undefined)[] = [];
  const contexts: unknown[] = [];
  const retrying = new StoryGenerationService(db, { generate: async (_, previous, previousBook) => { counts.push(previous); contexts.push(previousBook); return counts.length === 1 ? { ...storyBook(), chapters: [{ title: "Noc", text: Array(60).fill("księżyc").join(" ") + "." }] } : storyBook(); } }, { enabled: () => true, now: () => now });
  await retrying.generate(principal("storyFailure"), storyRequest());
  assert.deepEqual(counts, [undefined, 60]);
  assert.equal(contexts[0], undefined);
  assert.equal((contexts[1] as { title: string }).title, "Lis i księżyc");
  assert.equal((await db.doc("privateAccounts/storyFailure").get()).get("storyUsage.count"), 2);
});

function storyRequest() { return { description: "Lis wraca do domu.", language: "polish", readerAge: "3–5", readingMinutes: 1, wordsPerMinute: 80, consentVersion: "2026-10-04", cloudProcessingAccepted: true }; }
function storyBook() { return { title: "Lis i księżyc", summary: "Lis wraca do domu.", chapters: [{ title: "Pod gwiazdami", text: Array(79).fill("księżyc").join(" ") + " zasnął." }], illustrationGuide: "An amber fox under stars." }; }

test("Story service: an expired request cannot clear the replacement lease", async () => {
  const { StoryGenerationService } = await import("../story");
  let time = now, calls = 0;
  let firstFinish!: (value: unknown) => void, secondFinish!: (value: unknown) => void;
  let firstStart!: () => void, secondStart!: () => void;
  const firstPending = new Promise<unknown>((r) => { firstFinish = r; });
  const secondPending = new Promise<unknown>((r) => { secondFinish = r; });
  const firstReady = new Promise<void>((r) => { firstStart = r; });
  const secondReady = new Promise<void>((r) => { secondStart = r; });
  const service = new StoryGenerationService(db, { generate: async () => { if (++calls === 1) { firstStart(); return firstPending; } secondStart(); return secondPending; } }, { enabled: () => true, now: () => time });
  const first = service.generate(principal("storyExpired"), storyRequest()); await firstReady;
  time += 421000;
  const second = service.generate(principal("storyExpired"), storyRequest()); await secondReady;
  const replacement = (await db.doc("privateAccounts/storyExpired").get()).get("storyGeneration.lease");
  firstFinish(storyBook()); await assert.rejects(first, { code: "permission-denied" });
  assert.equal((await db.doc("privateAccounts/storyExpired").get()).get("storyGeneration.lease"), replacement);
  secondFinish(storyBook()); await second;
  assert.equal((await db.doc("privateAccounts/storyExpired").get()).get("storyGeneration"), undefined);
});

test("Story service: near-complete long books receive one validated bounded scene repair", async () => {
  const { StoryGenerationService } = await import("../story");
  let calls = 0, repairs = 0;
  const incomplete = { ...storyBook(), chapters: [{ title: "Pod gwiazdami", text: Array(899).fill("księżyc").join(" ") + " zasnął." }] };
  const service = new StoryGenerationService(db, {
    generate: async () => { calls++; return incomplete; },
    supplement: async (_, book, missingWords) => {
      repairs++; assert.equal(missingWords, 60);
      return { ...book, chapters: book.chapters.map((chapter) => ({ ...chapter, text: chapter.text + " " + Array(179).fill("cisza").join(" ") + " zapadła." })) };
    },
  }, { enabled: () => true, now: () => now });
  const result = await service.generate(principal("storyRepair"), { ...storyRequest(), readingMinutes: 15 });
  assert.equal(calls, 2); assert.equal(repairs, 1); assert.equal(result.title, incomplete.title);
  assert.equal((await db.doc("privateAccounts/storyRepair").get()).get("storyUsage.count"), 1);
  assert.equal((await db.doc("privateAccounts/storyRepair").get()).get("storyGeneration"), undefined);
});

test("Story service: substantially incomplete books do not trigger an unbounded scene repair", async () => {
  const { StoryGenerationService } = await import("../story");
  let calls = 0, repairs = 0;
  const short = { ...storyBook(), chapters: [{ title: "Pod gwiazdami", text: Array(499).fill("księżyc").join(" ") + " zasnął." }] };
  const service = new StoryGenerationService(db, {
    generate: async () => { calls++; return short; },
    supplement: async () => { repairs++; return short; },
  }, { enabled: () => true, now: () => now });
  await assert.rejects(service.generate(principal("storyTooShort"), { ...storyRequest(), readingMinutes: 15 }), { code: "internal" });
  assert.equal(calls, 2); assert.equal(repairs, 0);
});
