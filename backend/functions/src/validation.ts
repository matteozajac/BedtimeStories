import { createHash } from "node:crypto";
import { HttpsError } from "firebase-functions/v2/https";
import { CONSENT_VERSION, Chapter, Language, LIMITS, NARRATION_STYLES, NarrationInput, NarrationStyle, Principal, RecordingKind } from "./contracts";
import { builtInVoice } from "./voice-catalog";

export function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new HttpsError("invalid-argument", "Invalid request.");
  return value as Record<string, unknown>;
}
export function exactKeys(data: Record<string, unknown>, keys: string[]): void {
  if (Object.keys(data).some((key) => !keys.includes(key))) throw new HttpsError("invalid-argument", "Unexpected request fields.");
}
export function string(value: unknown, maximum: number, label: string): string {
  if (typeof value !== "string" || !value.trim() || value.length > maximum || value.includes("\u0000")) {
    throw new HttpsError("invalid-argument", `Invalid ${label}.`);
  }
  return value;
}
export function identifier(value: unknown): string {
  const result = string(value, 128, "identifier");
  if (!/^[A-Za-z0-9_-]+$/.test(result)) throw new HttpsError("invalid-argument", "Invalid identifier.");
  return result;
}
export function uuid(value: unknown): string {
  const result = identifier(value);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(result)) {
    throw new HttpsError("invalid-argument", "Invalid request ID.");
  }
  return result.toLowerCase();
}
export function language(value: unknown): Language {
  if (value !== "en-US" && value !== "pl-PL") throw new HttpsError("invalid-argument", "Unsupported language.");
  return value;
}
export function requireApple(principal: Principal | undefined, now: number, recent = false): Principal {
  if (!principal?.uid || principal.provider !== "apple.com") throw new HttpsError("unauthenticated", "Sign in with Apple to continue.");
  identifier(principal.uid);
  if (recent && (!Number.isFinite(principal.authTime) || principal.authTime > now + 60 || now - principal.authTime > LIMITS.recentAuthSeconds)) {
    throw new HttpsError("unauthenticated", "Sign in again to delete your cloud data.");
  }
  return principal;
}
export function enrollmentInput(raw: unknown): { displayName: string; language: Language } {
  const data = object(raw);
  exactKeys(data, ["displayName", "language", "consentVersion", "retentionAccepted"]);
  if (data.consentVersion !== CONSENT_VERSION || data.retentionAccepted !== true) {
    throw new HttpsError("failed-precondition", "Review and accept the current voice consent and retention information.");
  }
  return { displayName: string(data.displayName, 80, "voice name").trim(), language: language(data.language) };
}
export function narrationInput(raw: unknown): NarrationInput {
  const data = object(raw);
  exactKeys(data, ["requestId", "voiceProfileId", "draftId", "snapshotHash", "language", "preview", "chapters"]);
  const hash = string(data.snapshotHash, 64, "snapshot hash");
  if (!/^[0-9a-f]{64}$/i.test(hash)) throw new HttpsError("invalid-argument", "Invalid snapshot hash.");
  if (typeof data.preview !== "boolean") throw new HttpsError("invalid-argument", "Invalid preview choice.");
  if (!Array.isArray(data.chapters) || data.chapters.length < 1 || data.chapters.length > LIMITS.maxChapters) {
    throw new HttpsError("invalid-argument", "Invalid chapter count.");
  }
  const chapters: Chapter[] = data.chapters.map((rawChapter) => {
    const chapter = object(rawChapter);
    exactKeys(chapter, ["id", "title", "paragraphs"]);
    if (!Array.isArray(chapter.paragraphs) || chapter.paragraphs.length < 1 || chapter.paragraphs.length > LIMITS.maxParagraphsPerChapter) {
      throw new HttpsError("invalid-argument", "Invalid paragraph count.");
    }
    return {
      id: identifier(chapter.id),
      title: typeof chapter.title === "string" && chapter.title.length <= 200 ? chapter.title : (() => { throw new HttpsError("invalid-argument", "Invalid chapter title."); })(),
      paragraphs: chapter.paragraphs.map((rawParagraph) => {
        const paragraph = object(rawParagraph);
        exactKeys(paragraph, ["text", "style"]);
        return {
          text: string(paragraph.text, LIMITS.maxParagraphCharacters, "paragraph"),
          style: typeof paragraph.style === "string" && (NARRATION_STYLES as readonly string[]).includes(paragraph.style) ? paragraph.style as NarrationStyle : (() => { throw new HttpsError("invalid-argument", "Invalid narration style."); })(),
        };
      }),
    };
  });
  if (new Set(chapters.map((chapter) => chapter.id)).size !== chapters.length) throw new HttpsError("invalid-argument", "Duplicate chapter identifiers.");
  const characters = chapters.reduce((total, chapter) => total + chapter.paragraphs.reduce((sum, paragraph) => sum + paragraph.text.length, 0), 0);
  if (characters > (data.preview ? LIMITS.maxPreviewCharacters : LIMITS.maxBookCharacters)) throw new HttpsError("resource-exhausted", "This narration is too long.");
  const words = chapters.reduce((total, chapter) => total + chapter.paragraphs.reduce((sum, paragraph) => sum + paragraph.text.trim().split(/\s+/u).length, 0), 0);
  if (!data.preview && words > LIMITS.maxBookWords) throw new HttpsError("resource-exhausted", "A cloud narration can contain up to 5,400 words.");
  const result: NarrationInput = {
    requestId: uuid(data.requestId), voiceProfileId: identifier(data.voiceProfileId), draftId: identifier(data.draftId),
    snapshotHash: hash.toLowerCase(), language: language(data.language), preview: data.preview, chapters,
  };
  const builtIn = builtInVoice(result.voiceProfileId);
  if ((result.voiceProfileId.startsWith("builtin-") && !builtIn) || /^voice(?:key)?_/u.test(result.voiceProfileId)) {
    throw new HttpsError("invalid-argument", "Choose an available narrator profile.");
  }
  if (builtIn && builtIn.language !== result.language) throw new HttpsError("invalid-argument", "Choose a narrator for this language.");
  if (Buffer.byteLength(JSON.stringify(result), "utf8") > 750000) throw new HttpsError("resource-exhausted", "This narration contains too much data.");
  return result;
}
export function contentHash(value: unknown): string { return createHash("sha256").update(JSON.stringify(value)).digest("hex"); }

