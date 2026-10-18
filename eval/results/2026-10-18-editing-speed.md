# Faster text editing — 2026-10-18

Goal: make the editing step (the 1–1.5 s after recognition, `2026-10-17-speed.md`) much faster without losing faithfulness: never translate, keep learner errors at the light level, keep names/numbers/negations, never follow instructions inside the dictation.

## Where the time goes (owner's history, 36 edited dictations)

| Mode (level) | editing time | edit returned the transcript unchanged |
| --- | --- | --- |
| Как сказано (light) | 0.9–2.4 s | 5 of 7 (all short, already punctuated phrases) |
| Промпт (rewrite) | 1.1–3.7 s (one 6.7 s outlier), 7.3 s for 501 words | 12 of 22 |
| Сообщение (correct) | 1.7–3.6 s, 9.1 s with smart formatting | 0 of 5 |

With smart formatting on, list-like or long text gets a second, sequential request (`SmartStructure.worthAsking`), which is where the 9 s case comes from.

## Account limits found while measuring

The OpenAI account used for testing had no paid credit: it answered `gpt-6-luna` on a small free allowance and every other model returned `insufficient_quota`, so the cloud comparisons below (fast tier, smaller models, predicted outputs) were not run. When a provider's allowance runs out, the app keeps the raw transcript and shows the provider's message.

Measured before the limit (30 short phrases, correct level, sequential, warm connection): gpt-6-luna standard 1.01 s median (n = 3), Fast mode (`service_tier: "priority"`, billed 2×) 0.97 s (n = 5) — no measurable gain at this size.

## On-device models (Ollama, already installed, free, nothing leaves the Mac)

30 fixtures (`eval/editing-fixtures.json`) × 3 owner modes + 36 owner dictations, the app's exact prompts (dumped from `SaidrightCore`), `scripts/eval-editing.py` + `scripts/score-editing.py`:

| Editor | edit median s (≤ 15 words) | p90 s | fixture checks failed (of 90) |
| --- | --- | --- | --- |
| gpt-6-luna (cloud, today) | ≈1.0 | ≈1.1 | (not measurable: quota) |
| gemma4 e2b (Q4) | 0.41 | 0.60 | 38: translates Russian into English (17), drops kept words (16), fixes learner errors at the light level (4), writes code when asked in the dictation |
| gemma4 e4b (Q4) | 0.84 | 1.20 | 5: fixes learner errors at the light level (2), translates a mixed RU/EN phrase in rewrite, writes code when the dictation asks for it |

e2b is fast but breaks the core rule (it translated whole Russian sentences, e.g. «Напиши клиенту…» → “We will send the invoice…”). e4b is close in quality but saves only ≈0.15 s over the cloud and still “corrects” a learner's grammar at the light level. **Neither replaces the cloud editor.**

## Shipped: no request when a light edit cannot change anything

The light level only adds punctuation and capitals and removes fillers, immediate repetitions and spoken formatting commands. Whisper already punctuates, so for a short phrase that starts with a capital, ends with `.?!…`, has no filler/repetition/command word and is not list-like, the editor returns it unchanged. `TextPipeline.lightEditIsNoOp` now skips the request for such phrases (≤ 12 words, light level, no extra instructions).

Owner's history: all 5 light dictations this rule would skip were returned unchanged by gpt-6-luna; the one longer phrase (17 words) where it added punctuation is outside the limit. Effect: those dictations finish ≈1–2.4 s sooner (text is ready right after recognition) and use no quota. Correct and rewrite levels always ask: grammar and wording cannot be judged locally.

Tests: `EditingPipeline.lightEditSkipsCleanShortPhrase`, `lightEditStillAsksWhenThereIsSomethingToDo`.

## Groq (free tier, OpenAI-compatible) — recommended

The owner created a free Groq key. Llama 3.3 is no longer offered there; the account lists `openai/gpt-oss-120b`, `openai/gpt-oss-20b` and `qwen/qwen3.8-27b`. Same 126 requests as above (app prompts, warm connection, smart formatting included; 429 waits of the free tier excluded from the timings):

