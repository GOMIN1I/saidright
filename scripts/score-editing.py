#!/usr/bin/env python3
"""Scores rows written by scripts/eval-editing.py. Prints a Markdown summary (no owner text).

  python3 -I scripts/score-editing.py <rows.json> [<rows.json> ...] [--show-failures]

Fixture checks (eval/editing-fixtures.json), per edited text:
  keep     – every 'keep' substring survives (case-insensitive)
  script   – the share of Latin words moves by at most 0.15 (no translation)
  numbers  – every digit group of the input survives
  learner  – light level: a learner's grammar errors are kept (same words as the input)
  length   – output/input length between 0.45 and 1.5 (light, correct) as IntegrityReport
Owner items carry the text the current cloud editor (gpt-6-luna) produced when they were
dictated ('reference'); the score is the word distance to it, with and without punctuation.
"""
import json
import re
import statistics
import sys
import unicodedata


def words(text, punct=False):
    text = unicodedata.normalize('NFKC', text or '').replace('ё', 'е')
    if punct:
        return re.findall(r"\w+|[^\w\s]", text)
    return re.sub(r"[^\w\s'’]", ' ', text.lower()).split()


def distance(a, b):
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def latin_share(text):
    ws = words(text)
    lat = sum(1 for w in ws if re.search('[a-z]', w) and not re.search('[а-я]', w))
    cyr = sum(1 for w in ws if re.search('[а-я]', w))
    return lat / max(1, lat + cyr)


def plain(layout_or_text):
    return re.sub(r'^\s*([-*+] (\[[ x]\] )?|\d+[.)] |#+ |> )', '', layout_or_text or '', flags=re.M).replace('**', '').replace('|', ' ')


def checks(row, cleanup):
    raw, out = row['text'], row['edited'] or ''
    fails = []
    if not out:
        return ['failed']
    low = out.lower()
    if any(k.lower() not in low for k in row.get('keep', [])):
        fails.append('keep')
    if abs(latin_share(raw) - latin_share(out)) > 0.15:
        fails.append('script')
    if not set(re.findall(r'\d+', raw)) <= set(re.findall(r'\d+', out)):
        fails.append('numbers')
    if row.get('learner') and cleanup == 'light' and words(raw) != words(out):
        fails.append('learner')
    ratio = len(out) / max(1, len(raw))
    if cleanup in ('light', 'correct') and (ratio > 1.5 and len(out) > 40 or ratio < 0.45 and len(raw) > 40):
        fails.append('length')
    return fails


def main():
    files = [a for a in sys.argv[1:] if not a.startswith('--')]
    show = '--show-failures' in sys.argv
    rows = [r for f in files for r in json.load(open(f))]
    cleanup_of = {'Как сказано': 'light', 'Сообщение': 'correct', 'Промпт': 'rewrite'}
    variants = list(dict.fromkeys(r['variant'] for r in rows))
    print('| Variant | ok | edit median s (≤ 15 words) | edit p90 s | edit+layout median s (all) | fixture checks failed | owner texts: word diff to gpt-6-luna | same words as luna | with punctuation |')
    print('| --- | --- | --- | --- | --- | --- | --- | --- | --- |')
    for v in variants:
        rs = [r for r in rows if r['variant'] == v]
        ok = [r for r in rs if r['edited'] is not None]
        short = [r['edit_s'] for r in ok if len(r['text'].split()) <= 15]
        fx = [r for r in rs if r['source'] == 'fixture']
        failed = {}
        for r in fx:
            for f in checks(r, cleanup_of.get(r['mode'], 'correct')):
                failed[f] = failed.get(f, 0) + 1
                if show:
                    print(f"  FAIL {v} {r['id']} {r['mode']} {f}: {(r['edited'] or '')[:160]!r}", file=sys.stderr)
        own = [r for r in ok if r['source'] == 'owner' and r.get('reference')]
        d = n = dp = np_ = same = 0
        for r in own:
            ref, hyp = plain(r['reference']), plain(r['edited'])
            d += distance(words(ref), words(hyp)); n += len(words(ref))
            dp += distance(words(ref, True), words(hyp, True)); np_ += len(words(ref, True))
            same += words(ref) == words(hyp)
        fail_text = ', '.join(f'{k} {c}' for k, c in sorted(failed.items())) or '0'
        p90 = sorted(r['edit_s'] for r in ok)[int(len(ok) * 0.9)] if ok else 0
        print(f"| {v} | {len(ok)}/{len(rs)} | {statistics.median(short) if short else 0:.2f} | {p90:.2f} | {statistics.median(r['total_s'] for r in ok) if ok else 0:.2f} | {fail_text} of {len(fx)} | "
              + (f"{100 * d / max(1, n):.1f}% | {same}/{len(own)} | {100 * dp / max(1, np_):.1f}% |" if own else '– | – | – |'))
    own_raw = [r for r in rows if r['variant'] == variants[0] and r['source'] == 'owner' and r.get('reference')]
    if own_raw:
        d = sum(distance(words(plain(r['reference'])), words(r['text'])) for r in own_raw)
        n = sum(len(words(plain(r['reference']))) for r in own_raw)
        dp = sum(distance(words(plain(r['reference']), True), words(r['text'], True)) for r in own_raw)
        np_ = sum(len(words(plain(r['reference']), True)) for r in own_raw)
        same = sum(words(plain(r['reference'])) == words(r['text']) for r in own_raw)
        print(f"| (no edit: raw transcript) | – | 0 | 0 | 0 | – | {100 * d / n:.1f}% | {same}/{len(own_raw)} | {100 * dp / np_:.1f}% |")


if __name__ == '__main__':
    main()
