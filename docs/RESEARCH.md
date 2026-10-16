# Research notes (2026-10-16)

Focused research to make decisions, not a market report. Sources are listed per section; third-party comparison pages are often written by competing vendors and are treated as weak evidence.

## Products people would compare Saywell with

| Product | Model of work | What it does well | Gap relevant to Saywell |
| --- | --- | --- | --- |
| Apple Dictation | Built into macOS, Fn/Globe | Zero setup, on-device on Apple silicon | No modes, no control over editing, no learning |
| Superwhisper | Local Whisper + optional cloud, “modes” with prompts, paid | Mode switching, local recognition | Editing is silent; no explanation of what changed or why |
| Wispr Flow | Cloud recognition and cleanup, subscription | Polished cleanup, cross-platform | Audio leaves the device; no local path |
| VoiceInk | Open source (GPL-3.0), local Whisper/Parakeet, per-app modes | Transparent, inexpensive | Same silent-cleanup model; GPL code cannot be reused in a permissively licensed project |
| MacWhisper | File transcription first, dictation added later | Long recordings, export | Dictation is secondary |
| Jot, Raycast Dictation, VoiceX | Local or cloud cleanup | Remove fillers, fix grammar | Correct text without teaching anything |

Pattern: every dictation tool either inserts raw text or **silently** improves it. Learning products (spaced repetition, tutors) are separate apps with their own content. No reviewed product shows a learner *their own* everyday sentence with the precise change, distinguishes recognition errors from learner errors, and lets them practise that construction, while keeping the inserted text free of explanations.

Saywell's differentiation, stated narrowly: **dictation with visible, bounded editing (four levels with integrity checks) plus optional feedback on your own sentences that never ends up in your text.** It is not claimed to be unique beyond this comparison.

Decisions taken from this:

- Modes are the main customization (as in Superwhisper/VoiceInk), but every mode shows in one line what it will do (languages · editing level · learning · output).
- Editing is never silent: a comparison view shows removed/added words; numbers/links/negation are checked.
- Learning is opt-in per mode and appears only in the app.
- Local recognition is the default; cloud is only for text, and only when a mode needs it.

Sources: [VoiceInk repository/licence summary](https://sourceforge.net/mirror/voiceink/), [Spokenly comparison (vendor)](https://spokenly.app/blog/wispr-flow-vs-superwhisper-vs-macwhisper), [zackproser.com overview](https://zackproser.com/blog/best-mac-dictation-app-2026), [buildbetter.ai overview](https://blog.buildbetter.ai/best-superwhisper-alternatives-in-2026-top-local-ai-dictation-tools-for-mac/), [Jot](https://peerlist.io/jamychatterjee/project/jot), [Raycast dictation manual](https://manual.raycast.com/ai/dictation.md).

## Recognition engines

| Candidate | Russian | Mixed RU/EN | Mac integration | Decision |
| --- | --- | --- | --- | --- |
| Whisper large-v3-turbo via MLX (current) | Strong (FLEURS RU WER ≈4–5 % for large-v3 class per published tables) | Works per phrase with language ID | Python runtime, Apple silicon only | **Keep as primary.** Measured here: ~0.8 s warm for 2–8 s clips on M4 Pro |
| WhisperKit (Core ML, Swift) | Same Whisper weights | Same | Native Swift package, no Python | **Roadmap**: removes the Python runtime; needs first-load compile time and integration work |
| NVIDIA Parakeet TDT 0.6B v3 | Supported (25 languages), slightly weaker on RU in vendor tables | Weaker coverage | Core ML ports exist (FluidAudio) | Not now: English-centric speed advantage matters less than Russian quality here |
| Apple `DictationTranscriber` (macOS 26+) | Supported (54 locales on this Mac, incl. ru) | One locale per session | Native, system-managed assets | **Added** as zero-setup engine for one-language modes |
| Apple `SpeechTranscriber` | **Not supported** on this Mac (45 locales, no ru) | — | Native | Not used: would fail the primary user |

Locale lists above were read on this Mac with the Speech framework (`supportedLocales`). Sources: [WhisperKit README](https://cdn.jsdelivr.net/gh/argmaxinc/whisperkit@main/README.md), [Parakeet vs Whisper (vendor benchmark)](https://whispernotes.app/blog/parakeet-v3-default-mac-model), [mlx-community/whisper-large-v3-turbo](https://huggingface.co/mlx-community/whisper-large-v3-turbo).

## Text model

OpenAI's model list (developers.openai.com/api/docs/models, read 2026-10-16) shows `gpt-6-luna` as the most efficient model, $0.10 / $0.50 per million input/output tokens, and the only flagship accepting `reasoning.effort = none`. Structured Outputs (`text.format` with `json_schema`, `strict: true`) are supported by the Responses API. Saywell defaults to `gpt-6-luna` with no reasoning, `store: false`, and offers “List models” so the default is not hard-wired to one account. A short dictation (≈100 input + 100 output tokens plus instructions ≈ 600 tokens) costs roughly $0.0001.

## Name

Candidates checked with a preliminary web search (not a trademark search):

| Name | Meaning | Collision found |
| --- | --- | --- |
| **Saywell** | “say it well”: speaking, and getting better at it | None for software found |
| Sotto | sotto voce | Existing Mac dictation app (Sotto by Kitze) — rejected |
| Utter | to speak | “utter” dictation app, “Utterly Voice” — rejected |
| Sayso | on your say-so | Several voice-input products — rejected |
| Parla | Italian “speaks” | ParlaParla dictation app — rejected |
| Glossa | tongue; gloss = explanation | No Mac app, but close to Glossika (language learning) — risky |
| Dictum | a said word | None found; generic Latin word, weak link to learning |
| Inkling | ink + a small hint of understanding | Inkling is an established education brand — risky |

Shortlist: **Saywell**, Dictum, Glossa. Recommendation: **Saywell** — two common English words, pronounceable in Russian, German and Chinese contexts, connects speaking with gradual improvement without “AI”, “Voice” or “Tutor”. Before public release the owner should run a trademark search and check domain/handle availability; nothing was registered.

Sources: [Sotto listings](https://www.stork.ai/en/sotto), [utter on the App Store](https://apps.apple.com/app/id6753176013), [Sayso releases](https://github.com/gearwithai/sayso/releases), [ParlaParla listing](https://marlvel.ai/api/llm/apps/productivity/parlaparla-ai-dictation), [Glossika app](https://apps.apple.com/us/app/glossika-language-learning/id1597902556?l=pt-BR).
