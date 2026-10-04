import test, { before, after } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { Firestore, Timestamp } from "firebase-admin/firestore";
import { Message } from "firebase-admin/messaging";
import { HttpsError } from "firebase-functions/v2/https";
import { initializeTestEnvironment, RulesTestEnvironment, assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { collection, doc, getDoc, getDocs, query, setDoc, where } from "firebase/firestore";
import { Principal } from "../contracts";
import { CloudVoiceService } from "../service";
import { OperationNotificationService } from "../operationNotifications";
import { StoryProvider } from "../story";
import { StoryJobService, StoryTask } from "../storyJobs";

const projectId = "demo-bedtime-cloud";
let env: RulesTestEnvironment, db: Firestore;
const now = Date.now(), principal = (uid: string): Principal => ({ uid, provider: "apple.com", authTime: now / 1000 });
const request = () => ({ requestId: randomUUID(), description: "A fox finds a quiet home.", language: "english", readerAge: "3–5", readingMinutes: 1, wordsPerMinute: 80, consentVersion: "2026-10-04", cloudProcessingAccepted: true });
const book = () => ({ title: "A quiet home", summary: "A fox finds its home.", chapters: [{ title: "Under the stars", text: Array(79).fill("moon").join(" ") + " slept." }], illustrationGuide: "An amber fox under stars." });
const tasks: StoryTask[] = [];
const api = (provider: StoryProvider = { generate: async () => book() }, clock = () => now) => new StoryJobService(db, provider, { enqueue: async (task) => { tasks.push(task); } }, { enabled: () => true, now: clock });
const apple = (uid: string) => env.authenticatedContext(uid, { firebase: { sign_in_provider: "apple.com" } }).firestore();
const device = (token = "fake-fcm-token-123456789") => ({ deviceId: "installation", deviceToken: token, locale: "en", alertsEnabled: true });
const notify = (send: (message: Message) => Promise<string>, clock = Date.now) => new OperationNotificationService(db, { send }, clock);
before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) throw new Error("Use Firebase emulators: these tests must never target production.");
  env = await initializeTestEnvironment({ projectId, firestore: { rules: readFileSync(resolve("..", "firestore.rules"), "utf8") } });
  db = new Firestore({ projectId });
});
after(async () => { await db?.terminate(); await env?.cleanup(); });

