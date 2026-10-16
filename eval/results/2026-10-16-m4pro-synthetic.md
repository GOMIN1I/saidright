# ASR evaluation — synthetic set

Date: 2026-10-16. Machine: arm64, macOS 27.0. Model dir: `whisper-turbo`.
Fixtures: macOS synthetic voices (see eval/fixtures.json). Warm-path timings; the cold column is model load + first two clips.

## new, languages=[ru,en]

Cold start + 2 clips: 2.02 s. Mean error rate over 13 speech clips: 0.031.

| clip | lang | audio s | ASR s | RTF | WER/CER | key tokens | output |
|---|---|---|---|---|---|---|---|
| ru-short | ru | 2.36 | 0.81 | 0.344 | 0.17 (WER) | 0/1 | Привет, я буду через 10 минут. |
| ru-names-numbers | ru | 7.6 | 0.874 | 0.115 | 0.15 (WER) | 4/4 | Встреча с Анной Петровой перенесена на 15 марта в 14 часов 30 минут, кабинет 204. |
| ru-negation | ru | 4.35 | 0.856 | 0.197 | 0.00 (WER) | 2/2 | Я не буду отправлять этот файл, пока клиент не подтвердит бюджет. |
| ru-long-pauses | ru | 9.62 | 1.646 | 0.171 | 0.00 (WER) | 1/1 | Сначала нужно записать голос. Потом проверить пунктуацию. И только после этого отправить т |
| ru-quiet | ru | 2.89 | 0.829 | 0.287 | 0.00 (WER) | 1/1 | Это тихая фраза, которую легко потерять. |
| ru-noise | ru | 2.84 | 0.85 | 0.299 | 0.00 (WER) | 1/1 | Проверка распознавания при фоновом шуме в кафе. |
| en-short | en | 2.22 | 0.815 | 0.368 | 0.00 (WER) | 1/1 | Can you send me the report by Friday? |
| en-learner-errors | en | 3.13 | 0.831 | 0.266 | 0.00 (WER) | 2/2 | Yesterday I go to the shop and buy a new microphone. |
| en-tech | en | 4.06 | 0.838 | 0.206 | 0.00 (WER) | 2/2 | Push the commit to GitHub and open a pull request for the API refactor. |
| en-negation-numbers | en | 4.21 | 0.831 | 0.197 | 0.00 (WER) | 3/3 | I don't think we need more than 3 servers for 2500 users. |
| mixed-ru-en | mixed | 6.83 | 2.433 | 0.357 | 0.00 (WER) | 3/3 | Я сделал новую ветку. and pushed the changes Посмотри, пожалуйста, когда будет время. |
| de-short | de | 2.32 | 0.824 | 0.355 | 0.00 (WER) | 1/1 | Ich schicke dir die Unterlagen morgen früh. |
| zh-short | zh | 2.93 | 0.836 | 0.285 | 0.08 (CER) | 1/1 | 我明天上午9点给你打电话。 |
| silence | none | 3.0 | 0.0 | 0.0 | — | 0/0 | (empty) |
| noise-only | none | 3.0 | 0.001 | 0.0 | — | 0/0 | (empty) |

## new, auto (any language)

Cold start + 2 clips: 2.05 s. Mean error rate over 13 speech clips: 0.031.

