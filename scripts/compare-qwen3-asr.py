#!/usr/bin/env python3
"""Compares Qwen3-ASR (mlx-qwen3-asr) with the app's Whisper path on the same clips.

  python3 -I scripts/compare-qwen3-asr.py \
      --whisper "<python with mlx-whisper>:<whisper-turbo model dir>" \
      --qwen "<python with mlx-qwen3-asr>:<Qwen3-ASR model dir>" [--qwen ...] \
      [--recordings <dir of the owner's WAVs>] \
      --dump <rows.json outside the repo> [--out eval/results/<name>.md]

Clips: eval/fixtures.json + eval/routing-fixtures.json (WAVs in build/fixtures and
build/routing-fixtures, made by scripts/make-fixtures.sh / eval-routing.py). With
--recordings, real recordings are added without a reference; they are compared with
Whisper's output and their text is only written to --dump, never to the report.

Whisper runs through Resources/recognizer.py exactly as the app does (VAD, language ID
restricted to ru+en). Qwen3-ASR runs in its own process (this file with --serve) on the
whole file with automatic language detection, or with one forced language
(--qwen python:model:Russian). Each engine decodes one warm-up clip first; each clip is
then decoded once. (Repeating a clip is not a valid latency sample for Whisper: the
worker's encoder cache returns the previous pass for identical audio.)
"""
import argparse
import difflib
import importlib.util
import json
import platform
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def serve(model_dir, language):
    """Worker mode, run with the Qwen venv's python: JSON lines in, JSON lines out."""
    import numpy as np
    import soundfile as sf
    from mlx_qwen3_asr import Session
    t = time.monotonic()
    session = Session(model=model_dir)
    print(json.dumps({'type': 'ready', 'load': time.monotonic() - t}), flush=True)
    for line in sys.stdin:
        req = json.loads(line)
        audio, rate = sf.read(req['path'], dtype='float32', always_2d=False)
        if audio.ndim == 2:
            audio = audio.mean(axis=1)
        assert rate == 16000, rate
        t = time.monotonic()
        result = session.transcribe(np.ascontiguousarray(audio), language=language or None)
        print(json.dumps({'type': 'transcript', 'text': result.text, 'language': result.language,
                          'seconds': time.monotonic() - t}, ensure_ascii=False), flush=True)


