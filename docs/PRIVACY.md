# Privacy and data

| Data | Where it goes | Control |
| --- | --- | --- |
| Microphone audio | Recorded only while the capsule is visible, into `~/Library/Application Support/Saywell/Recordings/` | Kept 7 days by default for replay/re-recognition; “Keep audio” off deletes each recording after processing |
| Recognition | Local Whisper process or Apple's on-device model. Audio never leaves the Mac | — |
| Transcript text | Sent to the chosen text service **only** when the active mode uses editing or automatic language help, or when you press an action that needs it | Per-mode levels; global **Local-only** blocks every non-localhost request in code (`TextProvider.makeRequest`) |
| History | `history.json` (text, edits, feedback, timings) | Keep/expire text independently of audio; export as Markdown/JSON; delete one or all |
| API keys | macOS Keychain, service `app.saywell.credentials`, one item per provider, `WhenUnlockedThisDeviceOnly` | Never written to files, logs, exports or prompts; a key is only sent to its own provider host |
| Logs | `Logs/saywell.log`: timings, outcomes, error codes | No transcripts, audio paths' content, prompts or keys |
| Downloads | Hugging Face (model), GitHub (uv), PyPI (packages) on explicit install | Checksums verified; nothing else is contacted |

No telemetry or analytics. Exports of modes contain no credentials or transcripts.

Retention runs at launch and after each dictation. Recordings from crashes or cancelled sessions that no record references are removed if older than a minute. Deletion only touches files named `<UUID>.wav` inside Saywell's own recordings folder.

The Govori 0.2 folder is read (library import, runtime/model in place) and never modified. The Govori Keychain item is read only when you press “Import” in Settings, which shows the macOS access prompt.

`saywell://` automation links are off by default because any app can open a link.
