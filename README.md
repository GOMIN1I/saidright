<p align="center"><img src="assets/brand/app-icon-1024.png" width="128" alt="Saywell icon"></p>

<h1 align="center">Saywell</h1>

<p align="center"><b>Speak in any Mac app — the text appears where your cursor is.</b><br>
Local speech recognition, modes for how much to edit, and optional language tips that never get in the way.</p>

<p align="center"><a href="../../releases/latest">Download</a> · <a href="site/index.html">Product page</a> · <a href="README.ru.md">Русский</a></p>

> **Status: 0.5 developer preview.** Free and open source (Apache 2.0). Apple silicon, macOS 14 or later. Not notarized by Apple — see [Install](#install).

<p align="center"><img src="docs/screenshots/readme-main.jpg" width="420" alt="Saywell main window"> <img src="docs/screenshots/readme-recognition.jpg" width="420" alt="Recognition settings"></p>

## What it does

- **Dictation anywhere.** Tap right ⌘ (or ⌃⌥Space), speak, tap again. Hold-to-talk is available. Ordinary shortcuts such as ⌘C never start a recording; Esc cancels.
- **Honest delivery.** Text goes only into the field you were typing in. If focus moved, nothing is pasted and the text is on the clipboard, with the reason.
- **Local recognition.** Whisper large-v3-turbo (best for mixed languages and Chinese) or NVIDIA Parakeet TDT 0.6B v3 (≈0.1 s per phrase, 25 European languages), both through MLX on your Mac; Apple on-device dictation as a no-download option. *Automatic* picks Parakeet for one-language modes and Whisper for mixed speech — see [How recognition works](docs/RECOGNITION.md). Spoken numbers become digits.
- **Speak two languages at once.** A Russian + English mode keeps English terms in Latin script (“посмотри мой pull request”) and handles switches mid-dictation.
- **Modes.** Keep what you said, tidy punctuation, fix grammar, or rewrite in a tone — per mode, with a preview of what changes. Switch with ⌃⌥M.
- **Learn from your own sentences (optional).** After the text is inserted, a card can grow out of the capsule with the correction, a friendly explanation in your language, and an example on request. Correct text gets nothing. Save items for spaced practice. ⌃⌥L reopens the last tip.
- **Native feel.** Liquid Glass or Ink capsule, light/dark themes, settings with search, Reduce Motion and VoiceOver respected.
- **Private by default.** Audio never leaves the Mac. Editing and tips use a model you choose — free and local through [Ollama](https://ollama.com), or your own cloud key; *Local only* blocks every cloud request. No account, no telemetry.

## Requirements

| | |
| --- | --- |
| Mac | Apple silicon (M1 or later); 16 GB memory recommended for Whisper turbo plus a local text model (with less than 12 GB Saywell suggests Whisper small) |
| macOS | 14 or later (Liquid Glass and Apple on-device dictation need macOS 26) |
| Disk | about 3 GB for Whisper turbo and its runtime; Parakeet adds 2.5 GB; Whisper small needs 0.5 GB |
| Network | only to download a recognizer once (and for a cloud text service, if you choose one) |
| Permissions | Microphone; Input Monitoring for single-key shortcuts such as right ⌘; Accessibility to paste into other apps |

## Install

1. Download `Saywell.dmg` from [Releases](../../releases/latest) and drag Saywell to Applications.
2. Open it once. macOS says it can't verify the developer — click **Done**.
3. **System Settings → Privacy & Security** → scroll down → *“Saywell was blocked…”* → **Open Anyway**, and confirm. (Free builds are not notarized; notarization needs a paid Apple Developer membership.)
4. Follow the introduction: languages, a recognizer download inside the app (checksum-verified), and the three permissions.

To verify the download, put `Saywell.dmg.sha256` from the release next to the DMG and run `shasum -a 256 -c Saywell.dmg.sha256`.

## Use

| Action | Default |
| --- | --- |
| Start / stop dictation | right ⌘ tap · ⌃⌥Space |
| Cancel | Esc |
| Next mode | ⌃⌥M |
| Show / close last tip | ⌃⌥L |

Dictate into any text field. The capsule at the bottom of the screen shows recording, processing and done; the text is pasted where you were typing. Open Saywell from the Dock for history, practice cards and Settings.

## Configuration

Everything is in **Settings** (⌘,), with search:

- **Modes** — spoken languages, recognizer (*Automatic*, Whisper, Parakeet, Apple), how much the text is edited, learning tips, where the text goes.
- **Shortcuts** — the dictation key or combination, toggle or hold-to-talk, mode switching.
- **Recognition** — install or remove recognizers, personal vocabulary for Whisper.
- **Text & AI** — editing and tips through a local Ollama model or an OpenAI-compatible service; *Local only*.
- **Learning, Appearance, Privacy & Data, Advanced** — tip presentation, capsule look, history retention and export, automation links, diagnostics.

Data lives in `~/Library/Application Support/Saywell` (settings, modes, history, downloaded models). Keys are in the Keychain.

## Languages

| | |
| --- | --- |
| Interface | English, Русский, Deutsch, 简体中文 |
| Recognition, tested | Russian, English, German, Chinese (Whisper); Russian, English, German (Parakeet); mixed Russian + English |
| Recognition, supported by the models | about 100 languages with Whisper, 25 European languages with Parakeet; marked as less tested in the app |
| Language tips | tested for Russian and English learners; other languages experimental |

## Accuracy and speed

Measured on an M4 Pro. Real speech: 100 Google FLEURS clips; mixed and code-switched speech: synthetic clips ([eval/results](eval/results)).

| Recognizer | Per short phrase | Word errors RU / EN / DE (FLEURS) | Mixed RU+EN | English terms inside Russian |
| --- | --- | --- | --- | --- |
| Whisper large-v3-turbo | ≈0.5 s | 4.1 / 3.6 / 4.4 % | 3.1–3.4 % | kept in Latin script |
| Parakeet TDT 0.6B v3 | ≈0.1 s | 6.1 / 4.3 / 5.6 % | drops the other language | written phonetically |

Your voice and microphone will differ; synthetic clips check plumbing, not natural accents.

## Build from source

Requires Xcode 26 or later (Swift 6 toolchain).

```
scripts/check.sh                 # everything CI runs: tests, build, strings, scripts, secret scan
scripts/build-app.sh             # → build/Saywell.app
open build/Saywell.app
```

`SAYWELL_SIGN_IDENTITY=- SAYWELL_BUILD_DIR=build/public scripts/build-app.sh` makes an ad hoc signed build for sharing. Pull requests, releases and the product page are automated with GitHub Actions — see [docs/GITHUB.md](docs/GITHUB.md).

## Security and privacy

Audio is processed on the Mac; keys stay in the Keychain; downloads are checksum-verified; nothing is collected. Details and how to report a vulnerability: [SECURITY.md](SECURITY.md) and [docs/PRIVACY.md](docs/PRIVACY.md).

## Limitations

- Apple silicon only. Tested most on the newest macOS; 14–15 are expected to work but are less tested.
- Some apps (browsers, Electron) do not expose field contents, so insertion is reported as “pasted, not verifiable”.
- Secure Input (password fields, some terminals) hides keys from all apps; Saywell then copies instead of pasting.
- Pronunciation, accent and fluency are not assessed — a transcript can't support that.

## Documentation

[How recognition works](docs/RECOGNITION.md) · [Architecture](docs/ARCHITECTURE.md) · [Testing](docs/TESTING.md) · [Models & licences](docs/MODELS_AND_LICENSES.md) · [Privacy](docs/PRIVACY.md) · [Design](docs/DESIGN.md) · [GitHub workflow](docs/GITHUB.md) · [Release](docs/RELEASE.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md)

## Licence and credits

Saywell is licensed under the [Apache License 2.0](LICENSE); see [NOTICE](NOTICE). Speech models are downloaded on request and are not part of the app: OpenAI Whisper (MIT) and NVIDIA Parakeet TDT 0.6B v3 (CC BY 4.0, © NVIDIA). Built with [MLX](https://github.com/ml-explore/mlx), [mlx-whisper](https://github.com/ml-explore/mlx-examples) and [parakeet-mlx](https://github.com/senstella/parakeet-mlx). Saywell is not affiliated with Apple, OpenAI, NVIDIA or Google.
