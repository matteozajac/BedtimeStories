import test from "node:test";
import assert from "node:assert/strict";
import { activityMessage, activityTimestamp, completionMessage, operationCopy, operationProjection } from "../operationNotifications";

test("operation projections normalize approval, clamp progress and reject unknown states", () => {
  assert.deepEqual(operationProjection("voiceEnrollment", { status: "awaitingApproval" }), { state: "ready", progress: 1, preview: false });
  assert.deepEqual(operationProjection("narration", { state: "processing", progress: 5, preview: true }), { state: "running", progress: 1, preview: true });
  assert.equal(operationProjection("storyGeneration", { state: "processing", progress: NaN })?.progress, 0.15);
  assert.equal(operationProjection("voiceEnrollment", { status: "deleting" }), undefined);
  assert.equal(operationProjection("narration", undefined), undefined);
});
test("completion push provides owner-scoped deep link and dedup identity with generic localized copy", () => {
  const message = completionMessage("owner", "job", "narration", { state: "ready", progress: 1, preview: false }, "private-token", "pl");
  assert.equal(message.notification?.title, "Nagranie bajki");
  assert.equal(message.data?.deepLink, "bedtimestories://operation/job");
  assert.equal(message.data?.eventId, "narration:job:ready");
  assert.equal(message.data?.ownerID, "owner");
  assert.equal(message.apns?.headers?.["apns-collapse-id"]?.length, 64);
  assert.equal(message.apns?.payload?.aps.threadId, "bedtime-operations");
  assert.equal(operationCopy("voiceEnrollment", { state: "ready", progress: 1, preview: false }, "pl").body, "Twój głos jest gotowy. Posłuchaj próbki i zatwierdź go.");
});
test("ActivityKit push has the app Codable content schema and ends quietly at a terminal state", () => {
  const running = activityMessage("job", "storyGeneration", { state: "running", progress: 0.55, preview: false }, "fcm", "activity", "en", 1000);
  assert.equal(running.apns?.liveActivityToken, "activity");
  assert.equal(running.apns?.payload?.aps.event, "update");
  assert.deepEqual(running.apns?.payload?.aps["content-state"], { operationID: "job", title: "New bedtime story", subtitle: "Getting it ready for you", progress: 0.55, state: "running" });
  assert.equal(running.apns?.payload?.aps["stale-date"], 1600);
  const ready = activityMessage("job", "storyGeneration", { state: "ready", progress: 1, preview: false }, "fcm", "activity", "en", 1001);
  assert.equal(ready.apns?.payload?.aps.event, "end");
  assert.equal(ready.apns?.payload?.aps["dismissal-date"], 1121);
  assert.equal(ready.apns?.payload?.aps.alert, undefined);
});
test("successive ActivityKit events in the same Unix second receive strictly increasing timestamps", () => {
  assert.equal(activityTimestamp(1000200, undefined, 1000300), 1000);
  assert.equal(activityTimestamp(1000400, 1000, 1000400), 1001);
  assert.equal(activityTimestamp(1000500, 1001, 1000500), 1002);
  assert.equal(activityTimestamp(1005000, 1002, 1005000), 1005);
});
