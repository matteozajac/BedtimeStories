import { randomUUID } from "node:crypto";
import { Firestore, DocumentSnapshot, Timestamp, Transaction, FieldValue } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { CONSENT_STATEMENTS, CONSENT_VERSION, LIMITS, Principal, RecordingKind, RecordingStore, TaskDispatcher, WorkerTask } from "./contracts";
import { contentHash, decodeRecording, enrollmentInput, exactKeys, identifier, narrationInput, object, requireApple } from "./validation";
import { connection, diagnostic, preserveCause, taskKey, withDiagnosticContext } from "./diagnostics";
import { builtInVoice } from "./voice-catalog";

interface ServiceOptions { enabled: () => boolean; now?: () => number }
export class CloudVoiceService {
  private now: () => number;
  constructor(private db: Firestore, private recordings: RecordingStore, private dispatcher: TaskDispatcher, private options: ServiceOptions) {
    this.now = options.now ?? (() => Date.now());
  }
  private transaction<T>(execute: (tx: Transaction) => Promise<T>): Promise<T> {
    return connection("firestore", "transaction", () => this.db.runTransaction(execute));
  }
  private authenticated(principal: Principal | undefined, recent = false): Principal { return requireApple(principal, this.now() / 1000, recent); }
  private enabled(): void { if (!this.options.enabled()) throw new HttpsError("failed-precondition", "Cloud narration is not available yet."); }
  private account(uid: string) { return this.db.doc(`privateAccounts/${uid}`); }
  private enrollment(uid: string, id: string) { return this.db.doc(`privateAccounts/${uid}/enrollments/${id}`); }
  private privateVoice(uid: string, id: string) { return this.db.doc(`privateAccounts/${uid}/voices/${id}`); }
  private publicVoice(uid: string, id: string) { return this.db.doc(`users/${uid}/voices/${id}`); }
  private privateJob(uid: string, id: string) { return this.db.doc(`privateAccounts/${uid}/jobs/${id}`); }
  private publicJob(uid: string, id: string) { return this.db.doc(`users/${uid}/jobs/${id}`); }
  private active(account: DocumentSnapshot): void {
    if (account.exists && account.get("state") !== "active") throw new HttpsError("permission-denied", "Cloud account deletion is in progress.");
  }
  private owned(snapshot: DocumentSnapshot, uid: string): void {
    if (!snapshot.exists || snapshot.get("uid") !== uid) throw new HttpsError("not-found", "This cloud item is unavailable.");
  }
  private collecting(enrollment: DocumentSnapshot, uid: string): void {
    this.owned(enrollment, uid);
    if (enrollment.get("state") !== "collecting" || !(enrollment.get("expiresAt") instanceof Timestamp) || enrollment.get("expiresAt").toMillis() <= this.now()) {
      throw new HttpsError("failed-precondition", "Start a new voice recording session.");
    }
  }
  private quota(tx: Transaction, account: DocumentSnapshot, uid: string, kind: "enrollments" | "previews" | "books", maximum: number): void {
    const day = new Date(this.now()).toISOString().slice(0, 10);
    const old = account.get("limits") as Record<string, unknown> | undefined;
    const current: Record<string, unknown> = old?.day === day ? { ...old } : { day, enrollments: 0, previews: 0, books: 0 };
    const used = typeof current[kind] === "number" ? current[kind] as number : 0;
    if (used >= maximum) throw new HttpsError("resource-exhausted", "Your daily cloud narration limit has been reached.");
    current[kind] = used + 1;
    tx.set(this.account(uid), { state: "active", limits: current }, { merge: true });
  }
  private async dispatch(task: WorkerTask, reference: FirebaseFirestore.DocumentReference): Promise<void> {
    return withDiagnosticContext({ task_key: taskKey(task), task_kind: task.kind }, async () => {
      diagnostic("debug", "cloud_dispatch_started");
      try {
        await this.dispatcher.enqueue(task);
        await this.transaction(async (tx) => {
          const current = await tx.get(reference);
          // A concurrent delete can replace an enrollment outbox. Never clear that newer operation.
          if (current.exists && current.get("taskKind") === task.kind) {
            tx.update(reference, { dispatchPending: false, dispatchedAt: Timestamp.fromMillis(this.now()) });
          }
        });
        diagnostic("debug", "cloud_dispatch_completed");
      } catch (error) {
        diagnostic("warn", "cloud_dispatch_deferred", { recovery: "durable_outbox_retry" }, error);
        // Returning the accepted ID lets the client observe the durable outbox without another chargeable request.
      }
    });
  }
  async beginVoiceEnrollment(principal: Principal | undefined, raw: unknown) {
    const { uid } = this.authenticated(principal);
    this.enabled();
    const input = enrollmentInput(raw);
    const id = randomUUID();
    const expiresAt = Timestamp.fromMillis(this.now() + LIMITS.enrollmentTTLSeconds * 1000);
    await this.transaction(async (tx) => {
      const account = await tx.get(this.account(uid));
      this.active(account);
      const voices = await tx.get(this.db.collection(`privateAccounts/${uid}/voices`).where("status", "in", ["processing", "awaitingApproval", "ready", "failed", "deleting"]));
      if (voices.size >= LIMITS.activeVoices) throw new HttpsError("resource-exhausted", "Delete an existing voice before adding another.");
      this.quota(tx, account, uid, "enrollments", LIMITS.enrollmentAttemptsPerDay);
      tx.create(this.enrollment(uid, id), {
        uid, enrollmentId: id, ...input, consentLanguage: input.language === "pl-PL" ? "pl" : "en", consentVersion: CONSENT_VERSION,
        retentionAccepted: true, state: "collecting", recordings: {}, uploads: {}, createdAt: Timestamp.fromMillis(this.now()), expiresAt,
      });
    });
    return { enrollmentId: id, expiresAt: expiresAt.toMillis() / 1000, consentStatement: CONSENT_STATEMENTS[input.language] };
  }