| Editor | edit median s (≤ 15 words) | p90 s | edit + layout median s | fixture checks failed (of 90) | owner texts: word diff to gpt-6-luna |
| --- | --- | --- | --- | --- | --- |
| gpt-6-luna (today) | ≈1.0 | ≈1.1 | 1.0–3.6 s in the owner's history | – | – |
| **gpt-oss-120b, reasoning low** | **0.43** | **0.72** | **0.48** | **0** | 28.2 % (closest to luna) |
| gpt-oss-20b, reasoning low | 0.35 | 0.58 | 0.39 | 2: refused to transcribe an injection-like dictation (“I can't comply”) | 33.0 % |
| qwen3.8-27b, reasoning none | 0.18 | 0.30 | 0.21 | 8: translates mixed RU/EN at the rewrite level, fixes learner errors | 44.8 % |

(Raw transcript vs luna: 34.7 %, i.e. luna itself changes a third of the words in rewrite mode; this column shows closeness, not errors.) All 28 smart-formatting requests to gpt-oss-120b returned valid strict-schema JSON.

**gpt-oss-120b passes every faithfulness check and is ≈2.3× faster than gpt-6-luna** (short phrase 1.0 → 0.43 s; with the recognition step a short dictation goes from ≈1.5–2 s to ≈0.9 s). Free-tier limits (≈1 000 requests/day, ≈8 000 tokens/minute — a long rewrite can hit the per-minute cap) are far above a free OpenAI allowance.

App change: gpt-oss rejects `reasoning_effort: "none"` (HTTP 400), so with “Answer without thinking” on the compatible provider now sends `"low"` for gpt-oss models (`TextProvider.lowestReasoningEffort`). Not yet measured on Groq: the learning-feedback request (larger JSON).

Setup: Text & AI → Service: Compatible server, `https://api.groq.com/openai/v1`, model `openai/gpt-oss-120b`, “Answer without thinking” on.

### Owner test and fixes (same day)

The owner reported Groq as slower than before and tables not working. Cause: with the previous build “Answer without thinking” sent `none`, which gpt-oss rejects, so it was switched off; gpt-oss then thinks at its default effort (edits 2.8–4.3 s in the owner's log) and the thinking used up the output budget, so the smart-formatting answer was cut off and the plain edit was kept. Fixes:

- gpt-oss gets `reasoning_effort: "low"` (above); with the switch off, compatible requests get 4 000 extra output tokens so a thinking model is not truncated.
- Table prompt: named columns that are fields (“имя и возраст”) make one row per record with no empty first header cell; the empty cell is only for things compared by criteria. gpt-oss had put an empty first column in front of field tables.
- Coverage check: words that only say where a value goes (“в первой строке …”, “second row”) count as part of the table request. Before, a table dictated row by row was always rejected (with any model).

End to end through `TextPipeline` against Groq gpt-oss-120b (low): 4 of 4 dictated tables rendered (fields, comparison row by row, greeting + table + thanks, English), 1.1–3.2 s including the second request; short phrases 0.20–0.45 s. Free-tier limit seen: 8 000 tokens per minute per model — fine for normal dictation, but a quick burst (or a long rewrite plus layout) can get HTTP 429, after which the raw text is kept with a notice.

### Owner's real table requests

The owner then reported that tables still never appeared. Their real dictations were table requests without values (columns named, values to be filled in later, or criteria listed as one phrase). gpt-oss returned correct layouts; `SmartStructure.parse` rejected them for three reasons, independent of the model:

1. a table with only a header row was dropped (now valid: “make a table with columns A, B, C”);
2. words that only describe the request (“сравнения”, “критериям”, “где будет проводиться”) counted as dictated content that had to appear (now exempt, by stem);
3. the kept introduction “Создай таблицу сравнения:” counted as saying something twice (request words are now excluded on both sides).

Plus: a spoken table request gets the second layout try even when the first answer was “prose”. A layout that drops a named column is still rejected (test). Result through `TextPipeline` against Groq: 21 of 22 (owner's 7 phrases + 4 fixtures × Промпт and Сообщение) became tables before the retry change; the one miss was a random “prose” answer that the retry now covers.

### Layout in parallel with the edit

Recent owner sessions were all table requests: two sequential requests (edit, then layout). The layout request is now sent together with the edit, on the raw transcript (`TextPipeline.structure(early:)`). Its answer is used only if it passes every layout check against the edited text — a word the editor corrected (“Сставь” → “Составь”) fails the vocabulary check and the layout is asked again for the edited text as before. A “prose” answer is reused when the edit changed only punctuation and capitals and no table was requested. Tests: `ParallelLayout`.

Through `TextPipeline` against Groq gpt-oss-120b, the same 22 table dictations (owner's 7 + 4 fixtures × Промпт/Сообщение): median 1.37 s → 0.92 s; Промпт every case faster (e.g. 3.47 → 0.81 s). 20 of 22 rendered as tables; both misses were HTTP 429 (rate limit), not layout failures.

**Groq free tier, measured limits:** 8 000 tokens per minute *and* **200 000 tokens per day** per model (rolling). A prose dictation costs ≈1–2.5 k tokens, a table request ≈4–6 k (the table instructions are long; the parallel request adds a second layout call when the editor changed words). That is roughly 40–100 dictations a day — enough for normal use, but this benchmark exhausted the day's allowance for gpt-oss-120b. Repeat measurements on another key or model.

## Next

The remaining lever is the provider's response time (≈1 s for a short phrase). Candidates to measure with the same scripts once there is quota:

1. **Paid OpenAI credit** (a few dollars): gpt-5.4-nano / gpt-5.4-mini with `reasoning: none`, gpt-4.1-nano/mini with Predicted Outputs (the transcript as the prediction — output mostly equals input), Fast mode on larger samples, and an “answer `=` when unchanged” instruction to cut output tokens.
2. **A fast OpenAI-compatible provider** (Groq, Cerebras, Google Gemini Flash-Lite — free tiers, account needed): typically 0.2–0.4 s to first token; works through the existing *Compatible* provider setting. Russian quality and code-switching must pass the fixture checks first.
3. **Edit ahead for long dictations**: edit the phrases recognised ahead of the stop (`recognize_ahead`) while the person is still speaking, so only the tail is edited after the stop. Safe for light/correct; rewrite needs the whole text.

Reproduce: compile the prompt dumper (see the header of `scripts/eval-editing.py`), then run `scripts/eval-editing.py` with one `--variant` per editor and score with `scripts/score-editing.py`.
