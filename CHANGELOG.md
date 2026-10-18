# Changelog

## 1.0.0 — 2026-10-18

- **Main window without an empty band.** The mode switcher and settings button share the title bar's row with the close, minimise and zoom buttons, which are visible again in every window.

- **Tables by voice.** Say “I need a table with three columns: ChatGPT, Claude and Gemini” and dictate the values: smart formatting returns a Markdown table. The words of the request are left out, a greeting before it is kept, and every cell must come from what you said (RU/EN/DE/ZH requests).
- **A living app.** Saidright windows sit on a slowly drifting aurora — voice blue, violet and rose (#FF5257) over deep indigo at night, over airy mist by day — the product page's look. A ring of the same lights turns around the record button and brightens while you speak; the capsule breathes with a soft moving light. Prominent buttons use the blue-violet gradient; Finish uses blue → rose. All motion runs in Core Animation (no extra CPU measured) and stops with Reduce Motion.
- **Saidright colours.** Windows take on the icon's indigo by default — airy in light mode, deep at night — with a voice-blue accent. Settings → Appearance → Window colour switches back to plain macOS greys.
- **Introduction first.** On first launch only the introduction opens, centred, with an indigo hero, a fade-in and sliding steps; finishing it dissolves into the main window.
- **Faster long dictations.** Whisper recognises finished phrases while you are still speaking, so after the stop only the last part is left (16 real recordings: 3.1 s → 0.7 s on average). The connection to a cloud text service is opened while you speak (≈0.15 s).
- **Instant short phrases in light modes.** A short phrase that recognition already punctuated, with no fillers or repetitions, no longer waits for the cloud editor (it would return it unchanged): ≈1–2 s sooner and no request is sent.
- gpt-oss models on OpenAI-compatible servers (e.g. Groq) work with “Answer without thinking” (they get the lowest effort they accept). Measured: Groq `openai/gpt-oss-120b` edits ≈2.3× faster than gpt-6-luna and passed every faithfulness check.
- Tables dictated row by row (“в первой строке цена …”) are no longer rejected; tables with named fields (“имя и возраст”) get no empty first column. Thinking models on compatible servers get extra room so their answers are not cut off.
- **Faster tables and lists.** Smart formatting is requested together with the edit instead of after it, and used when it fits the edited text (Groq gpt-oss-120b, table requests: median 1.37 s → 0.92 s).
- Settings search: the search field no longer disappears when nothing matches (the window could get stuck); “Clear search” button and Esc.
- Long app names no longer stretch the main window's buttons.
- Product page redesigned: live capsule demo, interactive capsule playground, modes, voice tables, language practice, consistent dark screenshots in English and Russian.

## 0.6.0 — 2026-10-17

- **New name: Saidright** (previously Saywell, a name another dictation app already uses). The data folder moves to `~/Library/Application Support/Saidright` on first launch, saved keys are carried over from the Keychain, exported mode files from Saywell still import. macOS asks for Microphone, Input Monitoring and Accessibility once more because the app identity changed.
- **Smart formatting** (on by default in modes that edit text): tasks become a checklist, several things a list, steps a numbered list, separate topics get headings, repeated attributes a table — written as Markdown. Ordinary sentences stay prose. The layout is checked against what you said: nothing may be added, dropped or repeated, otherwise the plain edit is kept.
- Practice window: the empty state is centred.
- Product page: the capsule's done check mark is centred; no empty band beside the learning cards.

## 0.5.0 — 2026-10-17 (developer preview, first public release)

- Faster Whisper: language ID, decoding and the timestamp passes share one encoder pass (same transcripts; a short mixed-language phrase ≈0.95 s → ≈0.5 s).
- Settings read like a finished product: maintainer notes removed or rewritten as short user-facing text in all four languages.
- How recognition and *Automatic* work, with a measured comparison of language-gated routing (docs/RECOGNITION.md, scripts/eval-routing.py).
- GitHub automation: CI with a review tier, CodeQL, optional Claude code and security review, Dependabot, pre-release → promote → rollback releases (docs/GITHUB.md); `scripts/check.sh` runs the same checks locally.
- README and product page lead with language practice; requirements, configuration, languages and security sections; social preview image; SECURITY.md with private reporting.

- Recognition engine “Automatic” (default for new modes): Parakeet for one-language modes when installed, Whisper for mixed languages and Chinese.
- Parakeet output gets digits: Russian and English cardinals, Russian dates (“15 марта”), times (“14 часов 30 минут”), rooms (“204”); idioms and small single numbers stay words.
- Quiet voices are no longer dropped: VAD thresholds follow the recording's noise floor (quiet English 26.8 % → 3.6 % WER), still no text on noise or silence.
- Mixed RU/EN without pauses: Whisper recovers speech it skipped in the other language (25 % → 3.1 % WER on the mixed set), with guards against hallucinated subtitle credits.
- Acknowledgements and licences in Settings → Advanced (NVIDIA CC BY 4.0 attribution and others).

- NVIDIA Parakeet TDT 0.6B v3 as a built-in fast local engine, chosen per mode (≈6–10× faster than Whisper turbo here, close accuracy for one language per recording; Whisper stays the default for mixed RU/EN and Chinese). Own hashed runtime, in-app install, “use in one-language modes”.
- Learning card: emerges from the capsule (body first, then text), details fade in without overlapping, folds back into the capsule when closed, panel fits the card, hover tracked at AppKit level.
- `scripts/compare-asr.py` and an objective comparison report.

## 0.4.0 — 2026-10-16 (developer preview)

- The capsule teaches: after the text is inserted, a learning card can grow out of the capsule with the correction, a friendly explanation, details and an example on request, paging, “practise later”, “got it” and “mine was right/misheard”. Or a subtle marker, or window only. Correct text gets nothing.
- Friendlier explanations pitched to a self-chosen level; explanations always in the chosen language (translated in a second step if a small local model answers in the wrong one).
- Settings is a real window with a full-height sidebar and search that reveals and highlights the setting; new Appearance section (theme, Liquid Glass/Ink, palettes, size, motion, sounds, Dock icon).
- First run asks for interface, spoken and learning languages separately; resumable; no Govori wording.
- Real model choices: Whisper large-v3-turbo or small (pinned, checksum-verified), Apple on-device, and a free local text model through Ollama with in-app download.
- New mark: a capsule whose rising voice ends in a text cursor.

## Earlier unreleased changes

- Record button redesigned as the capsule in a Liquid Glass bezel; glass header.
- Fixed ~10 % idle CPU caused by a status-dot animation that never stopped.
- Recogniser re-warms automatically after an unexpected exit (crash-loop guard).
- Feedback: script guard rejects translations offered as corrections; long quotes narrowed to the change; clearer kind definitions.
- Editor: explicit Do/Do-not lists per level; digits stay digits.
- Compatible servers get `reasoning_effort: none` (configurable) so thinking models answer within budget.
- ⌘-scroll no longer counts as a single ⌘ tap.
- Dictation started from Saidright's window offers “Insert into <previous app>”.
- Restored introduction window closes itself unless requested.

## 0.3.0 — 2026-10-16 (developer preview, renamed from Govori)

Rebuilt from the Govori 0.2 prototype. See docs/AUDIT.md for what was kept and replaced.

- Dictation core: explicit session state machine with ids; stale results can no longer affect a new session. Escape cancels.
- Hotkeys: right ⌘ (or right ⌥/⌃/⇧) through a listen-only event tap that installs as soon as Input Monitoring is granted; ⌘C, ⌘-click and other shortcuts never start dictation; hold-to-talk discards chords silently; ⌃⌥Space fallback; key test that proves events arrive.
- Capture: AVAudioEngine with device selection, level test, device-change handling, honest "no speech detected".
- Recognition: request-id worker protocol, adaptive VAD, language detection restricted to the mode's languages without forced translation, temperature fallback, vocabulary hints, no hallucinated text on noise in the evaluation set; 530 MB smaller runtime (no torch); in-app installer with checksums; Govori installation reused in place; Apple on-device dictation engine for one-language modes.
- Delivery: only into the field focused at start; Accessibility verification; clear copy fallback with reasons; clipboard restored.
- Modes: persisted, editable, duplicable, exportable; four editing levels with examples and integrity checks; independent learning settings; output insert/copy/keep; quick switching (⌃⌥M).
- Language help: strict JSON schema, validation against the transcript, recognition-error vs learner-error distinction, verdicts, practice exercise, TTS by language, self-rated spaced review, honest progress with a denominator.
- Interface in English, Russian, German and Simplified Chinese; settings in nine sections; onboarding; history with search, export and audio import.
- New compact capsule (78×34 pt) with entrance/exit motion, state glyphs, Reduce Motion/Transparency/Increase Contrast support.
- Privacy: independent text/audio retention, Local-only switch enforced in code, Keychain per provider, no telemetry.