test("durable story acceptance is idempotent, isolated and billed once before any provider work", async () => {
  let calls = 0;
  const service = api({ generate: async () => { calls++; return book(); } }), data = request();
  await assert.rejects(service.start(undefined, data), { code: "unauthenticated" });
  await assert.rejects(service.start(principal("opAccept"), { ...data, uid: "opForeign" }), { code: "invalid-argument" });
  const accepted = await Promise.all([service.start(principal("opAccept"), data), service.start(principal("opAccept"), data)]);
  assert.equal(accepted[0]!.jobId, data.requestId); assert.equal(accepted[1]!.jobId, data.requestId); assert.equal(calls, 0);
  assert.equal((await db.doc("privateAccounts/opAccept").get()).get("storyUsage.count"), 1);
  await assert.rejects(service.start(principal("opAccept"), { ...data, description: "A different idea." }), { code: "already-exists" });
  await assert.rejects(service.start(principal("opAccept"), request()), { code: "resource-exhausted" });
  await service.process({ uid: "opAccept", id: data.requestId });
  await service.process({ uid: "opAccept", id: data.requestId });
  const stored = await db.doc(`users/opAccept/storyJobs/${data.requestId}`).get();
  assert.equal(calls, 1); assert.equal(stored.get("state"), "ready"); assert.equal(stored.get("progress"), 1);
  assert.equal(stored.get("wordsPerMinute"), 80); assert.deepEqual(stored.get("result"), book());
  assert.equal((await db.doc(`privateAccounts/opAccept/storyJobs/${data.requestId}`).get()).get("input"), undefined);
  assert.equal((await db.doc("privateAccounts/opAccept").get()).get("storyGeneration"), undefined);
  await assertSucceeds(getDoc(doc(apple("opAccept"), stored.ref.path)));
  await assertSucceeds(getDocs(query(collection(apple("opAccept"), "users/opAccept/storyJobs"), where("expiresAt", ">", new Date(now)))));
  await assertFails(getDoc(doc(apple("opForeign"), stored.ref.path)));
  await assertFails(getDoc(doc(apple("opAccept"), `privateAccounts/opAccept/storyJobs/${data.requestId}`)));
  await assertFails(setDoc(doc(apple("opAccept"), stored.ref.path), { state: "ready" }));
});
test("a failed enqueue remains durable and scheduled retry repairs it; expired results are purged", async () => {
  let time = now;
  const service = new StoryJobService(db, { generate: async () => book() }, { enqueue: async () => { throw new Error("queue unavailable"); } }, { enabled: () => true, now: () => time });
  const { jobId } = await service.start(principal("opOutbox"), request());
  assert.equal((await db.doc(`privateAccounts/opOutbox/storyJobs/${jobId}`).get()).get("dispatchPending"), true);
  await api(undefined, () => time).retryAndClean();
  assert.equal((await db.doc(`privateAccounts/opOutbox/storyJobs/${jobId}`).get()).get("dispatchPending"), false);
  time += 31 * 60000; await api(undefined, () => time).retryAndClean();
  assert.equal((await db.doc(`users/opOutbox/storyJobs/${jobId}`).get()).get("errorCode"), "expired");
  const publicJob = db.doc(`users/opOutbox/storyJobs/${jobId}`);
  await publicJob.update({ expiresAt: Timestamp.fromMillis(now - 1) });
  await assertFails(getDoc(doc(apple("opForeign"), publicJob.path)));
  time += 24 * 3600000; await api(undefined, () => time).retryAndClean();
  assert.equal((await publicJob.get()).exists, false);
  assert.equal((await db.doc(`privateAccounts/opOutbox/storyJobs/${jobId}`).get()).exists, false);
});
test("transient story retries reuse accepted quota and persist only a sanitized terminal failure", async () => {
  let calls = 0;
  const service = api({ generate: async () => { calls++; throw new Error("private provider payload and account credentials"); } });
  const { jobId } = await service.start(principal("opRetry"), request());
  for (let n = 0; n < 2; n++) await assert.rejects(service.process({ uid: "opRetry", id: jobId }), { code: "unavailable" });
  await service.process({ uid: "opRetry", id: jobId });
  const stored = (await db.doc(`users/opRetry/storyJobs/${jobId}`).get()).data();
  assert.equal(calls, 3); assert.equal(stored!.state, "failed"); assert.equal(stored!.errorCode, "unavailable");
  assert.ok(!JSON.stringify(stored).includes("private"));
  assert.equal((await db.doc("privateAccounts/opRetry").get()).get("storyUsage.count"), 1);
});
test("cancellation during inference fences late output and cannot clear a replacement request", async () => {
  let finish!: (book: unknown) => void, start!: () => void;
  const pending = new Promise<unknown>((r) => { finish = r; }), started = new Promise<void>((r) => { start = r; });
  const service = api({ generate: async () => { start(); return pending; } });
  const { jobId } = await service.start(principal("opCancel"), request());
  const work = service.process({ uid: "opCancel", id: jobId }); await started;
  await assert.rejects(service.cancel(principal("opForeign"), { jobId }), { code: "permission-denied" });
  await service.cancel(principal("opCancel"), { jobId });
  const replacement = await service.start(principal("opCancel"), request());
  finish(book()); await work;
  const cancelled = await db.doc(`users/opCancel/storyJobs/${jobId}`).get();
  assert.equal(cancelled.get("state"), "cancelled"); assert.equal(cancelled.get("result"), undefined);
  assert.equal((await db.doc("privateAccounts/opCancel").get()).get("storyGeneration.lease"), replacement.jobId);
});
test("account deletion during inference prevents output or lease resurrection", async () => {
  let finish!: (book: unknown) => void, start!: () => void;
  const pending = new Promise<unknown>((r) => { finish = r; }), started = new Promise<void>((r) => { start = r; });
  const service = api({ generate: async () => { start(); return pending; } });
  const { jobId } = await service.start(principal("opDelete"), request());
  const work = service.process({ uid: "opDelete", id: jobId }); await started;
  await db.doc("privateAccounts/opDelete").set({ state: "deleted" });
  await db.recursiveDelete(db.doc("users/opDelete")); await db.recursiveDelete(db.doc(`privateAccounts/opDelete/storyJobs/${jobId}`));
  finish(book()); await work;
  assert.equal((await db.doc(`users/opDelete/storyJobs/${jobId}`).get()).exists, false);
  assert.equal((await db.doc(`privateAccounts/opDelete/storyJobs/${jobId}`).get()).exists, false);
  assert.deepEqual((await db.doc("privateAccounts/opDelete").get()).data(), { state: "deleted" });
});
test("expired worker execution cannot overwrite a new execution of the same durable job", async () => {
  let time = now, calls = 0, start!: () => void, finish!: (value: unknown) => void;
  const pending = new Promise<unknown>((r) => { finish = r; }), started = new Promise<void>((r) => { start = r; });
  const service = api({ generate: async () => { if (++calls === 1) { start(); return pending; } return book(); } }, () => time);
  const { jobId } = await service.start(principal("opExecution"), request());
  const first = service.process({ uid: "opExecution", id: jobId }); await started;
  await assert.rejects(service.process({ uid: "opExecution", id: jobId }), { code: "aborted" });
  time += 421000; await service.process({ uid: "opExecution", id: jobId });
  finish({ ...book(), title: "Stale result" }); await first;
  assert.equal((await db.doc(`users/opExecution/storyJobs/${jobId}`).get()).get("result.title"), book().title);
});
test("notification device and activity registration enforce Apple ownership and transfer an installation between accounts", async () => {
  const service = notify(async () => "sent");
  await assert.rejects(service.registerDevice(undefined, device()), { code: "unauthenticated" });
  await assert.rejects(service.registerDevice(principal("opDeviceA"), { ...device(), uid: "opDeviceB" }), { code: "invalid-argument" });
  await service.registerDevice(principal("opDeviceA"), device());
  await assertFails(getDoc(doc(apple("opDeviceA"), "privateAccounts/opDeviceA/notificationDevices/installation")));
  await service.registerDevice(principal("opDeviceB"), device());
  assert.equal((await db.doc("privateAccounts/opDeviceA/notificationDevices/installation").get()).exists, false);
  assert.equal((await db.doc("privateAccounts/opDeviceB/notificationDevices/installation").get()).get("uid"), "opDeviceB");
  await assert.rejects(service.registerActivity(principal("opDeviceB"), { deviceId: "installation", kind: "narration", operationId: "foreign", activityToken: "a".repeat(64) }), { code: "not-found" });
  await db.doc("privateAccounts/opDeviceB").set({ state: "deleting" });
  await assert.rejects(service.registerDevice(principal("opDeviceB"), device()), { code: "permission-denied" });
  await service.unregisterDevice(principal("opDeviceB"), { deviceId: "installation" });
  assert.equal((await db.doc("privateAccounts/opDeviceB/notificationDevices/installation").get()).exists, false);
});
test("terminal notifications deduplicate, Live Activities progress without alerts and stale events cannot rewind them", async () => {
  const messages: Message[] = [], service = notify(async (message) => { messages.push(message); return "sent"; });
  await service.registerDevice(principal("opPush"), device("op-push-fcm-token-123456"));
  const ref = db.doc("users/opPush/jobs/job");
  await ref.set({ uid: "opPush", id: "job", state: "processing", progress: 0.3 });
  await service.registerActivity(principal("opPush"), { deviceId: "installation", kind: "narration", operationId: "job", activityToken: "a".repeat(64) });
  assert.equal(messages[0]?.apns?.payload?.aps.event, "update");
  const previous = await ref.get(); await ref.update({ state: "ready", progress: 1 });
  const ready = await ref.get();
  await service.changed("opPush", "job", "narration", previous.data(), ready.data(), ready.updateTime!.toMillis());
  await service.changed("opPush", "job", "narration", previous.data(), ready.data(), ready.updateTime!.toMillis());
  await service.changed("opPush", "job", "narration", undefined, previous.data(), previous.updateTime!.toMillis());
  assert.equal(messages.filter((message) => message.notification).length, 1);
  assert.equal(messages.filter((message) => message.apns?.payload?.aps.event === "end").length, 1);
  assert.equal(messages.length, 3);
  await service.registerDevice(principal("opQuiet"), { ...device("op-quiet-fcm-token-123456"), alertsEnabled: false });
  const quiet = db.doc("users/opQuiet/storyJobs/job"); await quiet.set({ uid: "opQuiet", state: "processing", progress: 0.5 });
  await service.registerActivity(principal("opQuiet"), { deviceId: "installation", kind: "storyGeneration", operationId: "job", activityToken: "b".repeat(64) });
  await quiet.update({ state: "ready", progress: 1 }); const done = await quiet.get();
  await service.changed("opQuiet", "job", "storyGeneration", undefined, done.data(), done.updateTime!.toMillis());
  assert.equal(messages.filter((message) => message.notification).length, 1);
  assert.equal(messages.at(-1)?.apns?.payload?.aps.event, "end");
});
test("notification failure can retry safely, previews do not alert, and tombstones prevent every delivery", async () => {
  let attempts = 0;
  const service = notify(async () => { if (++attempts === 1) throw new Error("temporary FCM outage"); return "sent"; });
  await service.registerDevice(principal("opPushRetry"), device("op-retry-fcm-token-123456"));
  const ref = db.doc("users/opPushRetry/voices/voice"); await ref.set({ uid: "opPushRetry", status: "awaitingApproval" });
  const done = await ref.get();
  await assert.rejects(service.changed("opPushRetry", "voice", "voiceEnrollment", { status: "processing" }, done.data(), done.updateTime!.toMillis()));
  await service.changed("opPushRetry", "voice", "voiceEnrollment", { status: "awaitingApproval" }, done.data(), done.updateTime!.toMillis());
  assert.equal(attempts, 2);
  const preview = db.doc("users/opPushRetry/jobs/preview"); await preview.set({ state: "ready", preview: true }); const sample = await preview.get();
  await service.changed("opPushRetry", "preview", "narration", undefined, sample.data(), sample.updateTime!.toMillis());
  assert.equal(attempts, 2);
  await db.doc("privateAccounts/opPushRetry").set({ state: "deleting" });
  const other = db.doc("users/opPushRetry/jobs/other"); await other.set({ state: "ready" }); const state = await other.get();
  await service.changed("opPushRetry", "other", "narration", undefined, state.data(), state.updateTime!.toMillis());
  assert.equal(attempts, 2);
});

