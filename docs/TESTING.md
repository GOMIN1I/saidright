# Verification status

Legend: **Verified** = observed working on the test Mac (M4 Pro, macOS 27.0) in this build. **Automated** = covered by `swift test`. **User check** = needs a person (physical key, real voice, judgement). **Not verified** = implemented but not yet exercised.

## Automated tests (`swift test`, 89 tests)

| Area | What is asserted |
| --- | --- |
| Hotkey detector | right vs left ⌘, ⌘C, ⌘-click, ⌘-scroll, adding ⌥, long press, missed release, hold begin/end/cancel, brief accidental press, reset on sleep |
| Session machine | normal flow, no second session while busy, late result after cancel + restart rejected, terminal states final, illegal transitions, mode snapshot isolation, timing boundaries |
| Editing pipeline | cleanup off → zero requests and provider never constructed; local-only blocks cloud but allows localhost; dictation sent as delimited data with closing tag neutralised; OpenAI key only to api.openai.com; plain HTTP to remote refused; dropped number → rejected; runaway expansion → rejected; 401/403/404/429-quota/429-rate/500/refusal/truncation/missing key classified; no automatic retries |
| Prompts | levels produce different instructions; extra instructions cannot replace rules |
| Feedback | strict schema shape; translations offered as “corrections” rejected by script (Cyrillic/Latin/Han…); long quotes narrowed to the changed span; fabricated quote, unknown kind, no-op dropped; empty list valid; hint keeps one; malformed JSON throws; practice without a real error dropped; drifting correction rebuilt |
| Statistics | only confirmed, certain, undisputed learner errors count, with a denominator |
| Storage | modes round-trip, duplicate/rename/delete, last mode protected, import never overwrites, export has no secret fields, preset reset, retention (audio vs text), only `UUID.wav` deletable, lenient settings decoding, Govori library import |
| Misc | word/character diff incl. Chinese and punctuation, worker line buffering and decoding, timeout scaling, UI language resolution |

`python3 scripts/check-localization.py`: 516 keys × en/ru/de/zh-Hans, no missing keys, no format-specifier mismatches.

## End-to-end on the real app

Triggered with opt-in `saidright://` links (same code path as the hotkey: `handleHotkey(.toggle)`), audio from a synthetic file via `SAIDRIGHT_TEST_AUDIO`, delivery into TextEdit, result read back from TextEdit.

| Scenario | Result | Status |
| --- | --- | --- |
| Russian names/numbers → TextEdit, cleanup off | Inserted, `insertedVerified`; text ready 0.96 s after end of recording, inserted 1.22 s | Verified |
| Focus moved to Finder before processing finished | Nothing pasted; `copied:focusChanged`; TextEdit unchanged | Verified |
| Stop → cancel during recognition → new session | Only the new text inserted, once | Verified |
| No Accessibility permission | `copied:noPostPermission`, text on clipboard | Verified (before permission was granted) |
| Light editing without an API key | Raw transcript delivered, no request, persistent hint in the main window | Verified |
| Capsule recording (blue) → processing (pink) → done | Shown bottom-centre, compact | Verified visually |
| Russian UI, AppKit menus in Russian after relaunch | Correct | Verified |
| Onboarding steps 1–4 in Russian | Correct; Govori recogniser detected in place | Verified |
| Real microphone (AirPods input at night, silent room) | 2.9 s and 7.1 s captured, peak −65/−62 dB, reported “no speech”, nothing inserted, nothing sent to the recogniser | Verified |
| Recogniser process killed with SIGKILL | Next dictation restarted it cold (1.9 s) and inserted; with idle app the worker is re-warmed automatically 1 s after the crash; crash loop limited to 2 restarts / 5 min | Verified |
| Prompt mode with editing through a local OpenAI-compatible server (Ollama, gemma4:e2b) | “I go … buy” → “I went … bought” inserted and verified; comparison view shows struck/underlined changes | Verified |
| Language help (hint) in the main window, “Save for review”, Practice card, self-grading | Item shown with kind, rule, example, verdict buttons; card created, graded, rescheduled | Verified |
| History window: list, search field, detail with comparison, timings, feedback | Correct | Verified |
| Dictation started with the record button in Saidright → “Insert into TextEdit” | TextEdit activated, text pasted | Verified |
| Audio import conversion (AAC 44.1 kHz stereo → 16 kHz mono WAV) + recognition | Correct text, 0.95 s | Verified (conversion function run standalone; the file-picker/drag UI not exercised) |
| Apple dictation engine (DictationTranscriber, en_US asset) | English correct in 0.14–0.6 s; mixed RU/EN produced nonsense (“Yes, deal no vehicle…”) — confirms it must only be used for one-language modes | Verified (API path run standalone) |
| UI in Russian, German, Simplified Chinese; light and dark appearance | Main window, settings sections, onboarding, capsule preview, history, practice inspected | Verified visually |
| Idle CPU / memory | App idle 0.1 % CPU, ~47 MB; recording with capsule 4.5 % CPU; recogniser worker ~1.8 GB RSS with the model loaded | Measured |
| **Physical right ⌘ tap in another app** | — | **User check** |
| **Real voice (speaking), built-in mic and AirPods** | — | **User check** |
| Hold-to-talk with real key, ⌘C while dictation key held | Logic unit-tested only | User check |
| OpenAI editing/feedback with a real key | Not run (no key; the brief forbids asking for it in chat). The same request builder is unit-tested; the compatible path was run against Ollama | Not verified |
| In-app runtime installer on a clean account | Code path written; not run because a runtime exists here and a clean account needs the owner | Not verified |
| Sleep/wake, lock/unlock, device unplug mid-recording | Handlers implemented | Not verified |
| VoiceOver full pass, keyboard-only navigation, Increase Contrast | Accessibility labels confirmed in the AX tree (buttons, colours, verdicts); announcements implemented | Partly verified |