  async uploadEnrollmentRecording(principal: Principal | undefined, raw: unknown) {
    const { uid } = this.authenticated(principal);
    this.enabled();
    const data = object(raw);
    exactKeys(data, ["enrollmentId", "kind", "audioBase64"]);
    const id = identifier(data.enrollmentId);
    if (data.kind !== "reference" && data.kind !== "consent") throw new HttpsError("invalid-argument", "Invalid recording kind.");
    const kind: RecordingKind = data.kind;
    const { audio, duration } = decodeRecording(data.audioBase64, kind);
    const hash = contentHash(audio.toString("base64"));
    const reservation = randomUUID();
    const alreadySaved = await this.transaction(async (tx) => {
      const [account, enrollment] = await tx.getAll(this.account(uid), this.enrollment(uid, id));
      this.active(account!);
      this.owned(enrollment!, uid);
      const existing = enrollment!.get(`recordings.${kind}`);
      if (enrollment!.get("state") === "submitted") {
        const profile = await tx.get(this.privateVoice(uid, id));
        this.owned(profile, uid);
        if (["deleting", "deleted"].includes(profile.get("status")) || !existing || existing.inputHash !== hash) {
          throw new HttpsError("failed-precondition", "Start a new session to replace an uploaded recording.");
        }
        // A lost complete response can replay uploads. Immutable matching samples
        // already attached to this owner's submitted profile require no new write.
        return true;
      }
      this.collecting(enrollment!, uid);
      if (existing) {
        if (existing.inputHash === hash) return true;
        throw new HttpsError("failed-precondition", "Start a new session to replace an uploaded recording.");
      }
      const uploading = enrollment!.get(`uploads.${kind}`);
      if (uploading?.expiresAt instanceof Timestamp && uploading.expiresAt.toMillis() > this.now()) throw new HttpsError("aborted", "The recording is still uploading. Try again shortly.");
      tx.update(this.enrollment(uid, id), { [`uploads.${kind}`]: { reservation, expiresAt: Timestamp.fromMillis(this.now() + 120000) } });
      return false;
    }).catch((error) => { audio.fill(0); throw error; });
    if (alreadySaved) { audio.fill(0); return {}; }
    let saved: Awaited<ReturnType<RecordingStore["save"]>> | undefined;
    try {
      saved = await this.recordings.save(uid, id, kind, audio);
      await this.transaction(async (tx) => {
        const [account, enrollment] = await tx.getAll(this.account(uid), this.enrollment(uid, id));
        this.active(account!);
        this.collecting(enrollment!, uid);
        if (enrollment!.get(`uploads.${kind}.reservation`) !== reservation) throw new HttpsError("aborted", "Recording upload changed.");
        tx.update(this.enrollment(uid, id), { [`recordings.${kind}`]: { ...saved, duration, inputHash: hash }, [`uploads.${kind}`]: FieldValue.delete() });
      });
      return {};
    } catch (error) {
      // Deletion can race a KMS/storage write: remove any result that cannot be attached to its active owner.
      if (saved) await this.recordings.remove(saved.path).catch((cleanupError) => {
        diagnostic("warn", "recording_rollback_object_delete_failed", { recovery: "scheduled_cleanup" }, cleanupError);
      });
      await this.transaction(async (tx) => {
        const enrollment = await tx.get(this.enrollment(uid, id));
        if (enrollment.exists && enrollment.get(`uploads.${kind}.reservation`) === reservation) tx.update(enrollment.ref, { [`uploads.${kind}`]: FieldValue.delete() });
      }).catch((cleanupError) => {
        diagnostic("warn", "recording_rollback_reservation_failed", { recovery: "reservation_expiry" }, cleanupError);
      });
      if (error instanceof HttpsError) throw error;
      throw preserveCause(new HttpsError("unavailable", "The recording could not be saved. Try again."), error);
    } finally { audio.fill(0); }
  }