test("APNs credential failure accepts and retains activity registration until scheduled delivery recovers", async () => {
  let available = false, attempts = 0;
  const service = notify(async () => {
    attempts++;
    if (!available) throw Object.assign(new Error("private APNs provider response"), { code: "messaging/third-party-auth-error" });
    return "sent";
  });
  const uid = "opActivityCredentials";
  await service.registerDevice(principal(uid), { ...device("op-activity-credentials-token-123456"), alertsEnabled: false });
  await db.doc(`users/${uid}/jobs/job`).set({ uid, state: "ready", progress: 1 });
  assert.deepEqual(await service.registerActivity(principal(uid), { deviceId: "installation", kind: "narration", operationId: "job", activityToken: "d".repeat(64) }), {});
  const installation = db.doc(`privateAccounts/${uid}/notificationDevices/installation`);
  let pending = await installation.collection("activities").get();
  assert.equal(pending.size, 1); assert.equal(pending.docs[0]!.get("deliveryPending"), true);
  assert.equal(pending.docs[0]!.get("sendLease"), undefined); assert.equal((await installation.get()).exists, true);
  assert.equal(attempts, 1);
  available = true; await service.clean();
  pending = await installation.collection("activities").get();
  assert.equal(pending.empty, true); assert.equal(attempts, 2); assert.equal((await installation.get()).exists, true);
  await service.clean(); assert.equal(attempts, 2);
});

