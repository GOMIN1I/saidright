# Architecture

```
┌──────────────────────── Saidright.app (SwiftUI + AppKit) ────────────────────────┐
│ UI: MainView · ResultView · FeedbackView · Settings window (sidebar + search)  │
│     Appearance · Onboarding · History · Practice                               │
│     Capsule (NSPanel + CapsuleModel): recording → processing → delivered →     │
│     optional learning card/marker; non-activating, interactive only for tips   │
│                                                                                │
│ AppModel (@Observable, MainActor) — orchestrates one session at a time        │
│   ├─ HotkeyService   CGEventTap (bare modifier) + Carbon (dictation, mode, tip)│
│   ├─ Permissions     mic / input monitoring / accessibility, polled           │
│   ├─ AudioRecorder   AVAudioEngine → 16 kHz mono WAV, level, voiced time      │
│   ├─ WhisperEngine ×2 resident Python workers (Whisper, Parakeet), JSON lines ┼──► Resources/recognizer.py
│   │                  separate environments: Runtime/ and Runtime-Parakeet/    │     (MLX Whisper | parakeet-mlx)
│   ├─ AppleDictation  SpeechAnalyzer + DictationTranscriber (macOS 26+)        │
│   ├─ TextDelivery    focused-field capture, paste, AX verification            │
│   ├─ RuntimeInstaller pinned uv + hashed locks + model download/verify        │
│   ├─ OllamaService   local text models (detect, list, pull with progress)     │
│   └─ SpeechService   AVSpeechSynthesizer per language; Sound cues             │
│                                                                                │
│ SaidrightCore (platform-neutral, unit tested)                                    │
│   Modes (RecognizerChoice incl. auto) · SessionMachine · ModifierDetector     │
│   EditorPrompt · IntegrityReport · TextProvider (OpenAI / compatible)          │
│   TutorPrompt · FeedbackValidator · CapsuleHints · ReviewScheduler · TextDiff │
│   ModelCatalog · NumberNormalizer · SearchMatcher                              │
│   HistoryStore · RetentionPolicy · LegacyImport · AppSettings · Localizer     │
└────────────────────────────────────────────────────────────────────────────────┘
```

## Session lifecycle

`SessionMachine` (Core) owns the only mutable session state:

```
starting → recording → transcribing → [editing] → delivering → finished(outcome)
               │             │             │
               ├─ noSpeech   ├─ noSpeech   └─ (editor failure keeps raw text)
any non-terminal → cancelled | failed
```

- Every session has a UUID and an immutable `SessionSnapshot` (mode copy, trigger, destination). Editing a mode during a session affects only the next one.
- Every asynchronous step checks `machine.isCurrent(id)` before writing state. A late recogniser reply after cancel + restart is rejected (`SessionTests.staleResultAfterCancelAndRestartIsRejected`). Worker replies carry request ids; replies nobody waits for are dropped in `WhisperEngine.received`.
- Switching modes is disabled while busy and the UI says the change applies next time.

## Hotkeys

`ModifierDetector` (Core, pure, tested) consumes `flagsChanged`, `keyDown` and `mouseDown` events:

- Device-dependent flag bits distinguish right from left Command/Option/Control/Shift.
- Toggle: a clean press-and-release under 0.6 s fires; any key, click or other modifier during the press makes it a shortcut (⌘C, ⌘-click, ⌥⌘…) and nothing fires.
- Hold: begins recording immediately so the first syllable is kept, but the capsule appears only after 220 ms; a chord or a press shorter than 250 ms discards the recording silently.
- Missed releases (permission dialogs, sleep, lock) are resynchronised from the next flag word; sleep/wake/lock/unlock reset state and re-enable the tap.

`HotkeyService` installs the tap whenever Input Monitoring becomes available (permissions are polled every 1.5 s), re-enables it after `tapDisabledByTimeout`, reports whether events actually arrive, and registers the Carbon combination (default ⌃⌥Space, no permission needed) as a fallback. Esc cancels while a session is active.

## Recognition

`recognizer.py` speaks a versioned JSON-lines protocol (`WorkerProtocol` in Core): `ping`, `prepare` (download with progress → SHA-256 verify → load → warm-up), `transcribe` (`languages`, optional vocabulary `prompt`).

- Energy VAD with adaptive noise floor and hysteresis; regions shorter than 1.2 s are merged (language ID needs context); regions over 28 s are split at the quietest frame.
- Language ID per region restricted to the mode's languages, except when the model is clearly confident in another language (otherwise Whisper translates). Consecutive regions of one language are joined before decoding.
- Temperature fallback (0, 0.2, 0.4) with compression/logprob thresholds; no-speech segments dropped; a short list of known silence hallucinations is dropped only for short low-voice regions.
- The app passes no environment secrets to the worker and uses `python -I`. Stderr is captured (no transcripts are ever written there) for diagnostics.
- Timeouts scale with audio length; on timeout the worker is restarted and the recording kept for retry.

## Editing and learning

`TextPipeline.edit` makes **no provider call when cleanup is off** (`EditingPipeline.cleanupOffMakesNoRequest`). Otherwise `EditorPrompt` builds level-specific instructions and wraps the transcript as `<dictation>` data with the closing tag neutralised. `IntegrityReport` rejects edits that drop numbers or links, or grow/shrink beyond the level's bounds, and flags lost negations; rejected or failed edits fall back to the raw transcript with a visible reason.

Language feedback uses a strict JSON schema (`TutorPrompt.schema`). `FeedbackValidator` drops items whose quote is not in the transcript, unknown kinds, no-op suggestions and over-long lists; rebuilds a drifting “corrected” text from the accepted items; and never lets malformed output affect the delivered text. Only confirmed, undisputed, certain learner errors count toward personal topics.

`TextProvider` sends OpenAI requests only to api.openai.com with the OpenAI key; a compatible server has its own Keychain slot. `localOnly` blocks every non-localhost request in one place. No automatic retries (no duplicate paid requests).

## Delivery

At session start `TextDelivery` captures the frontmost app and its focused AX element (and whether it is a secure field). After processing it pastes only if the same app and field still have focus; otherwise it copies and says why. After ⌘V it reads the field's AX value to confirm insertion where the app exposes it, reports “pasted, not verifiable” where it does not, and restores the previous clipboard only if nothing else changed it. Clipboard items are marked transient for clipboard managers.

## Persistence

`~/Library/Application Support/Saidright/` (0700): `settings.json`, `modes.json`, `history.json` (all versioned, atomic writes, 0600), `Recordings/` (UUID.wav only; deletion refuses any other name), `Logs/` (no transcripts or keys), `Runtime/`, `Models/`, `Cache/`. Unreadable files are copied aside before defaults are used. The Govori 0.2 library is imported once, read-only, with recordings copied; the Govori runtime and model are used in place.

## Why these boundaries

- Core has no AppKit/AVFoundation so the risky logic (session races, hotkey heuristics, prompt boundaries, validation, retention) is unit-tested with `swift test`.
- The capsule has its own observable model so 30 Hz level updates do not invalidate the main window.
- The recogniser stays out of process: a crash or memory spike in Python cannot take the app down, and it can be restarted.
