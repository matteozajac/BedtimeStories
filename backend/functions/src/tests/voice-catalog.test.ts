import test from "node:test";
import assert from "node:assert/strict";
import { BUILT_IN_VOICES, builtInVoice } from "../voice-catalog";
import { narrationInput } from "../validation";

const input = (voiceProfileId: string, language: string) => ({
  requestId: "1b8069e2-d8a2-4d86-b8da-1524c7b7e903", voiceProfileId, language,
  draftId: "draft", snapshotHash: "a".repeat(64), preview: true,
  chapters: [{ id: "chapter", title: "Moon", paragraphs: [{ text: "A rabbit found the moon.", style: "gentle" }] }],
});

test("each supported language has three distinct server-owned built-in profiles", () => {
  for (const language of ["en-US", "pl-PL"]) {
    const voices = BUILT_IN_VOICES.filter((voice) => voice.language === language);
    assert.equal(voices.length, 3);
    assert.equal(new Set(voices.map((voice) => voice.providerVoice)).size, 3);
    for (const voice of voices) assert.equal(narrationInput(input(voice.id, language)).voiceProfileId, voice.id);
  }
  assert.equal(new Set(BUILT_IN_VOICES.map((voice) => voice.id)).size, BUILT_IN_VOICES.length);
});

test("built-in IDs are exact, language-bound, and never raw provider identifiers", () => {
  assert.equal(builtInVoice("builtin-pl-luna")?.providerVoice, "Sulafat");
  assert.equal(builtInVoice("Sulafat"), undefined);
  for (const id of ["builtin-pl-arbitrary", "voice_foreign", "voicekey_foreign"]) {
    assert.throws(() => narrationInput(input(id, "pl-PL")), { code: "invalid-argument" });
  }
  assert.throws(() => narrationInput(input("builtin-en-luna", "pl-PL")), { code: "invalid-argument" });
  assert.equal(narrationInput(input("owned-logical-profile", "pl-PL")).voiceProfileId, "owned-logical-profile");
});
