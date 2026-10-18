# Models, runtime, licences and platform support

## Hardware and OS matrix

| | Apple silicon, macOS 14–15 | Apple silicon, macOS 26+ | Intel Mac |
| --- | --- | --- | --- |
| App | Builds for macOS 14 (not yet run on 14/15) | **Tested on macOS 27, M4 Pro** | Not built or supported |
| Whisper (MLX) | Expected (MLX wheels exist for macOS 14+) | **Tested** | Not supported (MLX is Apple silicon only) |
| Apple dictation engine | Not available | Available (54 locales seen on test Mac) | — |

The release build is arm64 only. Do not advertise Intel support.

## Components

| Component | Version | Licence | How it reaches the user |
| --- | --- | --- | --- |
| Saidright source | 0.5.0 | **Apache-2.0** (`LICENSE`, `NOTICE`) | GitHub |
| OpenAI Whisper large-v3-turbo weights | MLX conversion `mlx-community/whisper-large-v3-turbo` @ `a4aaeec0` | MIT (Whisper); conversion published under the same terms on Hugging Face | Downloaded by the app from Hugging Face on request, SHA-256 checked against the repository metadata; not bundled |
| mlx-whisper | 0.4.3 | MIT | Installed from PyPI via the hashed lock |
| MLX | 0.32.4 | MIT | PyPI |
| numpy, scipy, numba, llvmlite, tiktoken, huggingface_hub, soundfile, tqdm, … | see `Runtime/requirements.lock` | BSD/MIT/Apache-2.0 (verify per package before redistribution) | PyPI, `--require-hashes` |
| libsndfile (inside the soundfile wheel) | — | LGPL-2.1 | PyPI wheel; dynamically loaded by Python |
| uv | 0.11.14 | MIT / Apache-2.0 | Downloaded from GitHub releases, SHA-256 pinned in `RuntimeInstaller` |
| Python | 3.11 (python-build-standalone via uv) | PSF | Downloaded by uv |
| Apple Speech, AVFoundation | system | Apple SDK terms | Part of macOS |
| macOS voices (TTS, test fixtures) | system | Apple licence | Not redistributed; fixtures are generated locally and not committed |

Nothing third-party is presented as Saidright's own work; the recognition model is OpenAI Whisper.

`torch` is deliberately not installed: `mlx_whisper` only imports it for checkpoint conversion (`torch_whisper.py`). This saves ~530 MB compared with the Govori setup.

## Model options offered in the app (0.4)

Separate roles: **speech recognition** (always local) and **text editing / learning** (optional; local or cloud).

| Role | Option | Download | Memory (estimate) | Languages | Status |
| --- | --- | --- | --- | --- | --- |
| Speech | Whisper large-v3-turbo, `mlx-community/whisper-large-v3-turbo` @ `a4aaeec0` | 1.61 GB + 0.65 GB runtime | ≈2.2 GB | Whisper's 99 languages; mixed speech handled by the worker's per-region language ID | Tested here (RU/EN/DE/ZH synthetic set) |
| Speech | NVIDIA Parakeet TDT 0.6B v3, `mlx-community/parakeet-tdt-0.6b-v3` @ `ed2b7e8c` (CC-BY-4.0) via parakeet-mlx 0.5.3 (Apache-2.0) | 2.51 GB + 0.56 GB own runtime (`Runtime-Parakeet`, `Runtime/requirements-parakeet.lock`) | ≈1.1 GB measured | 25 European languages (official card), no Chinese; one language per recording | Tested here: FLEURS RU/EN/DE + synthetic, see eval/results/2026-10-16-parakeet-vs-whisper.md |
| Speech | Whisper small, `mlx-community/whisper-small-mlx` @ `45f39159` | 0.48 GB + runtime | ≈0.9 GB | same set, clearly lower accuracy outside English | Offered; **not tested here** |
| Speech | Apple on-device (SpeechAnalyzer/DictationTranscriber, macOS 26+) | system language pack | system | one locale per mode; mixed speech fails | Tested (English); per mode |
| Text | Ollama `gemma4:e2b` | 4.59 GB (registry manifest) | — | multilingual; small model, explanations sometimes need the translation fallback | Tested here |
| Text | Ollama `qwen3:4b` | 2.50 GB | — | multilingual | Offered; not tested |
| Text | Ollama `gemma4:e4b` | 6.58 GB | — | multilingual | Offered; not tested |
| Text | **Groq `openai/gpt-oss-120b` (default)** — Chat Completions, strict JSON schema, reasoning effort “low” | — | — | RU/EN/mixed: passed every faithfulness check; ≈0.4 s per short phrase | Tested with a real free key (`eval/results/2026-10-18-editing-speed.md`); free tier ≈1 000 requests and 200 000 tokens a day |
| Text | OpenAI `gpt-6-luna` (Responses API, strict JSON schema) | — | — | ≈1.0 s per short phrase | Tested with a real key |

Sizes were read on 2026-10-16 from the Hugging Face API (`/api/models/<repo>?blobs=true`, pinned revision) and the Ollama registry manifests (`registry.ollama.ai/v2/library/<name>/manifests/<tag>`). Whisper downloads are checked against each file's published SHA-256; Ollama verifies layer digests itself. Licences: Whisper weights MIT; Gemma models under the Gemma terms; Qwen3 per its model card — re-check before recommending in public material.

Parakeet is used by modes set to “Automatic” (the default for new modes) when it is installed and the mode has exactly one supported language, or when chosen explicitly per mode. Its English/Russian numbers are written as digits by `NumberNormalizer` (German not yet). It fits a mode with exactly one supported language; with several languages the editor warns that a switch inside one recording can be dropped or transliterated; unsupported languages (e.g. Chinese) are flagged. Its environment is separate from Whisper's, so installing or removing it never changes the Whisper runtime. CC-BY-4.0 requires attribution to NVIDIA in About/Acknowledgements before any public release.

Recommendation logic (`ModelCatalog.recommendedWhisper`): large-v3-turbo for anything other than English-only; small only for English-only on Macs with less than 12 GB memory.

### Evaluated, not offered yet

- Whisper large-v3 (3.1 GB): slower than turbo for little gain in dictation.
- Whisper base (0.14 GB): too inaccurate for Russian and mixed speech to recommend.

## Distribution approach

The app does not bundle Python or weights. On first run it offers a one-click install (~0.65 GB runtime + 1.6 GB model, disk space checked, cancellable, resumable by re-running, integrity-checked). If Govori 0.2 is present, its runtime and model are used in place (no duplicate gigabytes). Apple dictation needs no install beyond a system language asset.

Before a public release: produce an SBOM from the lock (`uv pip compile` output + licence fields), include licence texts in the app's About/Acknowledgements, and re-verify the Hugging Face repository licence card.

## Source licence recommendation

**Apache-2.0** for the app: permissive (portfolio-friendly, contributions easy), explicit patent grant, compatible with all dependencies above. MIT would also work. GPL-3.0 would be needed only to reuse code from GPL projects such as VoiceInk, which this project does not do. Chosen: Apache-2.0 (`LICENSE`, `NOTICE`), 2026-10-16.