| clip | lang | audio s | ASR s | RTF | WER/CER | key tokens | output |
|---|---|---|---|---|---|---|---|
| ru-short | ru | 2.36 | 0.812 | 0.344 | 0.17 (WER) | 0/1 | Привет, я буду через 10 минут. |
| ru-names-numbers | ru | 7.6 | 0.876 | 0.115 | 0.15 (WER) | 4/4 | Встреча с Анной Петровой перенесена на 15 марта в 14 часов 30 минут, кабинет 204. |
| ru-negation | ru | 4.35 | 0.858 | 0.197 | 0.00 (WER) | 2/2 | Я не буду отправлять этот файл, пока клиент не подтвердит бюджет. |
| ru-long-pauses | ru | 9.62 | 1.648 | 0.171 | 0.00 (WER) | 1/1 | Сначала нужно записать голос. Потом проверить пунктуацию. И только после этого отправить т |
| ru-quiet | ru | 2.89 | 0.826 | 0.286 | 0.00 (WER) | 1/1 | Это тихая фраза, которую легко потерять. |
| ru-noise | ru | 2.84 | 0.848 | 0.298 | 0.00 (WER) | 1/1 | Проверка распознавания при фоновом шуме в кафе. |
| en-short | en | 2.22 | 0.817 | 0.369 | 0.00 (WER) | 1/1 | Can you send me the report by Friday? |
| en-learner-errors | en | 3.13 | 0.826 | 0.264 | 0.00 (WER) | 2/2 | Yesterday I go to the shop and buy a new microphone. |
| en-tech | en | 4.06 | 0.837 | 0.206 | 0.00 (WER) | 2/2 | Push the commit to GitHub and open a pull request for the API refactor. |
| en-negation-numbers | en | 4.21 | 0.829 | 0.197 | 0.00 (WER) | 3/3 | I don't think we need more than 3 servers for 2500 users. |
| mixed-ru-en | mixed | 6.83 | 2.432 | 0.356 | 0.00 (WER) | 3/3 | Я сделал новую ветку. and pushed the changes Посмотри, пожалуйста, когда будет время. |
| de-short | de | 2.32 | 0.826 | 0.355 | 0.00 (WER) | 1/1 | Ich schicke dir die Unterlagen morgen früh. |
| zh-short | zh | 2.93 | 0.831 | 0.284 | 0.08 (CER) | 1/1 | 我明天上午9点给你打电话。 |
| silence | none | 3.0 | 0.0 | 0.0 | — | 0/0 | (empty) |
| noise-only | none | 3.0 | 0.0 | 0.0 | — | 0/0 | (empty) |

## Govori 0.2 baseline, auto

Cold start + 2 clips: 1.6 s. Mean error rate over 13 speech clips: 0.037.

| clip | lang | audio s | ASR s | RTF | WER/CER | key tokens | output |
|---|---|---|---|---|---|---|---|
| ru-short | ru | 2.36 | 0.812 | 0.344 | 0.17 (WER) | 0/1 | Привет, я буду через 10 минут. |
| ru-names-numbers | ru | 7.6 | 2.458 | 0.324 | 0.15 (WER) | 4/4 | Встреча с Анной Петровой перенесена на 15 марта. В 14 часов 30 минут. Кабинет 204. |
| ru-negation | ru | 4.35 | 1.647 | 0.379 | 0.00 (WER) | 2/2 | Я не буду отправлять этот файл. пока клиент не подтвердит бюджет. |
| ru-long-pauses | ru | 9.62 | 2.442 | 0.254 | 0.00 (WER) | 1/1 | Сначала нужно записать голос. Потом проверить пунктуацию. И только после этого отправить т |
| ru-quiet | ru | 2.89 | 0.824 | 0.285 | 0.00 (WER) | 1/1 | Это тихая фраза, которую легко потерять. |
| ru-noise | ru | 2.84 | 0.85 | 0.299 | 0.00 (WER) | 1/1 | Проверка распознавания при фоновом шуме в кафе. |
| en-short | en | 2.22 | 0.82 | 0.37 | 0.00 (WER) | 1/1 | Can you send me the report by Friday? |
| en-learner-errors | en | 3.13 | 0.825 | 0.264 | 0.00 (WER) | 2/2 | Yesterday I go to the shop and buy a new microphone. |
| en-tech | en | 4.06 | 0.837 | 0.206 | 0.00 (WER) | 2/2 | Push the commit to GitHub and open a pull request for the API refactor. |
| en-negation-numbers | en | 4.21 | 0.829 | 0.197 | 0.00 (WER) | 3/3 | I don't think we need more than 3 servers for 2500 users. |
| mixed-ru-en | mixed | 6.83 | 2.432 | 0.356 | 0.08 (WER) | 2/3 | Я сделал новую ветку. and pushed the changes «Пожалуйста, когда будет время?» |
| de-short | de | 2.32 | 0.825 | 0.355 | 0.00 (WER) | 1/1 | Ich schicke dir die Unterlagen morgen früh. |
| zh-short | zh | 2.93 | 0.832 | 0.284 | 0.08 (CER) | 1/1 | 我明天上午9点给你打电话。 |
| silence | none | 3.0 | 0.0 | 0.0 | — | 0/0 | (empty) |
| noise-only | none | 3.0 | 0.803 | 0.268 | — | 0/0 | Thank you. |
