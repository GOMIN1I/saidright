#!/usr/bin/env python3
"""Measures the editing step (cloud or local text model): latency and faithfulness.

  python3 -I scripts/eval-editing.py --prompts <prompts.json> --variant <spec> [--variant ...] \
      --out <rows.json> [--repeat 1]

<prompts.json> is written by scripts/dump-editor-prompts.swift (compiled with Sources/SaidrightCore); it dumps
EditorPrompt.system for each mode of a modes.json, the SmartStructure prompts/schema and, per
text, EditorPrompt.wrap and SmartStructure.worthAsking — so the requests are byte-identical
to the app's. Texts: eval/editing-fixtures.json (every editing mode) plus, optionally,
other {"text", "mode"} items (e.g. the owner's raw transcripts, kept outside the repository).

A variant spec is JSON: {"name", "api": "responses"|"chat", "base": "https://api.openai.com/v1/",
"model", "body": {extra request fields}, "key": "env var holding the credential" (optional),
"structure": "sequential"|"skip"}. The credential is read from the environment and never
printed. Every variant first sends one warm-up request on its own keep-alive connection, as
the app does while the person speaks (TextProvider.warmUp).
"""
import argparse
import http.client
import json
import os
import ssl
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent


class Client:
    def __init__(self, spec):
        self.spec = spec
        url = urlparse(spec['base'])
        self.host, self.port, self.prefix = url.hostname, url.port, url.path if url.path.endswith('/') else url.path + '/'
        self.https = url.scheme == 'https'
        self.key = os.environ.get(spec.get('key', 'OPENAI_API_KEY'), '') if spec.get('key', 'OPENAI_API_KEY') else ''
        self.conn = None

    def connect(self):
        if self.https:
            self.conn = http.client.HTTPSConnection(self.host, self.port or 443, timeout=60, context=ssl.create_default_context())
        else:
            self.conn = http.client.HTTPConnection(self.host, self.port or 80, timeout=120)

    def post(self, path, body):
        headers = {'Content-Type': 'application/json'}
        if self.key:
            headers['Authorization'] = 'Bearer ' + self.key
        data = json.dumps(body).encode()
        for attempt in range(2):
            if self.conn is None:
                self.connect()
            try:
                self.conn.request('POST', self.prefix + path, body=data, headers=headers)
                response = self.conn.getresponse()
                payload = response.read()
                return response.status, json.loads(payload or b'{}')
            except (http.client.HTTPException, OSError):
                self.conn = None
                if attempt:
                    raise

    def complete(self, system, user, max_tokens, schema=None):
        spec = self.spec
        if spec['api'] == 'responses':
            body = {'model': spec['model'], 'instructions': system, 'input': user, 'max_output_tokens': max_tokens, 'store': False}
            if schema:
                body['text'] = {'format': {'type': 'json_schema', 'name': 'layout', 'strict': True, 'schema': schema}}
        else:
            body = {'model': spec['model'], 'messages': [{'role': 'system', 'content': system}, {'role': 'user', 'content': user}], 'max_tokens': max_tokens, 'temperature': 0.2}
            if schema:
                body['response_format'] = {'type': 'json_schema', 'json_schema': {'name': 'layout', 'strict': True, 'schema': schema}}
        for k, v in spec.get('body', {}).items():
            if v is None:
                body.pop(k, None)
            elif k == 'prediction' and v == 'input':
                body['prediction'] = {'type': 'content', 'content': user.split('\n', 1)[1].rsplit('\n', 1)[0]}
            else:
                body[k] = v
        for _ in range(8):
            t = time.monotonic()
            status, obj = self.post('responses' if spec['api'] == 'responses' else 'chat/completions', body)
            dt = time.monotonic() - t
            # Free tiers limit tokens per minute; wait out a 429 instead of recording it
            # (benchmark only — the app never retries silently).
            if status != 429 or 'per day' in json.dumps(obj):
                break
            time.sleep(8)
        if status != 200:
            return dt, None, {'status': status, 'error': (obj.get('error') or {}).get('code') or (obj.get('error') or {}).get('message', '')[:120]}
        if spec['api'] == 'responses':
            text = ''.join(p.get('text', '') for item in obj.get('output', []) if item.get('type') == 'message' for p in item.get('content', []) if p.get('type') == 'output_text')
            usage = obj.get('usage', {})
            meta = {'in': usage.get('input_tokens'), 'out': usage.get('output_tokens'), 'cached': (usage.get('input_tokens_details') or {}).get('cached_tokens'), 'tier': obj.get('service_tier')}
        else:
            choice = (obj.get('choices') or [{}])[0]
            text = (choice.get('message') or {}).get('content') or ''
            usage = obj.get('usage', {})
            meta = {'in': usage.get('prompt_tokens'), 'out': usage.get('completion_tokens'), 'tier': obj.get('service_tier'),
                    'rejected': (usage.get('completion_tokens_details') or {}).get('rejected_prediction_tokens')}
        return dt, text.strip(), meta


