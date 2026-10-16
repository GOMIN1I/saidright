# Parakeet TDT 0.6B v3 vs Whisper — 2026-10-16

Apple M4 Pro, 24 GB, macOS 27.0. Each engine ran in its own worker process through `Resources/recognizer.py` (the app's own code path: shared energy VAD, hallucination filter; Whisper with per-region language ID restricted to RU+EN like the owner's modes, DE/ZH clips with their own language; Parakeet has no language parameter). One warm-up clip, then timed sequentially; the regular Saywell (Whisper loaded) was running at the same time. Reproduce with `scripts/compare-asr.py`.

Clips:
- **FLEURS dev** (google/fleurs, CC-BY-4.0, read speech by real speakers): first 25 utterances each for ru_ru, en_us, de_de, cmn_hans_cn, 4–27 s. FLEURS English is recorded very quietly (RMS ≈ −60 dBFS), so the main table uses copies peak-normalised to −3 dBFS; the raw table below shows what the current VAD does with the quiet originals.
- **Synthetic** (`eval/fixtures.json`, macOS voices): 15 clips incl. names/numbers, one RU/EN mix, silence, noise.
- **Extra mixed RU/EN** (6 synthetic clips, sentence-level switches with no pause, as `say` produces them).

Error rates: WER (CER for Chinese) after lower-casing, NFKC, ё→е, punctuation removed. Numbers are not normalised, so “15” vs “пятнадцатое” counts as errors.

## FLEURS (normalised) + synthetic

| Engine | load s | memory MB | ru WER | en WER | mixed WER | de WER | zh CER | text on silence/noise | mean latency s | RTF |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| whisper:whisper-turbo | 1.6 | 1799 | 4.3% | 3.7% | 0.0% | 4.2% | 4.9% | 0/2 | 0.71 | 0.073 |
| whisper:whisper-small | 1.0 | 878 | 10.6% | 5.0% | 0.0% | 11.0% | 20.7% | 0/2 | 0.23 | 0.023 |
| parakeet:parakeet-tdt-0.6b-v3 | 1.2 | 1136 | 5.7% | 4.6% | 30.8% | 4.6% | 129.3% | 0/2 | 0.11 | 0.011 |

## Extra mixed RU/EN clips

| Engine | load s | memory MB | en WER | mixed WER | mean latency s | RTF |
| --- | --- | --- | --- | --- | --- | --- |
| whisper:whisper-turbo | 1.5 | 1755 | 0.0% | 25.0% | 0.78 | 0.183 |
| parakeet:parakeet-tdt-0.6b-v3 | 1.2 | 1192 | 0.0% | 44.2% | 0.07 | 0.017 |

### whisper:whisper-turbo
| id | s | hypothesis |
| --- | --- | --- |
| mix-0 | 0.79 | Я проверил логи. And the deploy failed again. Так что откатываем. |
| mix-1 | 0.78 | Напиши клиенту. We will send the invoice tomorrow morning. |
| mix-2 | 0.75 | Там всего три файла. |
| mix-3 | 0.76 | Давай созвонимся после обеда. |
| mix-4 | 0.80 | Сегодня обновим зависимости. Then run the tests. И вечером выкатим релиз. |
| mix-5 | 0.78 | This sentence is fully in English and fairly long, to check that nothing is dropped. |
### parakeet:parakeet-tdt-0.6b-v3
| id | s | hypothesis |
| --- | --- | --- |
| mix-0 | 0.07 | Я проверил логи. Так что откатываем. |
| mix-1 | 0.07 | Напиши клиенту. Ви вил сенд и инвойс томоронин. |
| mix-2 | 0.07 | Can you review my pull request? Там всего три файла. |
| mix-3 | 0.07 | Давай созвонимся после обеда. |
| mix-4 | 0.08 | Сегодня обновим зависимости Тен ранэ тест и вечером выкатим релиз. |
| mix-5 | 0.07 | This sentence is fully in English and fairly long, to check that nothing is dropped. |

## FLEURS with original (quiet) levels

