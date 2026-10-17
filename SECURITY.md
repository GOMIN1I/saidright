# Security

## Reporting a vulnerability

Please use **Security → Report a vulnerability** on the GitHub repository (private vulnerability reporting). Do not open a public issue for security problems. You will get an answer within a week; fixes are released as a new version and noted in the changelog.

Supported versions: the latest release only.

## How Saidright protects you

- **Audio stays on the Mac.** Recognition runs locally (Whisper, Parakeet or Apple's on-device model). Recordings are deleted after processing unless you turn on keeping audio in Settings → Privacy.
- **Keys.** API keys are stored in the macOS Keychain (`app.saidright.credentials`, accessible only when the Mac is unlocked, never synced) and sent only to the host of the provider they belong to. Remote servers must use HTTPS; *Local only* blocks every cloud request.
- **No telemetry, no account.** Logs contain no transcripts, prompts, audio or keys.
- **Prompt injection.** Dictated text is sent to a text model as delimited data with instructions not to follow it, and responses are checked against the level's integrity rules before anything is inserted. A dictation that makes the editor do something else is a security bug — please report it.
- **Keyboard access.** The event tap is listen-only and looks only for the dictation key and modifiers; it never records what you type. Password fields (Secure Input) are respected.
- **Automation links.** `saidright://` links are off by default because any app can open them.
- **Downloads.** Models are pinned to a repository revision and verified against their published SHA-256 after download. The speech runtime is installed from hash-locked requirement files (`--require-hashes`) by a checksum-pinned `uv`. The recognizer runs as a separate Python process in isolated mode (`python -I`) with a minimal environment and no secrets.
- **Builds.** Release DMGs are built from the tagged source on GitHub Actions and published with their SHA-256 checksum. Builds are signed ad hoc and not notarized (notarization requires a paid Apple membership); macOS asks you to confirm the first launch.

## For contributors

Every pull request runs tests, CodeQL and a secret scan; changes to hotkeys, recording, text delivery, keys, the recognizer worker, runtimes, signing or workflows are tested by a person on a Mac before merging. See [docs/GITHUB.md](docs/GITHUB.md).
