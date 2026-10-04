import { AsyncLocalStorage } from "node:async_hooks";
import { createHash, randomUUID } from "node:crypto";
import { basename } from "node:path";
import * as logger from "firebase-functions/logger";
import { HttpsError } from "firebase-functions/v2/https";
import { WorkerTask } from "./contracts";

type Fields = Record<string, string | number | boolean>;
type Level = "debug" | "info" | "warn" | "error";
const context = new AsyncLocalStorage<Fields>();
const phases = new WeakMap<object, { connection: string; phase: string }>();
const namePattern = /^[A-Za-z0-9_.$<>-]{1,160}$/;
const safeStringCodes = new Set([
  "ECONNRESET", "ECONNREFUSED", "ETIMEDOUT", "EAI_AGAIN", "ENOTFOUND", "EPIPE", "ABORT_ERR",
  "auth/id-token-expired", "auth/id-token-revoked", "auth/user-disabled", "auth/user-not-found",
  "auth/invalid-id-token", "auth/argument-error", "auth/internal-error", "auth/insufficient-permission",
  "messaging/third-party-auth-error", "messaging/invalid-apns-credentials", "messaging/authentication-error",
  "messaging/mismatched-credential", "messaging/registration-token-not-registered", "messaging/invalid-registration-token",
  "messaging/invalid-argument", "messaging/invalid-payload", "messaging/invalid-options",
  "messaging/internal-error", "messaging/server-unavailable", "messaging/message-rate-exceeded", "messaging/device-message-rate-exceeded",
]);

export function taskKey(task: WorkerTask): string {
  return createHash("sha256").update(`${task.kind}:${task.uid}:${task.id}`).digest("hex");
}

export function withDiagnosticContext<T>(fields: Fields, execute: () => T): T {
  return context.run({ ...context.getStore(), ...fields }, execute);
}

export function preserveCause<T extends Error>(error: T, cause: unknown): T {
  Object.defineProperty(error, "cause", { value: cause, configurable: true });
  return error;
}

function frames(stack: unknown, error?: Error) {
  if (typeof stack !== "string") return [];
  let source = stack;
  if (error) {
    // A multi-line provider message may itself contain text that resembles a frame.
    // Remove its complete header before parsing any source positions.
    const header = `${error.name}: ${error.message}`;
    if (!source.startsWith(header)) return [];
    source = source.slice(header.length);
  }
  // Discard the message line and retain only V8 source positions. No URLs, source lines, or locals.
  return source.split("\n").slice(1).flatMap((line) => {
    const match = /^\s*at\s+(?:(.*?)\s+\()?(.+?):(\d+):(\d+)\)?$/.exec(line);
    if (!match) return [];
    const file = basename(match[2]!);
    if (!namePattern.test(file)) return [];
    const rawFunction = match[1] ?? "<anonymous>";
    return [{ file, function: namePattern.test(rawFunction) ? rawFunction : "<anonymous>", line: Number(match[3]), column: Number(match[4]) }];
  }).slice(-24);
}

export function errorSnapshot(error: unknown): { causes: Record<string, unknown>[]; cause_chain_truncated: boolean } {
  const causes: Record<string, unknown>[] = [];
  const seen = new Set<unknown>();
  let current = error;
  while (current !== undefined && current !== null && !seen.has(current) && causes.length < 5) {
    seen.add(current);
    if (!(current instanceof Error)) {
      causes.push({ type: "NonErrorThrow", stack_origin: "reporting", frames: frames(new Error().stack) });
      current = undefined;
      break;
    }
    const type = current.constructor.name;
    const item: Record<string, unknown> = { type: namePattern.test(type) ? type : "Error",
      stack_origin: typeof current.stack === "string" ? "exception" : "reporting",
      frames: typeof current.stack === "string" ? frames(current.stack, current) : frames(new Error().stack) };
    const code = (current as Error & { code?: unknown }).code;
    if (current instanceof HttpsError || (typeof code === "number" && Number.isInteger(code)) || (typeof code === "string" && safeStringCodes.has(code))) item.code = code;
    const status = (current as Error & { status?: unknown; statusCode?: unknown }).status ?? (current as Error & { statusCode?: unknown }).statusCode;
    if (typeof status === "number" && Number.isInteger(status) && status >= 100 && status <= 599) item.http_status = status;
    const phase = phases.get(current);
    if (phase) Object.assign(item, phase);
    causes.push(item);
    current = current.cause;
  }
  return { causes, cause_chain_truncated: current !== undefined && current !== null };
}

export function diagnosticEntry(event: string, fields: Fields = {}, error?: unknown): Record<string, unknown> {
  return { event, ...context.getStore(), ...fields, ...(error === undefined ? {} : { error: errorSnapshot(error) }) };
}

export function diagnostic(level: Level, event: string, fields: Fields = {}, error?: unknown): void {
  logger[level](event, diagnosticEntry(event, fields, error));
}

export async function connection<T>(service: string, phase: string, execute: () => Promise<T>, fields: Fields = {}): Promise<T> {
  const started = performance.now();
  diagnostic("debug", "connection_started", { connection: service, phase, ...fields });
  try {
    const result = await execute();
    diagnostic("debug", "connection_completed", { connection: service, phase, elapsed_ms: Math.round(performance.now() - started), ...fields });
    return result;
  } catch (error) {
    if (error instanceof Error && !phases.has(error)) phases.set(error, { connection: service, phase });
    // The operation owner reports the error once with its preserved cause chain.
    diagnostic("debug", "connection_failed", { connection: service, phase, elapsed_ms: Math.round(performance.now() - started), ...fields });
    throw error;
  }
}

export async function operation<T>(name: string, execute: () => Promise<T>): Promise<T> {
  return withDiagnosticContext({ operation: name, operation_id: randomUUID() }, async () => {
    const started = performance.now();
    diagnostic("debug", "cloud_operation_started");
    try {
      const result = await execute();
      diagnostic("info", "cloud_operation_completed", { elapsed_ms: Math.round(performance.now() - started) });
      return result;
    } catch (error) {
      const recoverable = error instanceof HttpsError && !["internal", "unknown", "data-loss"].includes(error.code);
      diagnostic(recoverable ? "warn" : "error", "cloud_operation_failed", { elapsed_ms: Math.round(performance.now() - started) }, error);
      throw error;
    }
  });
}