  async completeVoiceEnrollment(principal: Principal | undefined, raw: unknown) {
    const { uid } = this.authenticated(principal);
    this.enabled();
    const data = object(raw);
    exactKeys(data, ["enrollmentId"]);
    const id = identifier(data.enrollmentId);
    await this.transaction(async (tx) => {
      const [account, enrollment, profile] = await tx.getAll(this.account(uid), this.enrollment(uid, id), this.privateVoice(uid, id));
      this.active(account!);
      this.owned(enrollment!, uid);
      if (enrollment!.get("state") === "submitted" && profile!.exists) return;
      this.collecting(enrollment!, uid);
      const reference = enrollment!.get("recordings.reference");
      const consent = enrollment!.get("recordings.consent");
      if (!reference || !consent || Object.keys(enrollment!.get("uploads") ?? {}).length !== 0) throw new HttpsError("failed-precondition", "Record and upload both voice samples first.");
      const voices = await tx.get(this.db.collection(`privateAccounts/${uid}/voices`).where("status", "in", ["processing", "awaitingApproval", "ready", "failed", "deleting"]));
      if (voices.size >= LIMITS.activeVoices) throw new HttpsError("resource-exhausted", "Delete an existing voice before adding another.");
      const createdAt = Timestamp.fromMillis(this.now());
      const displayName = enrollment!.get("displayName");
      const language = enrollment!.get("language");
      tx.create(this.privateVoice(uid, id), {
        uid, voiceId: id, enrollmentId: id, displayName, language, consentLanguage: enrollment!.get("consentLanguage"), consentVersion: CONSENT_VERSION,
        retentionAccepted: true, referenceObject: reference.path, consentObject: consent.path,
        status: "processing", createdAt, taskKind: "enroll", dispatchPending: true,
      });
      tx.create(this.publicVoice(uid, id), { uid, id, displayName, language, status: "processing", createdAt });
      tx.update(this.enrollment(uid, id), { state: "submitted", profileId: id, submittedAt: createdAt });
    });
    await this.dispatch({ kind: "enroll", uid, id }, this.privateVoice(uid, id));
    return { profileId: id };
  }