## 2026-10-16 product iteration (capsule learning, settings, models, identity)

Evidence from this session on the same Mac. Screenshots were produced by the app itself (`SAIDRIGHT_QA_OPEN` + `SAIDRIGHT_QA_SNAPSHOT`, which render Saidright's own windows with `cacheDisplay`; no screen-recording permission is involved). That renderer **does not draw Liquid Glass**, so glass surfaces appear without their material; the Ink style and layout are shown faithfully. Glass was not visually verified in this session.

| Scenario | Result | Status |
| --- | --- | --- |
| `swift test` | 109 tests in 23 suites pass (new: settings search matching incl. ё/diacritics/Chinese, capsule hint selection, explanation language detection, wrong-language details dropped, details field optional for stored records, legacy capsule colours → custom palette, model recommendation, pinned model metadata) | Automated |
| `scripts/check-localization.py` | 694 keys × en/ru/de/zh-Hans, 0 problems (synonym keys for search included) | Automated |
| Live dictation, physical right ⌘, mode switching | Reported working very well by the owner before this session; code paths for hotkeys, capture and delivery were not changed | **Owner-reported** |
| Hotkey-style session (`SAIDRIGHT_QA_OPEN=dictate:3`, synthetic `en-learner-errors.wav`) into TextEdit, isolated data dir, local gemma4:e2b in memory | Inserted 0.70 s after recording ended (`insertedVerified`; in two later runs `insertedUnverified` at 1.5–1.9 s while several TextEdit documents were open — text present each time, delivery code unchanged); feedback stored; the capsule then opened the learning card, two items with paging, Russian explanations (`capsule-hint-live-ru.jpg`) | Verified |
| New recording while a hint card is visible (`dictate:3@22`) | Card replaced by the recording capsule immediately (`capsule-new-recording-replaces-hint.jpg`) | Verified |
| Card expanded (details, example, “mine was right”), RU and DE; long German strings fit | `capsule-hint-expanded-ru.jpg`, `capsule-hint-expanded-de.jpg` | Verified visually (Ink) |
| Settings window: sidebar toggle gone, no extra top band, full-height sidebar with search; RU/ZH, light/dark | `settings-search-reveal-ru.jpg`, `settings-learning-dark-ru.jpg`, `settings-appearance-zh.jpg` | Verified visually |
| Search “материал” → result → section opens, scrolls and tints the row | `settings-search-reveal-ru.jpg` | Verified |
| Onboarding with an empty data dir and no Govori (`SAIDRIGHT_DATA_DIR`, `SAIDRIGHT_LEGACY_DIR`) | First run opens; recognizer step offers the download with size, free space and network note; nothing downloaded (data dir 16 KB) | Verified (isolated seam, not a clean macOS account) |
| Onboarding on this Mac (shared Govori recognizer) | Described as “already on this Mac … belongs to another app”; no Govori name | Verified visually |
| Recognition models list (turbo in use, small downloadable, Apple per mode); Ollama detected with installed models | `settings-models-ru.jpg`, `settings-local-text-models-dark-ru.jpg` | Verified visually; downloads not started |
| Local-model tests (`SAIDRIGHT_LOCAL_LLM_MODEL=gemma4:e2b swift test --filter LocalModel`, 8 tests) | 2 of 3 consecutive runs fully green, one run had one failure: an occasional false positive on correct text or empty details from the 2B model. Russian explanations now arrive via the translation fallback when the model answers in English | Partly verified (model quality limit) |
| Icon at 1024/256/64/32/16 on light and dark, standard/light/graphite | `icon-variants.jpg` | Verified visually |

Not verified in this session: Liquid Glass rendering of the capsule and card on real wallpapers; hover persistence and clicking card buttons with a real pointer (the panel accepts first mouse and never becomes key, by design); whisper-small download and recognition quality; an Ollama pull; the Dock icon switch; VoiceOver reading the card; Reduce Motion/Transparency toggled at system level; multiple displays and full-screen apps; a clean macOS user account.

## 2026-10-16 Parakeet integration and card motion

| Scenario | Result | Status |
| --- | --- | --- |
| Objective comparison, 100 FLEURS real-speech clips + 21 synthetic (`eval/results/2026-10-16-parakeet-vs-whisper.md`) | Parakeet ≈6–10× faster than Whisper turbo (0.07–0.14 s vs 0.71–0.78 s per clip), ≈1.1 vs 1.8 GB; single-language WER close to turbo (RU 5.7/4.3, EN 4.6/3.7, DE 4.6/4.2 %), much better than Whisper small; drops or transliterates English inside Russian recordings; numbers as words; no Chinese | Measured |
| Parakeet runtime installed through the app's installer (`SAIDRIGHT_QA_OPEN=install-parakeet`): uv + Python 3.11 + hashed lock into `Runtime-Parakeet`, model already present and checksum-verified | Done in 22 s; Whisper runtime unchanged | Verified |
| Hotkey-style session with a Parakeet mode (RU, isolated data dir) into TextEdit | `insertedVerified`; recognition 0.24 s for 7.6 s of audio; text ready 0.29 s, inserted 0.50 s after recording ended | Verified |
| Learning card motion, captured every 40 ms (`SAIDRIGHT_QA_FRAMES`) | Tip capsule lands → empty body stretches → text fades in (no clipped or overlapping text); details fade in under the explanation while the card grows; button label swaps in place; closing fades text, shrinks the body back into a capsule, then fades. Panel height follows the card | Verified (Ink; frames rendered by the app) |
| Pointer hover keeps the card | AppKit tracking area on the non-key panel (SwiftUI hover does not run there) | Implemented; not exercised with a real pointer |
| `swift test` | 111 tests | Automated |

Found during the comparison, not fixed yet: the shared energy VAD rejects very quiet input (below ≈ −55 dBFS; FLEURS English) for every engine; Whisper's per-region language ID can merge two languages spoken without a pause and drop one.

## 0.5.0 recognition fixes

| Scenario | Result | Status |
| --- | --- | --- |
| Final comparison on 129 clips (FLEURS at original levels, synthetic, mixed, noise) | Whisper turbo: RU 4.1 %, EN 3.6 % (was 26.8 % on quiet audio), mixed 3.1 % (was 25 %), DE 4.4 %, ZH CER 4.9 %, 0/10 text on noise, 0.71 s; Parakeet: RU 6.1 %, EN 4.3 %, DE 5.6 %, 0.10 s, 0.8–1.1 GB | Measured (`eval/results/2026-10-16-parakeet-vs-whisper.md`) |
| “Automatic” mode, English only, `en-negation-numbers` → TextEdit | Parakeet used; “…three servers for 2500 users.” `insertedVerified`, 0.60 s after recording ended | Verified |
| “Automatic” mode, Russian only, `ru-names-numbers` → TextEdit | “…на 15 марта в 14 часов 30 минут. Кабинет 204.” `insertedVerified`, 0.52 s | Verified |
| `swift test` | 118 tests (new: number normaliser RU/EN incl. idioms and ordinals, Auto resolution) | Automated |
| Localization | 713 keys × 4 languages, 0 problems | Automated |

## 2026-10-17 Saidright 0.6.0 (rename, smart formatting, fixes)

| Scenario | Result | Status |
| --- | --- | --- |
| Rename Saywell → Saidright | Targets, modules, sources, strings (4 languages), env seams (`SAIDRIGHT_*`), URL scheme `saidright://`, bundle id `io.github.gomin1i.saidright`, scripts, workflows, site, README, docs. Old name kept only where compatibility needs it: Keychain service `app.saywell.credentials` (copied on first read), data folder `Saywell` (moved), `saywell.modes` export files (still import), rename notes | Source + automated |
| Data folder move on an APFS copy of the real folder (`SAIDRIGHT_PREVIOUS_DATA_DIR`) | Folder renamed; Parakeet venv `bin/python` link and `pyvenv.cfg` pointed at the new path; a Parakeet dictation afterwards: “I don't think we need more than three servers for 2500 users.” | Verified |
| `swift test` | 137 tests in 25 suites pass (new: smart formatting heuristics, rendering, invented/dropped/repeated content rejected, mixed-field repair, title script check, old rules and old export files decode) | Automated |
| Smart formatting with local models (`SAIDRIGHT_LOCAL_LLM_MODEL`, 3 runs each) | gemma4:e4b: tasks → checklist, “bring the numbers, the slides and the budget” → intro + bullets, an ordinary sentence stays prose — 9/9. gemma4:e2b: mostly correct; its malformed layouts (dropped or repeated text) are rejected and the plain edit is delivered | Measured |
| Product page | Capsule check mark centred (tick centre = capsule centre); learning cards and tip panel have equal height at 1440 px, stack without gaps at 800 and 375 px; no horizontal scroll; no console errors | Verified in browser |
| Practice window empty state | Centred horizontally and vertically (`practice-empty.jpg`) | Verified visually |
| Screenshots | Main window, settings and social preview re-rendered with the new name | Verified visually |

## 2026-10-17 release preparation (production copy, routing, GitHub, audit)

| Scenario | Result | Status |
| --- | --- | --- |
| `scripts/check.sh` (tests, release build, strings, Python/shell syntax, pinned actions, secret and personal-path scan) | 120 tests in 24 suites pass; 711 keys × 4 languages, 0 problems; no compiler warnings; scan clean | Automated |
| Settings copy without developer notes | Notes written for the maintainer removed or rewritten as short user-facing text in en/ru/de/zh (capsule preview, palette, glow, microphone, dictation footers dropped; cost, icon, permissions, model and coverage texts rewritten; “tested here / not tested by this project” wording gone). Recognition settings rendered by the app itself (`readme-recognition.jpg`) | Verified visually (EN, light) |
| Legacy key import row | Shown only when an earlier Govori installation exists | Source |
| Engine routing for a ru+en mode: Whisper vs Parakeet vs language-gated Parakeet, 26 synthetic clips incl. English terms inside Russian sentences | Whisper 4.0 % WER, 0.48 s; Parakeet 17.0 %, 0.07 s; gated 14.8 %, 0.42 s. Gating sends “pull request” to Parakeet, which writes “пул реквест”. Gating not adopted | Measured (`eval/results/2026-10-17-routing.md`, `docs/RECOGNITION.md`) |
| Whisper encoder cache (language ID, decoding, fallback and timestamp passes share one encoder pass) | Same transcripts on 26/26 clips; mean latency 0.95 → 0.47 s, median 0.80 → 0.42 s through the worker | Measured |
| Same change in the real app (isolated data dir, `SAIDRIGHT_LEGACY_DIR` with only runtime and models, `dictate:4`, ru+en mode, cleanup off) | “Я проверил логи. And the deploy failed again.” in 0.50 s; “Посмотри мой pull request, там всего 3 файла.” in 0.48 s (recognition time from history) | Verified |
| Independent diff review (Claude Code `/code-review`, high) | 10 findings (unrun required CodeQL check, apt without update, scan skipped new files, tags keyed on test coverage, cache key without module, missing 16 kHz check, rollback wording, duplicated command list, duplicate CI build, dropped estimate caveat); all fixed | Verified |
| Security audit of the source | Keys only to their own host, HTTPS required for remote servers, Keychain `WhenUnlockedThisDeviceOnly`, 0600/0700 files, worker in `python -I` with a minimal environment, hash-locked runtimes and checksum-pinned uv, automation links off by default and no longer logged verbatim. `docs/AUDIT.md` (prototype audit with machine details) is excluded from the public branch | Source |
| GitHub workflows (CI, CodeQL, Claude review, Release, Promote, Pages, Dependabot) | YAML parses; actions pinned to commit SHAs; review-tier logic tested locally on sample file lists. Not run on GitHub yet | Not verified on GitHub |

QA note: an isolated `SAIDRIGHT_DATA_DIR` still imports the Govori library from `SAIDRIGHT_LEGACY_DIR` (default `~/Library/Application Support/Govori`). Point `SAIDRIGHT_LEGACY_DIR` at a folder that holds only `runtime` and `models` links when the test must not see personal history.

## Local-model integration tests

`SAIDRIGHT_LOCAL_LLM_MODEL=gemma4:e2b swift test --filter LocalModel` (skipped without the variable). Findings that changed the code:

- Light level returned text without punctuation → instructions rewritten as explicit “Do / Do not” lists; now punctuates and keeps words.
- Correct level spelled “15 30 … 204” as words and turned 204 into “two forty” → the integrity check rejected it (raw text delivered); instruction “keep digits as digits” added; now passes.
- Feedback labelled clear tense errors as “style” → kind definitions with an example added; now “grammar”.
- For a Russian-only sentence the model offered an English translation as a correction → deterministic script guard added in the validator.
- The 2B model still writes explanations in English when asked for Russian; the default cloud model is expected to follow it but this is **not verified**.

## ASR evaluation

`scripts/make-fixtures.sh` then `scripts/eval-asr.py` (see `eval/results/2026-10-16-m4pro-synthetic.md`). Synthetic voices only; it checks plumbing and regressions, not natural-speech accuracy.

Key findings (15 clips, warm):

- Mean WER/CER over 13 speech clips: 0.031 (new) vs 0.037 (Govori 0.2 worker). Most residual “errors” are number formatting (“десять” → “10”).
- Silence and noise-only: both empty in the new worker; the Govori worker produced “Thank you.” on noise.
- Mixed RU/EN: new worker kept all three segments; Govori dropped “посмотри”.
- Govori split sentences mid-phrase on names/negation and took 2.5 s vs 0.9 s.
- An early version that strictly forced the mode's languages *translated* German and Chinese into English; fixed by accepting a clearly detected outside language. This is why the evaluation includes non-mode languages.
- Warm latency is dominated by a ~0.8 s fixed cost (30 s Whisper window), so short and 8 s clips take similar time. Cold start (load + warm-up) ≈ 2 s.

## Manual test script for a person

1. Open TextEdit, click into a document. Tap **right ⌘** once, say a Russian sentence, tap again → text appears; capsule blue → pink → ✓.
2. Same with English, then a mixed sentence.
3. Hold ⌘ and press C (copy) → no capsule, nothing recorded.
4. Tap right ⌘, then press Esc → capsule ×, nothing inserted.
5. Tap right ⌘, switch to another app while speaking, tap again → text copied, message says focus moved.
6. ⌃⌥M → capsule shows the next mode's name.
7. Settings → Shortcuts → Hold to talk; hold right ⌘ while speaking; release → inserted. Hold right ⌘ and press C → nothing.
8. Disconnect AirPods while recording → recording finishes with a notice.
