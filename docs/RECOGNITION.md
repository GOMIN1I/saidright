# How recognition works

Saidright has three recognizers. Each mode chooses one, or *Automatic*. From the user's point of view a mode is "one recognizer that understands my languages"; this page explains what happens underneath and why it is built this way.

## The engines

| | Whisper large-v3-turbo | Parakeet TDT 0.6B v3 | Apple on-device |
| --- | --- | --- | --- |
| Languages | ~100, incl. Chinese | 25 European | one per mode |
| Mixed languages in one recording | yes (see below) | no: the other language is dropped or written phonetically | no |
| English terms inside another language (“pull request”, “GitHub”) | kept in Latin script | written phonetically in Cyrillic | — |
| Personal vocabulary hints | yes | no | no |
| Time per short phrase (M4 Pro) | ≈0.5 s | ≈0.1 s | not measured |
| Memory | ≈1.8 GB | ≈1.1 GB | system |

## Automatic

*Automatic* is decided per mode from the languages the mode lists, not per recording:

- the mode has **one** language that Parakeet supports and Parakeet is installed → **Parakeet**;
- otherwise (several languages, Chinese, detection left open, Parakeet missing) → **Whisper**.

So a Russian + English mode always uses Whisper; an English-only mode uses Parakeet. The mode settings show which engine *Automatic* uses right now.

## Inside the Whisper pipeline (mixed-language modes)

1. **Voice activity.** An energy detector that follows the recording's own noise floor finds voiced regions (quiet voices down to about −70 dBFS count; silence, hum and clicks do not). Short regions are merged so each one has enough context.
2. **Language per region.** Whisper's language identification runs on every region, restricted to the mode's languages (so short Russian phrases are not mistaken for Ukrainian). A language clearly outside the set is kept as spoken rather than forced, because forcing makes Whisper translate.
3. **Decoding.** Consecutive regions in the same language are decoded together, with the personal vocabulary as a prompt.
4. **Coverage check.** Whisper sometimes decodes a whole region in one language and silently skips a sentence in the other (a switch without a pause). Segment timestamps, and word timestamps when the text is clearly too short for the amount of voice, show voiced audio that produced no words; those spans are decoded again in the other language and put back in order.
5. **Filters.** Known hallucination phrases on near-silence are dropped; numbers become digits.

Steps 2–4 run the Whisper audio encoder on the same 30-second window several times. Since 0.5.0 the worker caches the encoder output by the exact window content, so language ID, decoding, the temperature fallback and the timestamp pass share one encoder pass. Output is bit-for-bit the same; a short mixed-language phrase now takes ≈0.5 s instead of ≈0.95 s (26/26 identical transcripts, [eval/results/2026-10-17-routing.md](../eval/results/2026-10-17-routing.md)).

## Why not use Parakeet for the one-language phrases of a mixed mode?

That is the obvious "universal" design: identify the language first, send one-language recordings to the 6× faster Parakeet, and keep Whisper for mixed ones. It was built and measured on 26 clips for a Russian + English mode ([eval/results/2026-10-17-routing.md](../eval/results/2026-10-17-routing.md)):

| Policy | RU | EN | RU with English terms | RU/EN switch | All | Time |
| --- | --- | --- | --- | --- | --- | --- |
| Whisper (what Saidright does) | 1.6 % | 1.6 % | 11.9 % | 3.4 % | **4.0 %** | 0.48 s |
| Parakeet for everything | 0.0 % | 0.0 % | 28.6 % | 44.8 % | 17.0 % | 0.07 s |
| Language ID → Parakeet when one language | 0.0 % | 0.0 % | 28.6 % | 36.2 % | 14.8 % | 0.42 s |

(word error rate, lower is better; the Whisper “errors” on pure RU/EN are mostly digits vs. spelled-out numbers in the reference.)

It loses for two reasons that cannot be tuned away:

- **Language ID cannot see an English word inside a Russian sentence.** It correctly says “Russian”, Parakeet then writes “пул реквест”, “фичер флэк”, “гитхаб”. Bilingual people speak exactly like this, so it is the common case, not an edge case.
- **The speed gain disappears.** Language ID is itself an encoder pass (≈0.35 s), the expensive part of Whisper. After it, finishing with Whisper costs only ≈0.13 s more, so routing saves ≈0.06 s while making errors 3–4× more frequent. Running both engines in parallel and choosing afterwards has the same problem: there is no reliable confidence signal for “Parakeet transliterated an English word”.

Conclusion: for mixed-language speech, one strong multilingual model with language-aware segmentation and a coverage check is both the most accurate and, after the encoder cache, close to the fastest option. Parakeet remains the best choice for modes that really are one language, which *Automatic* already does.

## What could still make it better

- **Streaming partial results** for long dictations (perceived latency).
- **A Core ML / WhisperKit build of the same model** to drop the Python runtime and possibly speed up the encoder on the Neural Engine; needs the same evaluation before switching.
- **Consented natural recordings.** The numbers above use synthetic voices; real accents and microphones will differ. `scripts/eval-routing.py` and `scripts/compare-asr.py` take any clip list, so the comparison can be repeated on real speech.

## Reproduce

```
S="$HOME/Library/Application Support"
python3 -I scripts/eval-routing.py \
  --whisper "<python with mlx-whisper>:<whisper-turbo model dir>" \
  --parakeet "$S/Saidright/Runtime-Parakeet/bin/python3:$S/Saidright/Models/parakeet-tdt-0.6b-v3" \
  --out eval/results/<date>-routing.md
```