  async startNarration(principal: Principal | undefined, raw: unknown) {
    const { uid } = this.authenticated(principal);
    this.enabled();
    const input = narrationInput(raw);
    const builtIn = builtInVoice(input.voiceProfileId);
    const jobId = input.requestId;
    const payloadHash = contentHash(input);
    await this.transaction(async (tx) => {
      const [account, existing] = await tx.getAll(this.account(uid), this.privateJob(uid, jobId));
      this.active(account!);
      if (existing!.exists) {
        this.owned(existing!, uid);
        if (existing!.get("payloadHash") !== payloadHash) throw new HttpsError("already-exists", "Use a new request ID for a different narration.");
        // Acceptance stays recoverable even if the voice changed or was deleted
        // after a response was lost. Its already accepted payload is immutable.
        return;
      }
      const profile = builtIn ? undefined : await tx.get(this.privateVoice(uid, input.voiceProfileId));
      if (!builtIn) {
        this.owned(profile!, uid);
        const status = profile!.get("status");
        if ((status !== "ready" && !(input.preview && status === "awaitingApproval")) || !profile!.get("providerVoice")) throw new HttpsError("failed-precondition", "Listen to and approve this voice before generating a book.");
      }
      if (!input.preview) {
        const activeBooks = await tx.get(this.db.collection(`privateAccounts/${uid}/jobs`).where("preview", "==", false).where("state", "in", ["queued", "processing"]).limit(1));
        if (!activeBooks.empty) throw new HttpsError("resource-exhausted", "Wait for your current book narration to finish before starting another.");
      }
      this.quota(tx, account!, uid, input.preview ? "previews" : "books", input.preview ? LIMITS.previewsPerDay : LIMITS.booksPerDay);
      const createdAt = Timestamp.fromMillis(this.now());
      const expiresAt = Timestamp.fromMillis(this.now() + LIMITS.outputTTLSeconds * 1000);
      tx.create(this.privateJob(uid, jobId), { uid, jobId, ...input, payloadHash, state: "queued", createdAt, expiresAt, cancelRequested: false, taskKind: "narrate", dispatchPending: true });
      tx.create(this.publicJob(uid, jobId), { uid, id: jobId, state: "queued", progress: 0, preview: input.preview, voiceProfileId: input.voiceProfileId, draftId: input.draftId, snapshotHash: input.snapshotHash, createdAt, expiresAt, outputs: [] });
    });
    await this.dispatch({ kind: "narrate", uid, id: jobId }, this.privateJob(uid, jobId));
    return { jobId };
  }

  async approveVoice(principal: Principal | undefined, raw: unknown) {
    const { uid } = this.authenticated(principal);
    const data = object(raw);
    exactKeys(data, ["profileId"]);
    const id = identifier(data.profileId);
    await this.transaction(async (tx) => {
      const [account, profile] = await tx.getAll(this.account(uid), this.privateVoice(uid, id));
      this.active(account!);
      this.owned(profile!, uid);
      if (profile!.get("status") === "ready") return;
      if (profile!.get("status") !== "awaitingApproval" || !profile!.get("providerVoice")) throw new HttpsError("failed-precondition", "This voice is not ready to approve.");
      const approvedAt = Timestamp.fromMillis(this.now());
      tx.update(profile!.ref, { status: "ready", approvedAt });
      tx.update(this.publicVoice(uid, id), { status: "ready", approvedAt });
    });
    return {};
  }