def unwrap(text):
    text = (text or '').strip().replace('<dictation>', '').replace('</dictation>', '')
    if text.startswith('```') and text.endswith('```'):
        text = text[3:-3]
        first, _, rest = text.partition('\n')
        if ' ' not in first:
            text = rest
    return text.strip()


def run_variant(spec, prompts, items, repeat):
    client = Client(spec)
    modes = {m['name']: m for m in prompts['modes']}
    schema = json.loads(prompts['schema'])
    flags = {t['text']: t for t in prompts['texts']}
    # Warm-up: same shape as a real request, result discarded.
    first = next(iter(modes.values()))
    client.complete(first['system'], flags[items[0]['text']]['wrapped'], 256)
    rows = []
    for it in items:
        mode = modes[it['mode']]
        f = flags[it['text']]
        for r in range(repeat):
            edit_s, answer, meta = client.complete(mode['system'], f['wrapped'], max(256, len(it['text']) * 2 + 200))
            edited = unwrap(answer) if answer is not None else None
            struct_s, layout = 0.0, None
            if edited and mode['smartStructure'] and spec.get('structure', 'sequential') == 'sequential' and f['worthAsking']:
                key = ('title' if mode['cleanup'] != 'light' else 'plain') + ('Table' if f['table'] else '')
                struct_s, layout, _ = client.complete(prompts['structure'][key], '<dictation>\n' + edited + '\n</dictation>', max(400, len(edited) * 3 + 300), schema=schema)
            rows.append({**it, 'variant': spec['name'], 'run': r, 'edit_s': edit_s, 'struct_s': struct_s, 'total_s': edit_s + struct_s,
                         'edited': edited, 'layout': layout, 'meta': meta})
            print(f"{spec['name']:<28} {it['id'][:24]:<24} {it['mode'][:10]:<10} edit {edit_s:5.2f} struct {struct_s:5.2f}", file=sys.stderr, flush=True)
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--prompts', required=True)
    ap.add_argument('--variant', action='append', required=True)
    ap.add_argument('--extra', help='JSON list of {"id","text","mode"} items outside the repo')
    ap.add_argument('--modes', help='comma-separated mode names for the fixture texts (default: every editing mode)')
    ap.add_argument('--repeat', type=int, default=1)
    ap.add_argument('--limit', type=int)
    ap.add_argument('--out', required=True)
    args = ap.parse_args()
    prompts = json.load(open(args.prompts))
    mode_names = args.modes.split(',') if args.modes else [m['name'] for m in prompts['modes']]
    items = []
    for fx in json.load(open(ROOT / 'eval' / 'editing-fixtures.json'))['items']:
        for m in mode_names:
            items.append({'id': fx['id'], 'text': fx['text'], 'mode': m, 'keep': fx.get('keep', []), 'learner': fx.get('learner', False), 'source': 'fixture'})
    if args.extra:
        items += [{**x, 'keep': [], 'learner': False, 'source': 'owner'} for x in json.load(open(args.extra))]
    if args.limit:
        items = items[:args.limit]
    rows = []
    for v in args.variant:
        rows += run_variant(json.loads(v), prompts, items, args.repeat)
    Path(args.out).write_text(json.dumps(rows, ensure_ascii=False, indent=1))


if __name__ == '__main__':
    main()
