# Roadmap

Ordered by value to everyday use. Items move only when verified. Status as of 0.6.0 (2026-10-17).

## Next (needs a person or an account)
- Upload the social preview image (Settings → General → Social preview) and enable the `main` ruleset (docs/GITHUB.md).
- Clean-install check on a separate macOS user (the isolated-folder install already passes).
- Natural-speech evaluation with consented recordings (owner + volunteers), AirPods/Bluetooth, noisy rooms; extend `scripts/compare-asr.py` results with sample counts.
- Real VoiceOver pass over the capsule card and settings; multi-display and full-screen-app check.
- OpenAI editing/feedback with a real key; tune prompts on a small labelled set of learner sentences.
- macOS 14/15 smoke test (the package declares macOS 14).

## Next (engineering)
- Smart formatting: optional rich-text paste for apps that do not render Markdown (Notes, Mail, Pages), and measure it with the default cloud model.
- Parakeet vocabulary hints are not supported by the model; consider light post-processing for personal terms.
- Single English words inside Russian sentences are occasionally misheard (“Slack” → “слог”, “README” → “Redmi”); language-gated Parakeet makes this worse (measured), so improvements must stay inside Whisper (vocabulary hints, post-correction).
- Number normalisation beyond RU/EN/DE (ordinal numbers, times like “quarter past”).
- Streaming partial results in the capsule for long dictations.
- WhisperKit (Core ML) engine to remove the Python runtime; compare with MLX on the same set.
- Sparkle or GitHub-Releases update check.
- Run the GitHub workflows once and add the green checks to the ruleset (docs/GITHUB.md).

## Later
- Per-app automatic mode selection (opt-in).
- Undo the last insertion where the target app supports it.
- Practice session that groups confirmed recurring topics, with adjustable frequency and no streak pressure.
- Traditional Chinese, Spanish, French UI (only with complete, reviewed translations).
- Notarized DMG (needs a paid Apple Developer membership; intentionally skipped for the free release).

## Not planned
- Pronunciation/fluency/CEFR scores from transcripts.
- Accounts, cloud sync, social features.
