import { test } from "node:test";
import assert from "node:assert/strict";
import { HttpsError } from "firebase-functions/v2/https";
import { parseStoryResponse, storyInput, validateStory, wordCount, STORY_CONSENT_VERSION, StoryOutputError, storyPrompt, storySchema } from "../story";

const raw = { description: "Mały lis wraca do domu pod gwiazdami.", language: "polish", readerAge: "3–5", readingMinutes: 1, wordsPerMinute: 80, consentVersion: STORY_CONSENT_VERSION, cloudProcessingAccepted: true };
const prose = Array.from({ length: 80 }, (_, i) => i === 79 ? "zasnął." : "księżyc").join(" ");
const book = () => ({ title: "Lis i księżyc", summary: "Lis wrócił do domu.", chapters: [{ title: "Pod gwiazdami", text: prose }], illustrationGuide: "A small amber fox under stars in warm pastel colors." });
const rejectsCode = (code: string) => (error: unknown) => error instanceof HttpsError && error.code === code;

test("story input accepts Polish and rejects ownership/provider injection and missing consent", () => {
  const input = storyInput(raw);
  assert.equal(input.language, "polish"); assert.equal(input.description, raw.description);
  for (const field of ["uid", "model", "prompt", "previousWordCount", "providerKey"]) assert.throws(() => storyInput({ ...raw, [field]: "injected" }), rejectsCode("invalid-argument"));
  for (const patch of [{ cloudProcessingAccepted: false }, { consentVersion: "old" }]) assert.throws(() => storyInput({ ...raw, ...patch }), rejectsCode("failed-precondition"));
});
test("story input bounds duration, pace, enums and Unicode description bytes", () => {
  for (const patch of [{ readingMinutes: 0 }, { readingMinutes: 31 }, { readingMinutes: 1.5 }, { wordsPerMinute: 79 }, { wordsPerMinute: NaN }, { wordsPerMinute: 181 }, { language: "pl-PL" }, { readerAge: "3-5" }, { description: " " }, { description: "a".repeat(601) }, { description: "a\u0000b" }]) assert.throws(() => storyInput({ ...raw, ...patch }), rejectsCode("invalid-argument"));
  assert.doesNotThrow(() => storyInput({ ...raw, description: "🦊".repeat(600) }));
});
test("Unicode word counts and full Polish book validation match the app", () => {
  assert.equal(wordCount("Żółw śpi. 123 — 🦊"), 2);
  assert.deepEqual(validateStory(book(), storyInput(raw)), book());
  const decorated = book(); decorated.title = "\u200bLis i księżyc ";
  assert.equal(validateStory(decorated, storyInput(raw)).title, "Lis i księżyc");
  const short = book(); short.chapters[0]!.text = prose.split(" ").slice(0, 60).join(" ") + ".";
  assert.throws(() => validateStory(short, storyInput(raw)), (error: unknown) => error instanceof StoryOutputError && error.reason === "reading_length" && error.words === 60);
});
test("reject empty, unfinished, duplicate, oversized and unexpected generated fields", () => {
  for (const candidate of [{ ...book(), summary: "" }, { ...book(), title: "a".repeat(161) }, { ...book(), chapters: [] }, { ...book(), illustrationGuide: "a".repeat(401) }, { ...book(), secret: "extra" }, { ...book(), chapters: [{ title: "Rozdział", text: prose.slice(0, -1) }] }]) assert.throws(() => validateStory(candidate, storyInput(raw)), StoryOutputError);
  const input = storyInput({ ...raw, readingMinutes: 2 });
  assert.throws(() => validateStory({ ...book(), chapters: [book().chapters[0], book().chapters[0]] }, input), (error: unknown) => error instanceof StoryOutputError && error.reason === "duplicate_chapter");
});
test("parse only a complete final candidate, rejecting safety/truncation and thought text", () => {
  assert.deepEqual(parseStoryResponse({ candidates: [{ finishReason: "STOP", content: { parts: [{ thought: true, text: "private reasoning" }, { text: JSON.stringify(book()) }] } }] }), book());
  assert.throws(() => parseStoryResponse({ candidates: [{ finishReason: "MAX_TOKENS", content: { parts: [{ text: JSON.stringify(book()) }] } }] }), StoryOutputError);
  assert.throws(() => parseStoryResponse({ candidates: [{ finishReason: "STOP", content: { parts: [{ thought: true, text: JSON.stringify(book()) }] } }] }), StoryOutputError);
  assert.throws(() => parseStoryResponse({ promptFeedback: { blockReason: "SAFETY" } }), rejectsCode("failed-precondition"));
});
test("server prompt preserves Polish brief as JSON data and uses whole-book length correction", () => {
  const prompt = storyPrompt(storyInput(raw), 60);
  assert.match(prompt, /idiomatic Polish/); assert.match(prompt, /80-word prose target/);
  assert.ok(prompt.includes(JSON.stringify({ idea: raw.description })));
});

test("long books receive a fixed chapter budget in both prompt and schema", () => {
  const input = storyInput({ ...raw, readingMinutes: 30, wordsPerMinute: 180 });
  const schema = storySchema(input);
  assert.equal(schema.properties.chapters.minItems, 12);
  assert.equal(schema.properties.chapters.maxItems, 12);
  assert.match(schema.properties.chapters.items.properties.text.description, /450 words/);
  assert.match(storyPrompt(input, 3979), /1421 more words/);
});

test("a short complete story is supplied as untrusted expansion context", () => {
  const prompt = storyPrompt(storyInput(raw), 60, book());
  assert.ok(prompt.includes(JSON.stringify(book())));
  assert.match(prompt, /rather than starting over/);
  assert.match(prompt, /untrusted fictional data/);
});

test("long-story expansion keeps its writing budget inside the accepted upper bound", () => {
  const input = storyInput({ ...raw, readingMinutes: 30, wordsPerMinute: 180 });
  const expanded = storySchema(input, true);
  assert.match(expanded.properties.chapters.items.properties.text.description, /513 words/);
  assert.match(storyPrompt(input, 3611, book()), /6155 prose words/);
});