| Engine | load s | memory MB | ru WER | en WER | mixed WER | de WER | zh CER | text on silence/noise | mean latency s | RTF |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| whisper:whisper-turbo | 1.6 | 1804 | 4.5% | 26.8% | 0.0% | 4.4% | 4.9% | 0/2 | 0.71 | 1.338 |
| whisper:whisper-small | 1.2 | 726 | 11.5% | 28.6% | 0.0% | 11.4% | 24.2% | 0/2 | 0.22 | 0.417 |
| parakeet:parakeet-tdt-0.6b-v3 | 1.4 | 1132 | 5.9% | 28.4% | 30.8% | 5.6% | 139.5% | 0/2 | 0.11 | 0.208 |

The English column is high for every engine because the shared VAD drops clips quieter than about −55 dBFS before recognition. This is a pipeline finding, not a model difference.

## Reading

- **Speed**: Parakeet decodes a clip in 0.07–0.14 s warm vs 0.71–0.78 s for Whisper turbo through the same pipeline (≈6–10×; part of Whisper's time is our language-ID pass). Real-time factor ≈ 0.011 vs 0.073.
- **Memory**: ≈1.0–1.1 GB resident vs ≈1.8 GB for turbo; Whisper small ≈0.9 GB.
- **One language per recording**: Parakeet is close to turbo (RU 5.7 % vs 4.3 %, EN 4.6 % vs 3.7 %, DE 4.6 % vs 4.2 %) and far better than Whisper small (10.6 / 5.0 / 11.0 %).
- **Mixed RU/EN in one recording**: Parakeet drops the English part or writes it in Cyrillic (“Ви вил сенд и инвойс”). Whisper turbo also drops a sentence when two languages follow without a pause (a segmentation weakness of our pipeline), but less often.
- **Numbers**: Parakeet spells numbers as words in Russian and English (“пятнадцатое марта в четырнадцать часов”, “two thousand five hundred”); Whisper writes digits.
- **Chinese**: not supported by Parakeet v3.
- **Vocabulary hints**: Whisper uses personal terms as a prompt; Parakeet takes none.
- Silence and noise: no text from any engine.

## After the fixes (same day, original FLEURS levels, plus 8 noise/hum/click clips)

Changes measured here: VAD thresholds follow the recording's own noise floor (absolute minimum −70 dBFS instead of −55); with several expected languages, Whisper's segment (and, when the text is clearly too short, word) timestamps reveal voiced audio that produced no text, which is decoded again in the other language, with guards against quiet tails and known hallucination phrases.

| Engine | load s | memory MB | ru WER | en WER | mixed WER | de WER | zh CER | text on silence/noise | mean latency s | RTF |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| whisper:whisper-turbo | 1.5 | 1856 | 4.1% | 3.6% | 3.1% | 4.4% | 4.9% | 0/10 | 0.71 | 0.078 |
| parakeet:parakeet-tdt-0.6b-v3 | 1.4 | 795 | 6.1% | 4.3% | 41.5% | 5.6% | 131.8% | 0/10 | 0.10 | 0.011 |

- Quiet English (FLEURS originals): Whisper 26.8 % → **3.6 %** WER; Parakeet 28.4 % → **4.3 %**.
- Mixed RU/EN without pauses: Whisper 25 % → **3.1 %** WER (e.g. “Давай созвонимся после обеда. I need to finish the report first.” now complete). One English word was still misheard (“pull request” → “pool”).
- Noise, hum, clicks, silence: no text from either engine (0/10).
- Whisper mean latency unchanged (0.71 s); a recovery pass adds ≈0.4–1.5 s only on recordings where speech was actually missing.
- Parakeet figures here are before Saywell's number normalisation (applied in the app, `NumberNormalizer`), so its RU/EN rates include “пятнадцатое” vs “15” differences; in the app “two thousand five hundred” → “2500”, “пятнадцатое марта … двести четыре” → “15 марта … 204” (verified end to end).
- Parakeet still drops or transliterates the other language inside mixed recordings (41.5 %), which is why “Automatic” keeps Whisper for multi-language modes.
