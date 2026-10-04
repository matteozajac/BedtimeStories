import { randomUUID } from "node:crypto";
import { FieldValue, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { Principal } from "./contracts";
import { connection, diagnostic } from "./diagnostics";
import { contentHash, exactKeys, identifier, object, requireApple } from "./validation";
import { StoryBook, StoryGenerationService, StoryInput, StoryProvider, storyInput } from "./story";

export interface StoryTask { uid: string; id: string }
export interface StoryTaskDispatcher { enqueue(task: StoryTask): Promise<void> }
const TERMINAL = ["ready", "failed", "cancelled"];
const JOB_LIFETIME = 24 * 60 * 60 * 1000;
const OPERATION_DEADLINE = 30 * 60 * 1000;
const EXECUTION_LEASE = 7 * 60 * 1000;

/** The callable commits acceptance before dispatch; disconnects cannot lose the request. */
export class StoryJobService {
  constructor(private db: Firestore, private provider: StoryProvider, private dispatcher: StoryTaskDispatcher,
    private options: { enabled: () => boolean; now?: () => number }) {}
  private now(): number { return this.options.now?.() ?? Date.now(); }
  private account(uid: string) { return this.db.doc(`privateAccounts/${uid}`); }
  private job(uid: string, id: string) { return this.db.doc(`privateAccounts/${uid}/storyJobs/${id}`); }
  private publicJob(uid: string, id: string) { return this.db.doc(`users/${uid}/storyJobs/${id}`); }
  private transaction<T>(run: (tx: Transaction) => Promise<T>) { return connection("firestore", "story_job_transaction", () => this.db.runTransaction(run)); }
  async start(principal: Principal | undefined, raw: unknown): Promise<{ jobId: string }> {
    const { uid } = requireApple(principal, this.now() / 1000);
    if (!this.options.enabled()) throw new HttpsError("unavailable", "Gemini story creation is temporarily unavailable.");
    const data = object(raw);
    exactKeys(data, ["requestId", "description", "language", "readerAge", "readingMinutes", "wordsPerMinute", "consentVersion", "cloudProcessingAccepted"]);
    const id = identifier(data.requestId), { requestId: _, ...parameters } = data;
    const input = storyInput(parameters), payloadHash = contentHash(JSON.stringify(input));
    await this.transaction(async (tx) => {
      const [account, job] = await tx.getAll(this.account(uid), this.job(uid, id));
      if (account!.exists && account!.get("state") !== "active") throw new HttpsError("permission-denied", "Cloud account deletion is in progress.");
      if (job!.exists) {
        if (job!.get("uid") !== uid || job!.get("payloadHash") !== payloadHash) throw new HttpsError("already-exists", "This request identifier has already been used.");
        return;
      }
      const expires = account!.get("storyGeneration.expiresAt");
      if (expires instanceof Timestamp && expires.toMillis() > this.now()) throw new HttpsError("resource-exhausted", "A story is already being created.", { reason: "busy" });
      const day = new Date(this.now()).toISOString().slice(0, 10), usage = account!.get("storyUsage");
      const used = usage?.day === day && Number.isInteger(usage.count) ? usage.count : 0;
      if (used >= 10) throw new HttpsError("resource-exhausted", "Your daily story limit has been reached.", { reason: "daily_limit" });
      const createdAt = Timestamp.fromMillis(this.now()), expiresAt = Timestamp.fromMillis(this.now() + JOB_LIFETIME);
      tx.set(this.account(uid), { state: "active", storyUsage: { day, count: used + 1 }, storyGeneration: { lease: id, kind: "async", expiresAt: Timestamp.fromMillis(this.now() + OPERATION_DEADLINE) } }, { merge: true });
      tx.create(this.job(uid, id), { uid, id, input, payloadHash, state: "queued", attempts: 0, dispatchPending: true, createdAt, expiresAt, deadlineAt: Timestamp.fromMillis(this.now() + OPERATION_DEADLINE) });
      tx.create(this.publicJob(uid, id), { uid, id, state: "queued", progress: 0, language: input.language, wordsPerMinute: input.wordsPerMinute, createdAt, expiresAt });
    });
    const job = await this.job(uid, id).get();
    if (job.get("dispatchPending") === true && !TERMINAL.includes(job.get("state"))) await this.dispatch({ uid, id });
    return { jobId: id };
  }
  private async dispatch(task: StoryTask): Promise<void> {
    try {
      await this.dispatcher.enqueue(task);
      await this.transaction(async (tx) => {
        const job = await tx.get(this.job(task.uid, task.id));
        if (job.exists && !TERMINAL.includes(job.get("state"))) tx.update(job.ref, { dispatchPending: false, dispatchedAt: Timestamp.fromMillis(this.now()) });
      });
    } catch (error) {
      diagnostic("warn", "story_dispatch_deferred", { recovery: "durable_outbox_retry" }, error);
    }
  }
  async cancel(principal: Principal | undefined, raw: unknown): Promise<Record<string, never>> {
    const { uid } = requireApple(principal, this.now() / 1000), data = object(raw);
    exactKeys(data, ["jobId"]);
    const id = identifier(data.jobId);
    await this.transaction(async (tx) => {
      const [account, job] = await tx.getAll(this.account(uid), this.job(uid, id));
      if (!account!.exists || account!.get("state") !== "active") throw new HttpsError("permission-denied", "Cloud account deletion is in progress.");
      if (!job!.exists || job!.get("uid") !== uid) throw new HttpsError("not-found", "This story request is unavailable.");
      if (TERMINAL.includes(job!.get("state"))) return;
      const completedAt = Timestamp.fromMillis(this.now());
      tx.update(job!.ref, { state: "cancelled", dispatchPending: false, input: FieldValue.delete(), deadlineAt: FieldValue.delete(), completedAt });
      tx.update(this.publicJob(uid, id), { state: "cancelled", completedAt });
      if (account!.get("storyGeneration.lease") === id) tx.update(account!.ref, { storyGeneration: FieldValue.delete() });
    });
    return {};
  }
  async process(raw: unknown): Promise<void> {
    const data = object(raw); exactKeys(data, ["uid", "id"]);
    const uid = identifier(data.uid), id = identifier(data.id), execution = randomUUID();
    const reserved = await this.transaction(async (tx) => {
      const [account, job] = await tx.getAll(this.account(uid), this.job(uid, id));
      if (!account!.exists || account!.get("state") !== "active" || !job!.exists || job!.get("uid") !== uid || TERMINAL.includes(job!.get("state"))) return undefined;
      const deadline = job!.get("deadlineAt");
      if (account!.get("storyGeneration.lease") !== id || deadline instanceof Timestamp && deadline.toMillis() <= this.now()) {
        const completedAt = Timestamp.fromMillis(this.now());
        tx.update(job!.ref, { state: "failed", errorCode: "expired", dispatchPending: false, input: FieldValue.delete(), deadlineAt: FieldValue.delete(), completedAt });
        tx.update(this.publicJob(uid, id), { state: "failed", errorCode: "expired", completedAt });
        if (account!.get("storyGeneration.lease") === id) tx.update(account!.ref, { storyGeneration: FieldValue.delete() });
        return undefined;
      }
      const runningUntil = job!.get("processingUntil");
      if (job!.get("state") === "processing" && runningUntil instanceof Timestamp && runningUntil.toMillis() > this.now()) throw new HttpsError("aborted", "This story request is already processing.");
      const attempts = (job!.get("attempts") ?? 0) + 1;
      tx.update(job!.ref, { state: "processing", execution, attempts, dispatchPending: false, processingUntil: Timestamp.fromMillis(this.now() + EXECUTION_LEASE) });
      tx.update(this.publicJob(uid, id), { state: "processing", progress: 0.08 });
      return { input: job!.get("input") as StoryInput, attempts };
    });
    if (!reserved) return;
    const generator = new StoryGenerationService(this.db, this.provider, this.options);
    try {
      const book = await generator.generateReserved(uid, reserved.input, id, async (progress) => {
        await this.transaction(async (tx) => {
          const [account, job] = await tx.getAll(this.account(uid), this.job(uid, id));
          if (!account!.exists || account!.get("state") !== "active" || account!.get("storyGeneration.lease") !== id || !job!.exists || job!.get("execution") !== execution || job!.get("state") !== "processing") throw new HttpsError("cancelled", "This request is no longer active.");
          tx.update(this.publicJob(uid, id), { progress });
        });
      });
      if (Buffer.byteLength(JSON.stringify(book), "utf8") > 800000) throw new HttpsError("internal", "The story could not be completed.", { reason: "incomplete_story" });
      await this.finish(uid, id, execution, "ready", { result: book, progress: 1 });
    } catch (error) {
      diagnostic("warn", "story_job_attempt_failed", { attempt: reserved.attempts }, error);
      const code = error instanceof HttpsError ? error.code : "unavailable";
      const reason = (error instanceof HttpsError ? error.details : undefined) as { reason?: string } | undefined;
      const retryable = ["unavailable", "resource-exhausted"].includes(code) && reserved.attempts < 3;
      if (retryable) {
        const retry = await this.transaction(async (tx) => {
          const [account, job] = await tx.getAll(this.account(uid), this.job(uid, id));
          if (!account!.exists || account!.get("state") !== "active" || account!.get("storyGeneration.lease") !== id || !job!.exists || job!.get("execution") !== execution || job!.get("state") !== "processing") return false;
          tx.update(job!.ref, { state: "queued", execution: FieldValue.delete(), processingUntil: FieldValue.delete() });
          tx.update(this.publicJob(uid, id), { state: "queued", progress: 0 });
          return true;
        });
        if (retry) throw error;
      } else await this.finish(uid, id, execution, "failed", { errorCode: code, ...(reason?.reason && ["refused", "incomplete_story", "busy"].includes(reason.reason) ? { reason: reason.reason } : {}) });
    }
  }
  private async finish(uid: string, id: string, execution: string, state: "ready" | "failed", fields: { result?: StoryBook; progress?: number; errorCode?: string; reason?: string }): Promise<void> {
    await this.transaction(async (tx) => {
      const [account, job] = await tx.getAll(this.account(uid), this.job(uid, id));
      if (!account!.exists || account!.get("state") !== "active" || account!.get("storyGeneration.lease") !== id || !job!.exists || job!.get("execution") !== execution || job!.get("state") !== "processing") return;
      const completedAt = Timestamp.fromMillis(this.now());
      tx.update(job!.ref, { state, completedAt, input: FieldValue.delete(), deadlineAt: FieldValue.delete(), execution: FieldValue.delete(), processingUntil: FieldValue.delete(), dispatchPending: false });
      tx.update(this.publicJob(uid, id), { state, ...fields, completedAt });
      tx.update(account!.ref, { storyGeneration: FieldValue.delete() });
    });
  }
  async retryAndClean(): Promise<void> {
    const pending = await this.db.collectionGroup("storyJobs").where("dispatchPending", "==", true).limit(100).get();
    for (const job of pending.docs) {
      const path = job.ref.path.split("/");
      if (path[0] === "privateAccounts" && path[1] && !TERMINAL.includes(job.get("state"))) await this.dispatch({ uid: path[1], id: job.id });
    }
    // A deadline lives on each job, so a replacement account lease cannot hide its predecessor.
    const overdue = await this.db.collectionGroup("storyJobs").where("deadlineAt", "<=", Timestamp.fromMillis(this.now())).limit(100).get();
    for (const expired of overdue.docs) {
      const path = expired.ref.path.split("/");
      if (path[0] !== "privateAccounts" || !path[1]) continue;
      const uid = path[1];
      await this.transaction(async (tx) => {
        const [account, job] = await tx.getAll(this.account(uid), expired.ref);
        const deadline = job!.get("deadlineAt");
        if (account!.get("state") !== "active" || !job!.exists || !(deadline instanceof Timestamp) || deadline.toMillis() > this.now()) return;
        if (!TERMINAL.includes(job!.get("state"))) {
          const completedAt = Timestamp.fromMillis(this.now());
          tx.update(job!.ref, { state: "failed", errorCode: "expired", completedAt, dispatchPending: false, input: FieldValue.delete(), deadlineAt: FieldValue.delete() });
          tx.update(this.publicJob(uid, job!.id), { state: "failed", errorCode: "expired", completedAt });
        }
        if (account!.get("storyGeneration.lease") === job!.id) tx.update(account!.ref, { storyGeneration: FieldValue.delete() });
      });
    }
    const old = await this.db.collectionGroup("storyJobs").where("expiresAt", "<=", Timestamp.fromMillis(this.now())).limit(100).get();
    for (const job of old.docs) {
      const path = job.ref.path.split("/");
      if (path[0] !== "privateAccounts" || !path[1]) continue;
      const batch = this.db.batch(); batch.delete(job.ref); batch.delete(this.publicJob(path[1], job.id)); await batch.commit();
    }
  }
}