test("pending activity retries stop after the eight-hour activity lifetime without deleting its device", async () => {
  let time = now, attempts = 0;
  const service = notify(async () => { attempts++; throw Object.assign(new Error("private APNs provider response"), { code: "messaging/third-party-auth-error" }); }, () => time);
  const uid = "opActivityExpires";
  await service.registerDevice(principal(uid), { ...device("op-activity-expires-token-123456"), alertsEnabled: false });
  await db.doc(`users/${uid}/jobs/job`).set({ uid, state: "processing", progress: 0.2 });
  await service.registerActivity(principal(uid), { deviceId: "installation", kind: "narration", operationId: "job", activityToken: "e".repeat(64) });
  assert.equal(attempts, 1);
  time += 8 * 3600000 + 1; await service.clean();
  const installation = db.doc(`privateAccounts/${uid}/notificationDevices/installation`);
  assert.equal((await installation.collection("activities").get()).empty, true);
  assert.equal((await installation.get()).exists, true); assert.equal(attempts, 1);
});

test("a replaced expired story still reaches terminal failure without clearing the replacement lease", async () => {
  let time = now;
  const service = api(undefined, () => time), first = await service.start(principal("opDeadlineReplacement"), request());
  time += 31 * 60000;
  const second = await service.start(principal("opDeadlineReplacement"), request());
  await service.retryAndClean();
  assert.equal((await db.doc(`users/opDeadlineReplacement/storyJobs/${first.jobId}`).get()).get("errorCode"), "expired");
  assert.equal((await db.doc("privateAccounts/opDeadlineReplacement").get()).get("storyGeneration.lease"), second.jobId);
  await service.process({ uid: "opDeadlineReplacement", id: second.jobId });
  assert.equal((await db.doc(`users/opDeadlineReplacement/storyJobs/${second.jobId}`).get()).get("state"), "ready");
});
test("a lost enrollment completion response permits replaying both immutable recordings without duplicate profile or quota", async () => {
  let saves = 0;
  const service = new CloudVoiceService(db, {
    save: async (uid, id, kind, audio) => { saves++; return { path: `enrollments/${uid}/${id}/${kind}.json`, sha256: "a".repeat(64), bytes: audio.length, duration: 10 }; }, remove: async () => undefined,
  }, { enqueue: async () => undefined }, { enabled: () => true, now: () => now });
  const { enrollmentId } = await service.beginVoiceEnrollment(principal("opEnrollmentReplay"), { displayName: "Parent", language: "en-US", consentVersion: "2026-10-01", retentionAccepted: true });
  const bytes = Buffer.alloc(44 + 10 * 48000);
  bytes.write("RIFF"); bytes.writeUInt32LE(bytes.length - 8, 4); bytes.write("WAVE", 8); bytes.write("fmt ", 12); bytes.writeUInt32LE(16, 16); bytes.writeUInt16LE(1, 20); bytes.writeUInt16LE(1, 22); bytes.writeUInt32LE(24000, 24); bytes.writeUInt32LE(48000, 28); bytes.writeUInt16LE(2, 32); bytes.writeUInt16LE(16, 34); bytes.write("data", 36); bytes.writeUInt32LE(bytes.length - 44, 40);
  const reference = { enrollmentId, kind: "reference", audioBase64: bytes.toString("base64") }, consent = { ...reference, kind: "consent" };
  await service.uploadEnrollmentRecording(principal("opEnrollmentReplay"), reference); await service.uploadEnrollmentRecording(principal("opEnrollmentReplay"), consent);
  const accepted = await service.completeVoiceEnrollment(principal("opEnrollmentReplay"), { enrollmentId });
  await service.uploadEnrollmentRecording(principal("opEnrollmentReplay"), reference); await service.uploadEnrollmentRecording(principal("opEnrollmentReplay"), consent);
  const replayed = await service.completeVoiceEnrollment(principal("opEnrollmentReplay"), { enrollmentId });
  assert.equal(accepted.profileId, replayed.profileId); assert.equal(saves, 2);
  assert.equal((await db.collection("privateAccounts/opEnrollmentReplay/voices").get()).size, 1);
  assert.equal((await db.doc("privateAccounts/opEnrollmentReplay").get()).get("limits.enrollments"), 1);
  bytes[44] = 1;
  await assert.rejects(service.uploadEnrollmentRecording(principal("opEnrollmentReplay"), { ...reference, audioBase64: bytes.toString("base64") }), { code: "failed-precondition" });
  await assert.rejects(service.uploadEnrollmentRecording(principal("opEnrollmentForeign"), reference), { code: "not-found" });
  await db.doc("privateAccounts/opEnrollmentReplay").set({ state: "deleting" });
  await assert.rejects(service.uploadEnrollmentRecording(principal("opEnrollmentReplay"), consent), { code: "permission-denied" });
});
test("concurrent cross-account registrations leave exactly one owner for a shared FCM installation", async () => {
  const service = notify(async () => "sent");
  const token = "op-concurrent-owner-token-123456";
  await Promise.all(Array.from({ length: 4 }, (_, i) => service.registerDevice(principal(`opTokenRace${i}`), device(token))));
  const owners = await db.collectionGroup("notificationDevices").where("deviceToken", "==", token).get();
  assert.equal(owners.size, 1);
  const current = owners.docs[0]!;
  await current.ref.collection("activities").doc("old-activity").set({ activityToken: "private", expiresAt: Timestamp.fromMillis(now + 10000) });
  await current.ref.collection("deliveries").doc("old-delivery").set({ sentAt: Timestamp.fromMillis(now), expiresAt: Timestamp.fromMillis(now + 10000) });
  await service.registerDevice(principal("opTokenRaceFinal"), device(token));
  assert.equal((await current.ref.collection("activities").get()).size, 0);
  assert.equal((await current.ref.collection("deliveries").get()).size, 0);
  assert.equal((await db.collectionGroup("notificationDevices").where("deviceToken", "==", token).get()).size, 1);
});
test("a completed FCM send cannot recreate a receipt after account deletion", async () => {
  let started!: () => void, finish!: (value: string) => void;
  const ready = new Promise<void>((r) => { started = r; }), pending = new Promise<string>((r) => { finish = r; });
  const service = notify(async () => { started(); return pending; });
  await service.registerDevice(principal("opReceiptDelete"), device("op-delete-receipt-token-123456"));
  const operation = db.doc("users/opReceiptDelete/jobs/job"); await operation.set({ state: "ready" }); const state = await operation.get();
  const delivery = service.changed("opReceiptDelete", "job", "narration", undefined, state.data(), state.updateTime!.toMillis()); await ready;
  await db.doc("privateAccounts/opReceiptDelete").set({ state: "deleted" });
  await db.recursiveDelete(db.doc("privateAccounts/opReceiptDelete/notificationDevices/installation"));
  finish("sent"); await delivery;
  assert.equal((await db.collection("privateAccounts/opReceiptDelete/notificationDevices/installation/deliveries").get()).size, 0);
  assert.equal((await db.doc("privateAccounts/opReceiptDelete/notificationDevices/installation").get()).exists, false);
});
test("invalid old FCM token cannot delete its rotated registration and the terminal event retries to the new token", async () => {
  let calls = 0;
  let service: OperationNotificationService;
  service = notify(async (message) => {
    if (++calls === 1) {
      await service.registerDevice(principal("opTokenRotate"), device("op-rotated-valid-token-123456"));
      throw Object.assign(new Error("old FCM token expired"), { code: "messaging/registration-token-not-registered" });
    }
    assert.equal("token" in message ? message.token : undefined, "op-rotated-valid-token-123456");
    return "sent";
  });
  await service.registerDevice(principal("opTokenRotate"), device("op-previous-fcm-token-123456"));
  const operation = db.doc("users/opTokenRotate/jobs/job"); await operation.set({ state: "ready" }); const state = await operation.get();
  await assert.rejects(service.changed("opTokenRotate", "job", "narration", undefined, state.data(), state.updateTime!.toMillis()));
  assert.equal((await db.doc("privateAccounts/opTokenRotate/notificationDevices/installation").get()).get("deviceToken"), "op-rotated-valid-token-123456");
  await service.changed("opTokenRotate", "job", "narration", undefined, state.data(), state.updateTime!.toMillis());
  assert.equal(calls, 2);
});
test("ActivityKit sends strictly ordered whole-second timestamps for rapidly succeeding versions", async () => {
  const messages: Message[] = [], service = notify(async (message) => { messages.push(message); return "sent"; });
  await service.registerDevice(principal("opActivityOrder"), { ...device("op-activity-order-token-123456"), alertsEnabled: false });
  const operation = db.doc("users/opActivityOrder/jobs/job"); await operation.set({ state: "processing", progress: 0.2 });
  await service.registerActivity(principal("opActivityOrder"), { deviceId: "installation", kind: "narration", operationId: "job", activityToken: "c".repeat(64) });
  for (const progress of [0.5, 1]) {
    const before = await operation.get(); await operation.update({ progress, state: progress === 1 ? "ready" : "processing" }); const after = await operation.get();
    await service.changed("opActivityOrder", "job", "narration", before.data(), after.data(), after.updateTime!.toMillis());
  }
  const timestamps = messages.map((message) => message.apns!.payload!.aps.timestamp as number);
  assert.equal(timestamps.length, 3);
  assert.ok(timestamps.every((timestamp, index) => Number.isInteger(timestamp) && timestamp <= Math.floor(Date.now() / 1000) && (index === 0 || timestamp > timestamps[index - 1]!)));
  assert.equal(messages.at(-1)?.apns?.payload?.aps.event, "end");
});
test("narration projects only a logical voice ID and an accepted request is recoverable after cancellation or voice removal", async () => {
  const uid = "opNarrationReceipt", id = "logical-parent";
  await db.doc(`privateAccounts/${uid}`).set({ state: "active" });
  await db.doc(`privateAccounts/${uid}/voices/${id}`).set({ uid, voiceId: id, status: "awaitingApproval", providerVoice: { ciphertext: "private-provider-voice" } });
  const service = new CloudVoiceService(db, { save: async () => { throw new Error("unexpected recording"); }, remove: async () => undefined }, { enqueue: async () => undefined }, { enabled: () => true, now: () => now });
  const data = { requestId: randomUUID(), voiceProfileId: id, draftId: "voice-preview", snapshotHash: "a".repeat(64), language: "en-US", preview: true, chapters: [{ id: "preview-chapter", title: "Preview", paragraphs: [{ text: "A fox is sleeping under the stars.", style: "gentle" }] }] };
  const accepted = await service.startNarration(principal(uid), data);
  const projection = (await db.doc(`users/${uid}/jobs/${accepted.jobId}`).get()).data()!;
  assert.equal(projection.voiceProfileId, id); assert.equal(projection.providerVoice, undefined); assert.ok(!JSON.stringify(projection).includes("private-provider-voice"));
  await service.cancelNarration(principal(uid), { jobId: accepted.jobId });
  await db.doc(`privateAccounts/${uid}/voices/${id}`).delete();
  const retry = await service.startNarration(principal(uid), data);
  assert.equal(retry.jobId, accepted.jobId); assert.equal((await db.doc(`users/${uid}/jobs/${accepted.jobId}`).get()).get("state"), "cancelled");
  assert.equal((await db.doc(`privateAccounts/${uid}`).get()).get("limits.previews"), 1);
  await assert.rejects(service.startNarration(principal(uid), { ...data, requestId: randomUUID() }), { code: "not-found" });
  await assert.rejects(service.startNarration(principal(uid), { ...data, draftId: "another-preview" }), { code: "already-exists" });
});
