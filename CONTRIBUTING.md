# Contributing

Thanks for helping. Please read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) first.

## Setup

- Xcode 26 or later (Swift 6 toolchain, macOS 26 SDK), Apple silicon Mac. The app runs on macOS 14+.
- `scripts/check.sh` — runs everything CI runs (tests, release build, strings, scripts, secret scan). Run it before every pull request; see [docs/GITHUB.md](docs/GITHUB.md) for the review flow.
- `scripts/build-app.sh` — builds `build/Saidright.app`. Use a stable signing identity (`SAIDRIGHT_SIGN_IDENTITY`) or macOS will ask for permissions again after each build.
- `python3 scripts/check-localization.py` — every UI string must exist in en, ru, de and zh-Hans with matching format specifiers.

## Guidelines

- Logic that can be tested without AppKit/AVFoundation belongs in `Sources/SaidrightCore` with tests. UI and system services stay in `Sources/Saidright`.
- Every asynchronous result must be checked against the current session id (`SessionMachine.isCurrent`).
- Never log transcripts, prompts, audio or keys. Never add telemetry.
- New user-facing text: add a key to all four tables. If you cannot translate, open the PR as a draft and ask for translation; do not ship English placeholders in other tables.
- Do not claim capabilities in UI or docs that are not implemented and verified; update `docs/TESTING.md` when you verify something.
- Do not copy code from GPL-licensed projects.

## Translations

String tables live in `Resources/Localization/<lang>.lproj/Localizable.strings`. To add a language: copy `en.lproj`, translate every key, add the case to `UILanguage`, add the directory to `CFBundleLocalizations` in `Resources/Info.plist`, and run the checker. Only fully translated languages appear in the selector.

## Privacy of test data

Never commit real recordings or transcripts. `scripts/make-fixtures.sh` generates synthetic fixtures locally; generated audio is git-ignored.
