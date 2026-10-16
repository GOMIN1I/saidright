#!/usr/bin/env python3
"""Runs the recogniser worker over build/fixtures and reports WER/CER, key-token
preservation and timing. Optionally compares with the Govori 0.2 worker (baseline).

  python3 scripts/eval-asr.py --python <runtime python3> --model-dir <whisper dir> \
      [--baseline <path to old recognizer.py>] [--out eval/results/<name>.md]

Synthetic speech only checks plumbing and regressions; it is not an accuracy claim
about natural voices.
"""
import argparse
import json
import platform
import re
import subprocess
import sys
import time
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def normalize(text, lang):
    text = unicodedata.normalize('NFKC', text).lower().replace('ё', 'е')
    if lang == 'zh':
        return [c for c in text if not unicodedata.category(c).startswith(('P', 'Z', 'S'))]
    text = re.sub(r"[^\w\s']", ' ', text)
    return text.split()


def edit_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def error_rate(ref, hyp, lang):
    r, h = normalize(ref, lang), normalize(hyp, lang)
    if not r:
        return None
    return edit_distance(r, h) / len(r)


class Worker:
    def __init__(self, python, script, model_dir, legacy=False):
        self.legacy = legacy
        args = [python, '-I', '-u', script] if legacy else [python, '-I', '-u', script, '--model-dir', model_dir, '--cache-dir', str(ROOT / 'build' / 'hf-cache')]
        self.proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)

    def send(self, payload):
        self.proc.stdin.write(json.dumps(payload) + '\n')
        self.proc.stdin.flush()
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError('worker exited')
            obj = json.loads(line)
            if obj.get('type') == 'progress' or 'status' in obj:
                continue
            return obj

    def transcribe(self, path, languages):
        started = time.monotonic()
        if self.legacy:
            req = {'path': str(path)}
            if len(languages) == 1:
                req['language'] = languages[0]
            obj = self.send(req)
        else:
            obj = self.send({'id': path.stem, 'command': 'transcribe', 'path': str(path), 'languages': languages})
        return obj.get('text', ''), time.monotonic() - started, obj

    def close(self):
        self.proc.stdin.close()
        self.proc.wait(timeout=30)


def audio_seconds(path):
    import wave
    with wave.open(str(path)) as w:
        return w.getnframes() / w.getframerate()


def run(worker, spec, fixtures, languages, label):
    rows = []
    # Warm-up so per-clip timings are warm-path numbers; cold load is measured separately.
    t0 = time.monotonic()
    worker.transcribe(fixtures / 'silence.wav', languages)
    first = fixtures / f"{spec['items'][0]['id']}.wav"
    worker.transcribe(first, languages)
    cold = time.monotonic() - t0
    for item in spec['items']:
        path = fixtures / f"{item['id']}.wav"
        text, seconds, raw = worker.transcribe(path, languages)
        ref = ' '.join(item['parts'])
        lang = item['lang']
        metric = item.get('metric', 'wer')
        rate = error_rate(ref, text, 'zh' if lang == 'zh' else 'x') if ref else None
        keys = item.get('keys', [])
        kept = [k for k in keys if k.lower().replace('ё', 'е') in text.lower().replace('ё', 'е')]
        rows.append({
            'config': label, 'id': item['id'], 'lang': lang, 'audio_s': round(audio_seconds(path), 2),
            'asr_s': round(seconds, 3), 'rtf': round(seconds / max(0.01, audio_seconds(path)), 3),
            'metric': metric, 'error_rate': None if rate is None else round(rate, 3),
            'keys_kept': f'{len(kept)}/{len(keys)}', 'empty_ok': (not ref and not text.strip()) if not ref else None,
            'hypothesis': text,
        })
    return rows, cold


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--python', required=True)
    ap.add_argument('--model-dir', required=True)
    ap.add_argument('--baseline')
    ap.add_argument('--out')
    args = ap.parse_args()
    spec = json.loads((ROOT / 'eval' / 'fixtures.json').read_text())
    fixtures = ROOT / 'build' / 'fixtures'
    configs = [('new, languages=[ru,en]', False, ['ru', 'en']), ('new, auto (any language)', False, [])]
    if args.baseline:
        configs.append(('Govori 0.2 baseline, auto', True, []))
    all_rows, colds = [], {}
    for label, legacy, langs in configs:
        worker = Worker(args.python, args.baseline if legacy else str(ROOT / 'Resources' / 'recognizer.py'), args.model_dir, legacy)
        rows, cold = run(worker, spec, fixtures, langs, label)
        worker.close()
        all_rows += rows
        colds[label] = round(cold, 2)

    lines = [f"# ASR evaluation — synthetic set", '',
             f"Date: {time.strftime('%Y-%m-%d')}. Machine: {platform.machine()}, macOS {platform.mac_ver()[0]}. Model dir: `{Path(args.model_dir).name}`.",
             'Fixtures: macOS synthetic voices (see eval/fixtures.json). Warm-path timings; the cold column is model load + first two clips.', '']
    for label in colds:
        rows = [r for r in all_rows if r['config'] == label]
        rates = [r['error_rate'] for r in rows if r['error_rate'] is not None]
        lines += [f"## {label}", '', f"Cold start + 2 clips: {colds[label]} s. Mean error rate over {len(rates)} speech clips: {sum(rates)/len(rates):.3f}.", '',
                  '| clip | lang | audio s | ASR s | RTF | WER/CER | key tokens | output |', '|---|---|---|---|---|---|---|---|']
        for r in rows:
            er = '—' if r['error_rate'] is None else f"{r['error_rate']:.2f} ({r['metric'].upper()})"
            out = r['hypothesis'].replace('|', '/')[:90] or '(empty)'
            lines.append(f"| {r['id']} | {r['lang']} | {r['audio_s']} | {r['asr_s']} | {r['rtf']} | {er} | {r['keys_kept']} | {out} |")
        lines.append('')
    report = '\n'.join(lines)
    print(report)
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(report)
        Path(args.out).with_suffix('.json').write_text(json.dumps(all_rows, ensure_ascii=False, indent=1))


if __name__ == '__main__':
    sys.exit(main())
