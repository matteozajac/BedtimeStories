export const CONSENT_VERSION = "2026-10-01";
// Provider-verbatim consent scripts, Gemini Enterprise Voices API, verified 2026-10-02.
// https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/text-to-speech/voice-replication
export const CONSENT_STATEMENTS = {
  "en-US": "I am the owner of this voice and have consented to the creation of a synthetic model of my voice through the use of Google Cloud",
  "pl-PL": "Jestem właścicielem tego głosu i wyraziłem zgodę na utworzenie syntetycznego modelu mojego głosu za pomocą Google Cloud",
} as const;

export type Language = keyof typeof CONSENT_STATEMENTS;
export const NARRATION_STYLES = ["natural", "gentle", "curious", "excited", "reassuring", "whispered"] as const;
export type NarrationStyle = typeof NARRATION_STYLES[number];
export type RecordingKind = "reference" | "consent";
export type TaskKind = "enroll" | "narrate" | "deleteVoice" | "deleteAccount";
export interface WorkerTask { kind: TaskKind; uid: string; id: string }
export interface Principal { uid: string; provider: string; authTime: number }
export interface Paragraph { text: string; style: NarrationStyle }
export interface Chapter { id: string; title: string; paragraphs: Paragraph[] }
export interface NarrationInput {
  requestId: string;
  voiceProfileId: string;
  draftId: string;
  snapshotHash: string;
  language: Language;
  preview: boolean;
  chapters: Chapter[];
}
export interface EncryptedRecording {
  version: 1;
  uid: string;
  voiceId: string;
  kind: RecordingKind;
  kmsKeyName: string;
  wrappedKey: string;
  iv: string;
  ciphertext: string;
}
export interface RecordingObject { path: string; sha256: string; bytes: number; duration: number }
export interface RecordingStore {
  save(uid: string, enrollmentId: string, kind: RecordingKind, audio: Buffer): Promise<RecordingObject>;
  remove(path: string): Promise<void>;
}
export interface TaskDispatcher { enqueue(task: WorkerTask): Promise<void> }

export const LIMITS = {
  enrollmentTTLSeconds: 60 * 60,
  outputTTLSeconds: 30 * 24 * 60 * 60,
  recentAuthSeconds: 5 * 60,
  enrollmentAttemptsPerDay: 5,
  activeVoices: 3,
  previewsPerDay: 20,
  booksPerDay: 5,
  maxChapters: 50,
  maxParagraphsPerChapter: 300,
  maxParagraphCharacters: 8000,
  maxBookCharacters: 50000,
  maxBookWords: 5400,
  maxPreviewCharacters: 1500,
  maxRecordingBytes: 2 * 1024 * 1024,
} as const;
