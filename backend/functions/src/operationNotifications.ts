import { createHash, randomUUID } from "node:crypto";
import { DocumentData, FieldValue, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { Message } from "firebase-admin/messaging";
import { HttpsError } from "firebase-functions/v2/https";
import { Principal } from "./contracts";
import { connection, diagnostic } from "./diagnostics";
import { exactKeys, identifier, object, requireApple, string } from "./validation";

export type OperationKind = "narration" | "voiceEnrollment" | "storyGeneration";
type State = "queued" | "running" | "ready" | "failed" | "cancelled";
type Locale = "en" | "pl";
export interface OperationProjection { state: State; progress: number; preview: boolean }
export interface OperationMessenger { send(message: Message): Promise<string> }
const KINDS: OperationKind[] = ["narration", "voiceEnrollment", "storyGeneration"];
const TERMINAL: State[] = ["ready", "failed", "cancelled"];
const hash = (value: string) => createHash("sha256").update(value).digest("hex");
function collection(kind: OperationKind): string { return kind === "voiceEnrollment" ? "voices" : kind === "storyGeneration" ? "storyJobs" : "jobs"; }
function deviceToken(raw: unknown): string {
  const value = string(raw, 4096, "notification token");
  if (value.length < 16 || /\s/u.test(value)) throw new HttpsError("invalid-argument", "Invalid notification token.");
  return value;
}
export function operationProjection(kind: OperationKind, data: DocumentData | undefined): OperationProjection | undefined {
  if (!data) return undefined;
  const raw = kind === "voiceEnrollment" ? data.status : data.state;
  const states: Record<string, State> = { queued: "queued", processing: "running", awaitingApproval: "ready", ready: "ready", failed: "failed", cancelled: "cancelled", deleted: "cancelled" };
  const state = typeof raw === "string" ? states[raw] : undefined;
  if (!state) return undefined;
  const progress = state === "ready" ? 1 : typeof data.progress === "number" && Number.isFinite(data.progress) ? Math.min(1, Math.max(0, data.progress)) : state === "running" ? 0.15 : 0;
  return { state, progress, preview: data.preview === true };
}
export function operationCopy(kind: OperationKind, projection: OperationProjection, locale: Locale) {
  const polish = locale === "pl";
  const title = kind === "narration" ? (polish ? "Nagranie bajki" : "Story narration") : kind === "voiceEnrollment" ? (polish ? "Twój głos" : "Your voice") : (polish ? "Nowa bajka" : "New bedtime story");
  const subtitle = projection.state === "ready" ? (polish ? "Gotowe do otwarcia" : "Ready to open") : projection.state === "failed" ? (polish ? "Wymaga Twojej uwagi" : "Needs your attention") : projection.state === "cancelled" ? (polish ? "Anulowano" : "Cancelled") : projection.state === "queued" ? (polish ? "Czeka na rozpoczęcie" : "Waiting to begin") : (polish ? "Przygotowujemy dla Ciebie" : "Getting it ready for you");
  const body = projection.state === "failed" ? (polish ? "Otwórz aplikację, aby sprawdzić, co się stało." : "Open the app to see what happened.") : kind === "voiceEnrollment" ? (polish ? "Twój głos jest gotowy. Posłuchaj próbki i zatwierdź go." : "Your voice is ready. Listen to the sample and approve it.") : kind === "narration" ? (polish ? "Nagranie bajki jest gotowe. Otwórz aplikację, aby go posłuchać." : "Your story narration is ready. Open the app to listen.") : (polish ? "Twoja nowa bajka jest gotowa. Otwórz ją w aplikacji." : "Your new bedtime story is ready. Open it in the app.");
  return { title, subtitle, body };
}
export function completionMessage(uid: string, id: string, kind: OperationKind, projection: OperationProjection, token: string, locale: Locale): Message {
  const copy = operationCopy(kind, projection, locale), eventId = `${kind}:${id}:${projection.state}`;
  return { token, notification: { title: copy.title, body: copy.body }, data: { ownerID: uid, operationId: id, kind, state: projection.state, eventId, deepLink: `bedtimestories://operation/${id}` },
    apns: { headers: { "apns-push-type": "alert", "apns-priority": "10", "apns-collapse-id": hash(eventId), "apns-expiration": String(Math.floor(Date.now() / 1000) + 86400) }, payload: { aps: { sound: "default", threadId: "bedtime-operations" } } } };
}
export function activityMessage(id: string, kind: OperationKind, projection: OperationProjection, token: string, activityToken: string, locale: Locale, timestamp: number): Message {
  const copy = operationCopy(kind, projection, locale), terminal = TERMINAL.includes(projection.state);
  return { token, apns: { liveActivityToken: activityToken, headers: { "apns-push-type": "liveactivity", "apns-priority": terminal ? "10" : "5" },
    payload: { aps: { timestamp, event: terminal ? "end" : "update", "content-state": { operationID: id, title: copy.title, subtitle: copy.subtitle, progress: projection.progress, state: projection.state },
      ...(terminal ? { "dismissal-date": timestamp + 120 } : { "stale-date": timestamp + 600 }) } } } };
}
export function activityTimestamp(versionMillis: number, previous: number | undefined, nowMillis: number): number {
  return Math.max(Math.floor(versionMillis / 1000), Math.floor(nowMillis / 1000), previous === undefined ? 0 : previous + 1);
}

/** Tokens and delivery receipts stay in server-only collections, scoped to the Apple owner. */
export class OperationNotificationService {
  constructor(private db: Firestore, private messenger: OperationMessenger, private now: () => number = Date.now) {}
  private account(uid: string) { return this.db.doc(`privateAccounts/${uid}`); }
  private devices(uid: string) { return this.db.collection(`privateAccounts/${uid}/notificationDevices`); }
  private operation(uid: string, id: string, kind: OperationKind) { return this.db.doc(`users/${uid}/${collection(kind)}/${id}`); }
  private async deviceChildren(tx: Transaction, reference: FirebaseFirestore.DocumentReference) {
    const children = await Promise.all([tx.get(reference.collection("activities")), tx.get(reference.collection("deliveries"))]);
    return children.flatMap((items) => items.docs.map((item) => item.ref));
  }
  async registerDevice(principal: Principal | undefined, raw: unknown): Promise<Record<string, never>> {
    const { uid } = requireApple(principal, this.now() / 1000), data = object(raw);
    exactKeys(data, ["deviceId", "deviceToken", "locale", "alertsEnabled"]);
    const deviceId = identifier(data.deviceId), token = deviceToken(data.deviceToken);
    if (data.locale !== "en" && data.locale !== "pl") throw new HttpsError("invalid-argument", "Unsupported notification language.");
    if (typeof data.alertsEnabled !== "boolean") throw new HttpsError("invalid-argument", "Choose whether completion alerts are enabled.");
    const tokenHash = hash(token);
    await this.db.runTransaction(async (tx) => {
      const [account, device] = await tx.getAll(this.account(uid), this.devices(uid).doc(deviceId));
      if (account!.exists && account!.get("state") !== "active") throw new HttpsError("permission-denied", "Cloud account deletion is in progress.");
      const [devices, priorOwners] = await Promise.all([tx.get(this.devices(uid).limit(10)), tx.get(this.db.collectionGroup("notificationDevices").where("tokenHash", "==", tokenHash).limit(20))]);
      if (!device!.exists && devices.size >= 10) throw new HttpsError("resource-exhausted", "Too many notification devices are registered.");
      const former = priorOwners.docs.filter((prior) => prior.ref.path !== device!.ref.path);
      const children = (await Promise.all(former.map((prior) => this.deviceChildren(tx, prior.ref)))).flat();
      // A reused installation must never retain another signed-in account's registration.
      for (const child of children) tx.delete(child);
      for (const prior of former) tx.delete(prior.ref);
      tx.set(this.account(uid), { state: "active" }, { merge: true });
      tx.set(device!.ref, { uid, id: deviceId, deviceToken: token, tokenHash, locale: data.locale, alertsEnabled: data.alertsEnabled, updatedAt: Timestamp.fromMillis(this.now()), expiresAt: Timestamp.fromMillis(this.now() + 35 * 86400000) });
    });
    return {};
  }
  async unregisterDevice(principal: Principal | undefined, raw: unknown): Promise<Record<string, never>> {
    const { uid } = requireApple(principal, this.now() / 1000), data = object(raw); exactKeys(data, ["deviceId"]);
    const deviceId = identifier(data.deviceId);
    // Removal remains available during deletion; the parent tombstone still closes every send.
    await this.removeDevice(this.devices(uid).doc(deviceId));
    return {};
  }
  async registerActivity(principal: Principal | undefined, raw: unknown): Promise<Record<string, never>> {
    const { uid } = requireApple(principal, this.now() / 1000), data = object(raw);
    exactKeys(data, ["deviceId", "kind", "operationId", "activityToken"]);
    const deviceId = identifier(data.deviceId), id = identifier(data.operationId);
    if (!KINDS.includes(data.kind as OperationKind)) throw new HttpsError("invalid-argument", "Unsupported operation kind.");
    const kind = data.kind as OperationKind, activityToken = string(data.activityToken, 512, "activity token");
    if (!/^[a-fA-F0-9]{32,512}$/u.test(activityToken)) throw new HttpsError("invalid-argument", "Invalid activity token.");
    await this.db.runTransaction(async (tx) => {
      const [account, device, operation] = await tx.getAll(this.account(uid), this.devices(uid).doc(deviceId), this.operation(uid, id, kind));
      if (!account!.exists || account!.get("state") !== "active") throw new HttpsError("permission-denied", "Cloud account deletion is in progress.");
      if (!device!.exists || device!.get("uid") !== uid || !operation!.exists || (operation!.get("uid") !== undefined && operation!.get("uid") !== uid)) throw new HttpsError("not-found", "This operation is unavailable.");
      const reference = device!.ref.collection("activities").doc(hash(`${kind}:${id}`)), existing = await tx.get(reference);
      tx.set(reference, { kind, operationId: id, activityToken, deliveryPending: true, expiresAt: Timestamp.fromMillis(this.now() + 8 * 3600000),
        ...(existing.exists && existing.get("activityToken") !== activityToken ? { lastVersionMillis: FieldValue.delete(), sendLease: FieldValue.delete(), leaseUntil: FieldValue.delete() } : {}) }, { merge: true });
    });
    // Registration is accepted once its owner-scoped token/outbox commits. Provider
    // delivery may fail independently, including while APNs provisioning is deferred.
    try {
      const current = await this.operation(uid, id, kind).get(), projection = operationProjection(kind, current.data());
      if (projection) await this.deliverActivities(uid, id, kind, projection, current.updateTime?.toMillis() ?? this.now());
    } catch (error) {
      diagnostic("warn", "operation_activity_registration_delivery_deferred", { recovery: "scheduled_activity_retry" }, error);
    }
    return {};
  }
  async changed(uid: string, id: string, kind: OperationKind, before: DocumentData | undefined, after: DocumentData | undefined, updateMillis: number): Promise<void> {
    const projection = operationProjection(kind, after);
    if (!projection) return;
    // Firestore events may arrive out of order. Only the latest stored version drives APNs.
    const current = await this.operation(uid, id, kind).get();
    if (!current.exists || current.updateTime?.toMillis() !== updateMillis) return;
    const account = await this.account(uid).get();
    if (!account.exists || account.get("state") !== "active") return;
    const old = operationProjection(kind, before);
    let activityFailure: unknown;
    if (TERMINAL.includes(projection.state) || !old || old.state !== projection.state || old.progress !== projection.progress) {
      try { await this.deliverActivities(uid, id, kind, projection, updateMillis); }
      catch (error) { activityFailure = error; }
    }
    // Receipts deduplicate terminal events even if a later ready->ready write arrived first.
    if (!projection.preview && ["ready", "failed"].includes(projection.state)) await this.deliverCompletion(uid, id, kind, projection);
    if (activityFailure) throw activityFailure;
  }
  private async deliverCompletion(uid: string, id: string, kind: OperationKind, projection: OperationProjection): Promise<void> {
    const devices = await this.devices(uid).limit(10).get(), event = hash(`${kind}:${id}:${projection.state}`);
    let transientFailure: unknown;
    for (const device of devices.docs) {
      if (device.get("alertsEnabled") !== true) continue;
      const receipt = device.ref.collection("deliveries").doc(event), lease = randomUUID();
      const claimed = await this.db.runTransaction(async (tx) => {
        const [account, latest, prior] = await tx.getAll(this.account(uid), device.ref, receipt);
        if (!account!.exists || account!.get("state") !== "active" || !latest!.exists || latest!.get("alertsEnabled") !== true || latest!.get("deviceToken") !== device.get("deviceToken") || latest!.get("expiresAt").toMillis() <= this.now() || prior!.get("sentAt")) return false;
        const leaseUntil = prior!.get("leaseUntil");
        if (leaseUntil instanceof Timestamp && leaseUntil.toMillis() > this.now()) throw new HttpsError("aborted", "Notification delivery is in progress.");
        tx.set(receipt, { lease, leaseUntil: Timestamp.fromMillis(this.now() + 120000), expiresAt: Timestamp.fromMillis(this.now() + 7 * 86400000) });
        return true;
      });
      if (!claimed) continue;
      try {
        await connection("fcm", "operation_completion", () => this.messenger.send(completionMessage(uid, id, kind, projection, device.get("deviceToken"), device.get("locale"))));
        await this.db.runTransaction(async (tx) => {
          const [account, latest, prior] = await tx.getAll(this.account(uid), device.ref, receipt);
          if (account!.get("state") === "active" && latest!.exists && latest!.get("deviceToken") === device.get("deviceToken") && prior!.get("lease") === lease) tx.update(receipt, { sentAt: Timestamp.fromMillis(this.now()), leaseUntil: FieldValue.delete() });
        });
      } catch (error) {
        if (await this.discardInvalidToken(device.ref, device.get("deviceToken"), error)) continue;
        await this.db.runTransaction(async (tx) => { const prior = await tx.get(receipt); if (prior.get("lease") === lease && !prior.get("sentAt")) tx.delete(receipt); });
        diagnostic("warn", "operation_notification_deferred", { recovery: "firestore_event_retry" }, error);
        transientFailure = error;
      }
    }
    if (transientFailure) throw transientFailure;
  }
  private async deliverActivities(uid: string, id: string, kind: OperationKind, projection: OperationProjection, versionMillis: number): Promise<void> {
    const devices = await this.devices(uid).limit(10).get();
    let transientFailure: unknown;
    for (const device of devices.docs) {
      const reference = device.ref.collection("activities").doc(hash(`${kind}:${id}`)), lease = randomUUID();
      const claim = await this.db.runTransaction(async (tx) => {
        const [account, currentDevice, activity, operation] = await tx.getAll(this.account(uid), device.ref, reference, this.operation(uid, id, kind));
        if (account!.get("state") !== "active" || !currentDevice!.exists || currentDevice!.get("deviceToken") !== device.get("deviceToken") || currentDevice!.get("expiresAt").toMillis() <= this.now() || !activity!.exists || activity!.get("expiresAt").toMillis() <= this.now() || operation!.updateTime?.toMillis() !== versionMillis) return undefined;
        if ((activity!.get("lastVersionMillis") ?? -1) >= versionMillis) {
          if (activity!.get("deliveryPending") === true) tx.update(reference, { deliveryPending: false });
          return undefined;
        }
        const leaseUntil = activity!.get("leaseUntil");
        if (leaseUntil instanceof Timestamp && leaseUntil.toMillis() > this.now()) throw new HttpsError("aborted", "Activity delivery is in progress.");
        const timestamp = activityTimestamp(versionMillis, activity!.get("lastTimestamp"), Date.now());
        tx.update(reference, { sendLease: lease, leaseUntil: Timestamp.fromMillis(this.now() + 120000), deliveryPending: true });
        return { activityToken: activity!.get("activityToken") as string, timestamp };
      });
      if (!claim) continue;
      try {
        // Apple orders ActivityKit payloads by Unix seconds. Serialize per activity,
        // and wait at most one second instead of posting equal/future timestamps.
        const wait = claim.timestamp * 1000 - Date.now();
        if (wait > 0) await new Promise<void>((resolve) => setTimeout(resolve, wait));
        await connection("fcm", "operation_activity", () => this.messenger.send(activityMessage(id, kind, projection, device.get("deviceToken"), claim.activityToken, device.get("locale"), claim.timestamp)));
        await this.db.runTransaction(async (tx) => {
          const [account, currentDevice, activity] = await tx.getAll(this.account(uid), device.ref, reference);
          if (account!.get("state") !== "active" || !currentDevice!.exists || currentDevice!.get("deviceToken") !== device.get("deviceToken") || !activity!.exists || activity!.get("sendLease") !== lease || activity!.get("activityToken") !== claim.activityToken) return;
          if (TERMINAL.includes(projection.state)) tx.delete(reference);
          else tx.update(reference, { lastVersionMillis: versionMillis, lastTimestamp: claim.timestamp, deliveryPending: false, sendLease: FieldValue.delete(), leaseUntil: FieldValue.delete() });
        });
      } catch (error) {
        // An expired ActivityKit token does not establish that its FCM registration is invalid.
        const code = (error as { code?: string }).code;
        const expired = ["messaging/registration-token-not-registered", "messaging/invalid-registration-token"].includes(code ?? "");
        const discarded = await this.db.runTransaction(async (tx) => {
          const [activity, currentDevice] = await tx.getAll(reference, device.ref);
          if (!activity!.exists || activity!.get("sendLease") !== lease || activity!.get("activityToken") !== claim.activityToken) return true;
          if (expired && currentDevice!.get("deviceToken") === device.get("deviceToken")) { tx.delete(reference); return true; }
          else tx.update(reference, { sendLease: FieldValue.delete(), leaseUntil: FieldValue.delete() });
          return false;
        });
        if (!discarded) { diagnostic("warn", "operation_activity_deferred", { recovery: "firestore_event_retry" }, error); transientFailure = error; }
      }
    }
    if (transientFailure) throw transientFailure;
  }
  private async discardInvalidToken(reference: FirebaseFirestore.DocumentReference, token: string, error: unknown): Promise<boolean> {
    const code = (error as { code?: string }).code;
    if (!["messaging/registration-token-not-registered", "messaging/invalid-registration-token"].includes(code ?? "")) return false;
    const removed = await this.removeDevice(reference, token);
    if (!removed) return false;
    diagnostic("debug", "operation_notification_device_expired");
    return true;
  }
  private async removeDevice(reference: FirebaseFirestore.DocumentReference, expectedToken?: string, onlyExpired = false): Promise<boolean> {
    return this.db.runTransaction(async (tx) => {
      const device = await tx.get(reference), expiry = device.get("expiresAt");
      if (expectedToken !== undefined && device.get("deviceToken") !== expectedToken) return false;
      if (onlyExpired && (!device.exists || !(expiry instanceof Timestamp) || expiry.toMillis() > this.now())) return false;
      const children = await this.deviceChildren(tx, reference);
      for (const child of children) tx.delete(child);
      tx.delete(reference);
      return true;
    });
  }
  private async retryPendingActivities(): Promise<void> {
    const pending = await this.db.collectionGroup("activities").where("deliveryPending", "==", true).limit(100).get(), seen = new Set<string>();
    let transientFailure: unknown;
    for (const activity of pending.docs) {
      const path = activity.ref.path.split("/"), kind = activity.get("kind") as OperationKind, id = activity.get("operationId");
      if (path.length !== 6 || path[0] !== "privateAccounts" || path[2] !== "notificationDevices" || path[4] !== "activities" || !KINDS.includes(kind) || typeof id !== "string") continue;
      const uid = path[1]!, key = `${uid}:${kind}:${id}`;
      if (seen.has(key)) continue;
      seen.add(key);
      try {
        const current = await this.operation(uid, id, kind).get(), projection = operationProjection(kind, current.data());
        if (projection) await this.deliverActivities(uid, id, kind, projection, current.updateTime!.toMillis());
      } catch (error) { transientFailure = error; }
    }
    if (transientFailure) throw transientFailure;
  }
  async clean(): Promise<void> {
    const expired = await this.db.collectionGroup("notificationDevices").where("expiresAt", "<=", Timestamp.fromMillis(this.now())).limit(100).get();
    for (const device of expired.docs) if (device.ref.path.startsWith("privateAccounts/")) await this.removeDevice(device.ref, undefined, true);
    for (const group of ["deliveries", "activities"]) {
      const old = await this.db.collectionGroup(group).where("expiresAt", "<=", Timestamp.fromMillis(this.now())).limit(100).get();
      for (const item of old.docs) if (item.ref.path.startsWith("privateAccounts/") && item.ref.path.includes("/notificationDevices/")) await this.db.runTransaction(async (tx) => {
        const current = await tx.get(item.ref), expiresAt = current.get("expiresAt");
        if (current.exists && expiresAt instanceof Timestamp && expiresAt.toMillis() <= this.now()) tx.delete(item.ref);
      });
    }
    // At most 100 pending registrations per five-minute schedule; expired
    // activities are removed above, so unavailable APNs credentials cannot retry forever.
    await this.retryPendingActivities();
  }
}
