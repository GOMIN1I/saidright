#!/usr/bin/env python3
"""Evaluates engine routing for a mixed-language (ru+en) mode on the same clips.

  python3 scripts/eval-routing.py --whisper <python>:<model-dir> --parakeet <python>:<model-dir> \
      [--fixtures eval/routing-fixtures.json] [--threshold 0.8] [--out eval/results/<name>.md]

Policies compared:
  whisper  – today's choice for mixed modes: Whisper with per-region language ID and recovery.
  parakeet – Parakeet for everything (what "fast" would give if forced).
  gated    – Whisper language ID per voiced region first; when every region is the same
             Parakeet language with probability >= threshold, Parakeet decodes, else Whisper.
             Latency = language ID + the chosen engine (the Whisper branch reuses the encoder
             pass of the language ID through the worker's encoder cache).

Clips are generated with macOS `say` + ffmpeg into build/routing-fixtures (not committed).
Each engine runs in its own worker process through Resources/recognizer.py, as in the app.
"""
import argparse
import importlib.util
import json
import os
import platform
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location('compare_asr', ROOT / 'scripts' / 'compare-asr.py')
compare = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(compare)
PARAKEET_LANGS = {'bg', 'hr', 'cs', 'da', 'nl', 'en', 'et', 'fi', 'fr', 'de', 'el', 'hu', 'it', 'lv', 'lt', 'mt', 'pl', 'pt', 'ro', 'sk', 'sl', 'es', 'sv', 'ru', 'uk'}


def make_clips(spec, out):
    out.mkdir(parents=True, exist_ok=True)
    items = []
    for item in spec['items']:
        target = out / f"{item['id']}.wav"
        if not target.exists():
            with tempfile.TemporaryDirectory() as tmp:
                pieces = []
                for i, text in enumerate(item['parts']):
                    voice = item['voice'][i] if isinstance(item['voice'], list) else item['voice']
                    aiff, wav = os.path.join(tmp, f'{i}.aiff'), os.path.join(tmp, f'{i}.wav')
                    subprocess.run(['say', '-v', voice, '-o', aiff, text], check=True)
                    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', aiff, '-ar', '16000', '-ac', '1', wav], check=True)
                    pieces.append(wav)
                lst = os.path.join(tmp, 'list.txt')
                Path(lst).write_text(''.join(f"file '{p}'\n" for p in pieces))
                subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', lst, '-ar', '16000', '-ac', '1', str(target)], check=True)
        items.append({'id': item['id'], 'lang': item['lang'], 'path': str(target), 'ref': ' '.join(item['parts'])})
    return items


def start(kind, spec):
    python, model_dir = spec.split(':', 1)
    worker = compare.Worker(kind, python, model_dir, ['ru', 'en'])
    t0 = time.monotonic()
    ready = worker.send({'command': 'prepare'})
    if ready.get('type') != 'ready':
        raise RuntimeError(f'{kind}: {ready}')
    return worker, time.monotonic() - t0


def timed(worker, payload):
    t = time.monotonic()
    reply = worker.send(payload)
    return reply, time.monotonic() - t


def wer(rows, key, lang):
    err = n = 0
    for r in rows:
        if lang != 'all' and r['lang'] != lang:
            continue
        ref = compare.normalize(r['ref'], 'ru')
        err += compare.distance(ref, compare.normalize(r[key], 'ru'))
        n += len(ref)
    return 100 * err / max(1, n)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--whisper', required=True)
    ap.add_argument('--parakeet', required=True)
    ap.add_argument('--fixtures', default=str(ROOT / 'eval' / 'routing-fixtures.json'))
    ap.add_argument('--threshold', type=float, default=0.8)
    ap.add_argument('--out')
    args = ap.parse_args()
    items = make_clips(json.load(open(args.fixtures)), ROOT / 'build' / 'routing-fixtures')
    whisper, _ = start('whisper', args.whisper)
    parakeet, _ = start('parakeet', args.parakeet)
    langs = ['ru', 'en']
    for w in (whisper, parakeet):  # warm-up
        w.send({'command': 'transcribe', 'path': items[0]['path'], 'languages': langs})
    whisper.send({'command': 'languages', 'path': items[0]['path'], 'languages': langs})
    rows = []
    for it in items:
        # Language ID first, as a gated pipeline would run it; Whisper then reuses the cached
        # encoder pass for the same window, which is what the app gets too.
        lid, tl = timed(whisper, {'command': 'languages', 'path': it['path'], 'languages': langs})
        w, tw = timed(whisper, {'command': 'transcribe', 'path': it['path'], 'languages': langs})
        p, tp = timed(parakeet, {'command': 'transcribe', 'path': it['path'], 'languages': langs})
        regions = lid.get('regions', [])
        codes = {r['language'] for r in regions}
        single = len(codes) == 1 and codes <= PARAKEET_LANGS and all(r['probability'] >= args.threshold for r in regions)
        rows.append({
            **it, 'whisper': w.get('text', ''), 'parakeet': p.get('text', ''),
            'tw': tw, 'tp': tp, 'tl': tl, 'regions': regions, 'route': 'parakeet' if single else 'whisper',
        })
        rows[-1]['gated'] = rows[-1]['parakeet'] if single else rows[-1]['whisper']
        rows[-1]['tg'] = tl + (tp if single else tw)
        rows[-1]['tw_total'] = tl + tw  # the app's Whisper request does both steps
    whisper.close()
    parakeet.close()

    groups = ['ru', 'en', 'inline', 'mixed', 'all']
    lines = [f'# Engine routing for a ru+en mode — {time.strftime("%Y-%m-%d")}', '',
             f'{platform.machine()} · macOS {platform.mac_ver()[0]} · {len(rows)} synthetic clips (`eval/routing-fixtures.json`) · gate threshold {args.threshold}', '',
             '| Policy | ' + ' | '.join(f'{g} WER' for g in groups) + ' | mean latency s |', '|' + ' --- |' * (len(groups) + 2)]
    for name, text_key, time_key in (('whisper (today)', 'whisper', 'tw_total'), ('parakeet only', 'parakeet', 'tp'), ('gated', 'gated', 'tg')):
        mean = sum(r[time_key] for r in rows) / len(rows)
        lines.append(f'| {name} | ' + ' | '.join(f'{wer(rows, text_key, g):.1f}%' for g in groups) + f' | {mean:.2f} |')
    lid_mean = sum(r['tl'] for r in rows) / len(rows)
    lines += ['', f'Language ID alone: {lid_mean:.2f} s per clip on average.', '',
              '| id | gate | regions | whisper | parakeet |', '| --- | --- | --- | --- | --- |']
    for r in rows:
        regions = ', '.join(f"{x['language']} {x['probability']:.2f}" for x in r['regions'])
        lines.append(f"| {r['id']} | {r['route']} | {regions} | {r['whisper'][:90]} ({r['tw_total']:.2f} s) | {r['parakeet'][:90]} ({r['tp']:.2f} s) |")
    text = '\n'.join(lines)
    print(text)
    if args.out:
        Path(args.out).write_text(text + '\n')


if __name__ == '__main__':
    main()