  async cancelNarration(principal: Principal | undefined, raw: unknown) {
    const { uid } = this.authenticated(principal);
    const data = object(raw);
    exactKeys(data, ["jobId"]);
    const id = identifier(data.jobId);
    await this.transaction(async (tx) => {
      const [account, job] = await tx.getAll(this.account(uid), this.privateJob(uid, id));
      this.active(account!);
      this.owned(job!, uid);
      if (["ready", "failed", "cancelled"].includes(job!.get("state"))) return;
      tx.update(job!.ref, { cancelRequested: true, state: "cancelled", cancelledAt: Timestamp.fromMillis(this.now()) });
      tx.update(this.publicJob(uid, id), { state: "cancelled" });
    });
    return {};
  }

  async deleteVoice(principal: Principal | undefined, raw: unknown) {
    const { uid } = this.authenticated(principal, true);
    const data = object(raw);
    exactKeys(data, ["profileId"]);
    const id = identifier(data.profileId);
    let needsDispatch = false;
    await this.transaction(async (tx) => {
      const [account, profile] = await tx.getAll(this.account(uid), this.privateVoice(uid, id));
      this.active(account!);
      this.owned(profile!, uid);
      if (profile!.get("status") === "deleted") return;
      const jobs = await tx.get(this.db.collection(`privateAccounts/${uid}/jobs`).where("voiceProfileId", "==", id).where("state", "in", ["queued", "processing"]).limit(100));
      for (const job of jobs.docs) {
        tx.update(job.ref, { cancelRequested: true, state: "cancelled" });
        tx.update(this.publicJob(uid, job.id), { state: "cancelled" });
      }
      tx.update(profile!.ref, { status: "deleting", deletionRequestedAt: Timestamp.fromMillis(this.now()), taskKind: "deleteVoice", dispatchPending: true });
      tx.update(this.publicVoice(uid, id), { status: "deleting" });
      needsDispatch = true;
    });
    if (needsDispatch) await this.dispatch({ kind: "deleteVoice", uid, id }, this.privateVoice(uid, id));
    return {};
  }

  async deleteAccount(principal: Principal | undefined, raw: unknown) {
    const { uid } = this.authenticated(principal, true);
    const data = object(raw);
    exactKeys(data, []);
    let needsDispatch = false;
    await this.transaction(async (tx) => {
      const account = await tx.get(this.account(uid));
      if (account.get("state") === "deleted") return;
      tx.set(this.account(uid), { state: "deleting", storyGeneration: FieldValue.delete(), storyUsage: FieldValue.delete(), deletionRequestedAt: Timestamp.fromMillis(this.now()), taskKind: "deleteAccount", dispatchPending: true }, { merge: true });
      // Every API and worker checks this tombstone before reading/writing user data.
      tx.set(this.db.doc(`users/${uid}`), { state: "deleting" }, { merge: true });
      needsDispatch = true;
    });
    if (needsDispatch) await this.dispatch({ kind: "deleteAccount", uid, id: uid }, this.account(uid));
    return {};
  }

  async retryPendingDispatches(): Promise<void> {
    const pending = [
      ...((await connection("firestore", "pending_voices", () => this.db.collectionGroup("voices").where("dispatchPending", "==", true).limit(100).get())).docs),
      ...((await connection("firestore", "pending_jobs", () => this.db.collectionGroup("jobs").where("dispatchPending", "==", true).limit(100).get())).docs),
      ...((await connection("firestore", "pending_accounts", () => this.db.collection("privateAccounts").where("dispatchPending", "==", true).limit(100).get())).docs),
    ];
    diagnostic("debug", "pending_dispatch_scan_completed", { pending_count: pending.length });
    for (const snapshot of pending) {
      const path = snapshot.ref.path.split("/");
      if (path[0] !== "privateAccounts") continue;
      const uid = path[1];
      const kind = snapshot.get("taskKind");
      if (uid && ["enroll", "narrate", "deleteVoice", "deleteAccount"].includes(kind)) {
        await this.dispatch({ kind, uid, id: kind === "deleteAccount" ? uid : snapshot.id }, snapshot.ref);
      }
    }
  }
}
