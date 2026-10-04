import { Language } from "./contracts";

// Gemini 3.8 prebuilt names verified in the provider's primary documentation on 2026-10-04.
// https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/text-to-speech/overview
// Clients submit logical profile IDs only; this provider mapping remains server-owned.
export const BUILT_IN_VOICES = [
  { id: "builtin-en-luna", language: "en-US", providerVoice: "Sulafat" },
  { id: "builtin-en-milo", language: "en-US", providerVoice: "Achernar" },
  { id: "builtin-en-robin", language: "en-US", providerVoice: "Umbriel" },
  { id: "builtin-pl-luna", language: "pl-PL", providerVoice: "Sulafat" },
  { id: "builtin-pl-milo", language: "pl-PL", providerVoice: "Achernar" },
  { id: "builtin-pl-robin", language: "pl-PL", providerVoice: "Umbriel" },
] as const satisfies readonly { id: string; language: Language; providerVoice: string }[];

export function builtInVoice(id: string) {
  return BUILT_IN_VOICES.find((voice) => voice.id === id);
}
