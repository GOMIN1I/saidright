#!/usr/bin/env python3
"""Compares speech recognisers on the same clips: accuracy, warm latency, load time, memory.

  python3 scripts/compare-asr.py --items <items.json> --engine whisper:<python>:<model-dir>[:<langs>] \
      --engine parakeet:<python>:<model-dir> [--out eval/results/<name>.md]

items.json: [{"id", "lang" (ru|en|de|zh|mixed|none), "path", "ref", "seconds"?}]. Whisper runs through
Resources/recognizer.py exactly as the app does (VAD, language ID restricted to <langs>,
default "ru,en" like the owner's modes; de/zh clips use their own language). Parakeet runs
through Resources/recognizer.py with --engine parakeet.

Each engine is a separate process; one warm-up clip is decoded before timing. Memory is the
resident size of the worker after all clips. Error rates: WER (word) for alphabetic languages,
CER (character) for Chinese, after lower-casing, NFKC, ё→е and removing punctuation.
"""
import argparse
import json
import platform
import re
import subprocess
import time
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NUMBER_WORDS = None


def normalize(text, lang):
    text = unicodedata.normalize('NFKC', text).lower().replace('ё', 'е')
    if lang == 'zh':
        return [c for c in text if not unicodedata.category(c).startswith(('P', 'Z', 'S'))]
    text = re.sub(r"[^\w\s']", ' ', text)
    return text.split()


def distance(a, b):
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def rss_mb(pid):
    out = subprocess.run(['ps', '-o', 'rss=', '-p', str(pid)], capture_output=True, text=True).stdout.strip()
    return int(out) / 1024 if out else 0


class Worker:
    def __init__(self, kind, python, model_dir, langs):
        self.kind, self.langs = kind, langs
        args = [python, '-I', '-u', str(ROOT / 'Resources' / 'recognizer.py'), '--model-dir', model_dir, '--cache-dir', str(ROOT / 'build' / 'hf-cache'), '--engine', kind]
        self.proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
        self.n = 0

    def send(self, payload):
        self.n += 1
        payload['id'] = str(self.n)
        self.proc.stdin.write(json.dumps(payload, ensure_ascii=False) + '\n')
        self.proc.stdin.flush()
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError('worker exited')
            reply = json.loads(line)
            if reply.get('id') == payload['id'] and reply.get('type') != 'progress':
                return reply

    def languages_for(self, lang):
        if lang in ('de', 'zh'):
            return [lang]
        return self.langs

    def close(self):
        self.proc.terminate()


def audio_seconds(path):
    import wave
    try:
        with wave.open(path) as w:
            return w.getnframes() / w.getframerate()
    except Exception:
        return 0.0


def run(engine, items):
    kind, python, model_dir, *rest = engine.split(':')
    langs = rest[0].split(',') if rest else ['ru', 'en']
    w = Worker(kind, python, model_dir, langs)
    t0 = time.monotonic()
    ready = w.send({'command': 'prepare'})
    load = time.monotonic() - t0
    if ready.get('type') != 'ready':
        raise RuntimeError(f'{kind}: {ready}')
    w.send({'command': 'transcribe', 'path': items[0]['path'], 'languages': w.languages_for(items[0]['lang'])})  # warm-up
    rows = []
    for it in items:
        t = time.monotonic()
        reply = w.send({'command': 'transcribe', 'path': it['path'], 'languages': w.languages_for(it['lang'])})
        dt = time.monotonic() - t
        text = reply.get('text', '') if reply.get('type') == 'transcript' else f"[{reply.get('code')}]"
        rows.append({**it, 'hyp': text, 'seconds': dt, 'audio': it.get('seconds') or audio_seconds(it['path']), 'detected': reply.get('languages')})
    mem = rss_mb(w.proc.pid)
    w.close()
    return {'name': f'{kind}:{Path(model_dir).name}', 'load': load, 'memory': mem, 'rows': rows}


def summarize(result):
    by = {}
    for r in result['rows']:
        lang = r['lang']
        ref, hyp = normalize(r['ref'], 'zh' if lang == 'zh' else lang), normalize(r['hyp'], 'zh' if lang == 'zh' else lang)
        e = by.setdefault(lang, {'err': 0, 'n': 0, 'time': 0.0, 'audio': 0.0, 'clips': 0, 'empty': 0})
        if ref:
            e['err'] += distance(ref, hyp)
            e['n'] += len(ref)
        elif hyp:
            e['empty'] += 1  # text produced for silence/noise
        e['time'] += r['seconds']
        e['audio'] += r['audio']
        e['clips'] += 1
    return by


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--items', action='append', required=True)
    ap.add_argument('--engine', action='append', required=True)
    ap.add_argument('--out')
    args = ap.parse_args()
    items = []
    for f in args.items:
        items += json.load(open(f))
    results = [run(e, items) for e in args.engine]
    langs = sorted({i['lang'] for i in items}, key=lambda x: ['ru', 'en', 'mixed', 'de', 'zh', 'none'].index(x) if x in ['ru', 'en', 'mixed', 'de', 'zh', 'none'] else 9)
    lines = [f'# ASR comparison — {time.strftime("%Y-%m-%d")}', '', f'{platform.machine()} · macOS {platform.mac_ver()[0]} · {len(items)} clips', '']
    head = '| Engine | load s | memory MB | ' + ' | '.join(f'{l} {"CER" if l == "zh" else "WER"}' if l != 'none' else 'text on silence/noise' for l in langs) + ' | mean latency s | RTF |'
    lines += [head, '|' + ' --- |' * (head.count('|') - 1)]
    for res in results:
        by = summarize(res)
        cells = []
        for l in langs:
            e = by[l]
            cells.append(f"{e['empty']}/{e['clips']}" if l == 'none' else f"{100 * e['err'] / max(1, e['n']):.1f}%")
        total_t = sum(r['seconds'] for r in res['rows'])
        total_a = sum(r['audio'] for r in res['rows']) or 1
        lines.append(f"| {res['name']} | {res['load']:.1f} | {res['memory']:.0f} | " + ' | '.join(cells) + f" | {total_t / len(res['rows']):.2f} | {total_t / total_a:.3f} |")
    lines += ['', '## Per clip', '']
    for res in results:
        lines += [f"### {res['name']}", '', '| id | s | hypothesis |', '| --- | --- | --- |']
        for r in res['rows']:
            lines.append(f"| {r['id']} | {r['seconds']:.2f} | {r['hyp'][:140].replace('|', '/')} |")
        lines.append('')
    text = '\n'.join(lines)
    print(text)
    if args.out:
        Path(args.out).write_text(text + '\n')


if __name__ == '__main__':
    main()