def load_compare():
    spec = importlib.util.spec_from_file_location('compare_asr', ROOT / 'scripts' / 'compare-asr.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


compare = load_compare()


class QwenWorker:
    def __init__(self, python, model_dir, language):
        self.proc = subprocess.Popen([python, '-I', '-u', str(Path(__file__).resolve()), '--serve', model_dir, language or ''],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
        self.ready = json.loads(self.proc.stdout.readline())

    def send(self, path):
        self.proc.stdin.write(json.dumps({'path': path}) + '\n')
        self.proc.stdin.flush()
        return json.loads(self.proc.stdout.readline())

    def close(self):
        self.proc.terminate()


def items_from(spec_file, wav_dir):
    out = []
    for item in json.load(open(spec_file))['items']:
        path = wav_dir / f"{item['id']}.wav"
        if path.exists():
            out.append({'id': item['id'], 'lang': item['lang'], 'path': str(path), 'ref': ' '.join(item.get('parts', [])), 'real': False})
    return out


def run_engine(engine, items):
    kind, python, model_dir, *rest = engine.split(':')
    if kind == 'whisper':
        w = compare.Worker('whisper', python, model_dir, ['ru', 'en'])
        t = time.monotonic()
        w.send({'command': 'prepare'})
        load = time.monotonic() - t

        def decode(it):
            reply = w.send({'command': 'transcribe', 'path': it['path'], 'languages': w.languages_for(it['lang'])})
            return reply.get('text', ''), ','.join(reply.get('languages') or [])
        name = f'whisper:{Path(model_dir).name}'
    else:
        language = rest[0] if rest else ''
        w = QwenWorker(python, model_dir, language)
        load = w.ready['load']

        def decode(it):
            reply = w.send(it['path'])
            return reply.get('text', ''), reply.get('language', '')
        name = f'qwen:{Path(model_dir).name}' + (f':{language}' if language else '')
    decode(items[0])  # warm-up
    rows = []
    for it in items:
        t = time.monotonic()
        text, detected = decode(it)
        rows.append({**it, 'hyp': text, 'detected': detected, 'seconds': time.monotonic() - t})
    mem = compare.rss_mb(w.proc.pid)
    w.close()
    return {'name': name, 'load': load, 'memory': mem, 'rows': rows}


CYR = re.compile('[а-яё]')
LAT = re.compile('[a-z]')


def latin_share(words):
    lat = sum(1 for w in words if LAT.search(w) and not CYR.search(w))
    cyr = sum(1 for w in words if CYR.search(w))
    return lat / max(1, lat + cyr)


def word_errors(ref_text, hyp_text):
    ref, hyp = compare.normalize(ref_text, 'ru'), compare.normalize(hyp_text, 'ru')
    return compare.distance(ref, hyp), len(ref)


def changed_spans(a_text, b_text, limit=3):
    """Short changed word spans (for flagging, not full transcripts)."""
    a, b = compare.normalize(a_text, 'ru'), compare.normalize(b_text, 'ru')
    spans = []
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(a=a, b=b, autojunk=False).get_opcodes():
        if op != 'equal':
            spans.append(f"{' '.join(a[i1:i2][:5])} → {' '.join(b[j1:j2][:5])}")
    return spans[:limit]


def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--serve':
        serve(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else '')
        return
    ap = argparse.ArgumentParser()
    ap.add_argument('--whisper', required=True)
    ap.add_argument('--qwen', action='append', required=True)
    ap.add_argument('--recordings')
    ap.add_argument('--dump', required=True)
    ap.add_argument('--out')
    args = ap.parse_args()

    items = items_from(ROOT / 'eval' / 'fixtures.json', ROOT / 'build' / 'fixtures')
    items += items_from(ROOT / 'eval' / 'routing-fixtures.json', ROOT / 'build' / 'routing-fixtures')
    if args.recordings:
        for path in sorted(Path(args.recordings).glob('*.wav')):
            items.append({'id': path.stem[:8], 'lang': 'real', 'path': str(path), 'ref': '', 'real': True})
    for it in items:
        it['audio'] = compare.audio_seconds(it['path'])

    results = [run_engine('whisper:' + args.whisper, items)]
    results += [run_engine('qwen:' + q, items) for q in args.qwen]
    Path(args.dump).write_text(json.dumps(results, ensure_ascii=False, indent=1))

    whisper_rows = {r['path']: r for r in results[0]['rows']}
    groups = ['ru', 'en', 'inline', 'mixed', 'de', 'zh']
    lines = [f'# Qwen3-ASR vs Whisper — {time.strftime("%Y-%m-%d")}', '',
             f'{platform.machine()} · macOS {platform.mac_ver()[0]} · {sum(not i["real"] for i in items)} synthetic clips'
             + (f' + {sum(i["real"] for i in items)} real recordings' if args.recordings else ''), '',
             '| Engine | load s | memory MB | ' + ' | '.join(f'{g} WER' for g in groups) + ' | silence/noise with text | median s (synthetic) | median s (real ≤ 6 s) | median s (real, all) |',
             '|' + ' --- |' * (len(groups) + 7)]
    for res in results:
        cells = []
        for g in groups:
            err = n = 0
            for r in res['rows']:
                if r['lang'] == g:
                    e, k = word_errors(r['ref'], r['hyp']) if g != 'zh' else (compare.distance(compare.normalize(r['ref'], 'zh'), compare.normalize(r['hyp'], 'zh')), len(compare.normalize(r['ref'], 'zh')))
                    err, n = err + e, n + k
            cells.append(f'{100 * err / n:.1f}%' if n else '–')
        empty = [r for r in res['rows'] if r['lang'] == 'none']
        syn = [r['seconds'] for r in res['rows'] if not r['real']]
        short = [r['seconds'] for r in res['rows'] if r['real'] and r['audio'] <= 6]
        real = [r['seconds'] for r in res['rows'] if r['real']]
        med = lambda xs: f'{statistics.median(xs):.2f}' if xs else '–'
        lines.append(f"| {res['name']} | {res['load']:.1f} | {res['memory']:.0f} | " + ' | '.join(cells)
                     + f" | {sum(bool(r['hyp'].strip()) for r in empty)}/{len(empty)} | {med(syn)} | {med(short)} | {med(real)} |")

    if args.recordings:
        lines += ['', '## Real recordings vs Whisper (Whisper output as reference; text not shown)', '',
                  '| Engine | word difference | clips that differ | clips whose Latin/Cyrillic share moves by > 20 points |', '| --- | --- | --- | --- |']
        for res in results[1:]:
            err = n = differ = moved = 0
            for r in res['rows']:
                if not r['real']:
                    continue
                ref = whisper_rows[r['path']]['hyp']
                e, k = word_errors(ref, r['hyp'])
                err, n = err + e, n + k
                differ += e > 0
                moved += abs(latin_share(compare.normalize(ref, 'ru')) - latin_share(compare.normalize(r['hyp'], 'ru'))) > 0.2
            lines.append(f"| {res['name']} | {100 * err / max(1, n):.1f}% | {differ}/{sum(r['real'] for r in res['rows'])} | {moved} |")

    lines += ['', '## Synthetic clips, per clip', '']
    for res in results:
        lines += [f"### {res['name']}", '', '| id | lang | s | detected | hypothesis |', '| --- | --- | --- | --- | --- |']
        for r in res['rows']:
            if not r['real']:
                lines.append(f"| {r['id']} | {r['lang']} | {r['seconds']:.2f} | {r['detected']} | {r['hyp'][:140].replace('|', '/')} |")
        lines.append('')
    text = '\n'.join(lines)
    print(text)
    if args.out:
        Path(args.out).write_text(text + '\n')


if __name__ == '__main__':
    main()