export function decodeRecording(raw: unknown, kind: RecordingKind): { audio: Buffer; duration: number } {
  if (typeof raw !== "string" || raw.length > Math.ceil(LIMITS.maxRecordingBytes / 3) * 4 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(raw)) {
    throw new HttpsError("invalid-argument", "Invalid recording data.");
  }
  const audio = Buffer.from(raw, "base64");
  if (audio.length < 44 || audio.length > LIMITS.maxRecordingBytes || audio.toString("ascii", 0, 4) !== "RIFF" || audio.toString("ascii", 8, 12) !== "WAVE" || audio.readUInt32LE(4) + 8 !== audio.length) {
    throw new HttpsError("invalid-argument", "Record a mono WAV at 24 kHz, 16-bit PCM.");
  }
  let offset = 12;
  let format = false;
  let dataBytes = 0;
  let sawData = false;
  while (offset + 8 <= audio.length) {
    const id = audio.toString("ascii", offset, offset + 4);
    const bytes = audio.readUInt32LE(offset + 4);
    const start = offset + 8;
    if (start + bytes > audio.length) throw new HttpsError("invalid-argument", "Incomplete WAV recording.");
    if (id === "fmt ") {
      if (format || bytes < 16 || audio.readUInt16LE(start) !== 1 || audio.readUInt16LE(start + 2) !== 1 || audio.readUInt32LE(start + 4) !== 24000 || audio.readUInt32LE(start + 8) !== 48000 || audio.readUInt16LE(start + 12) !== 2 || audio.readUInt16LE(start + 14) !== 16) {
        throw new HttpsError("invalid-argument", "Record a mono WAV at 24 kHz, 16-bit PCM.");
      }
      format = true;
    } else if (id === "data") {
      if (sawData || bytes % 2 !== 0) throw new HttpsError("invalid-argument", "Invalid WAV recording.");
      sawData = true;
      dataBytes = bytes;
    }
    offset = start + bytes + bytes % 2;
  }
  const duration = dataBytes / 48000;
  if (!format || !sawData || offset !== audio.length || duration < (kind === "reference" ? 10 : 2) || duration > 30) {
    throw new HttpsError("invalid-argument", kind === "reference" ? "Record 10 to 30 seconds of your voice." : "Record the complete consent statement within 30 seconds.");
  }
  return { audio, duration };
}
