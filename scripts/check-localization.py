#!/usr/bin/env python3
"""Checks that every UI string table is complete and consistent.

- Collects keys used in Sources/Saidright via tr("...") and expands dynamic keys
  (tr("cleanup.\\(level.rawValue)")) from the enum values listed below.
- Verifies that en, ru, de and zh-Hans define exactly that set.
- Verifies that format specifiers match the English source for every key.

Run: python3 scripts/check-localization.py   (exit code 1 on problems)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / 'Sources' / 'Saidright'
TABLES = ROOT / 'Resources' / 'Localization'
LANGS = ['en', 'ru', 'de', 'zh-Hans']

DYNAMIC = {
    'cleanup': ['off', 'light', 'correct', 'rewrite'],
    'learning': ['off', 'hint', 'detailed', 'onDemand'],
    'output': ['insert', 'copy', 'keep'],
    'tone': ['keep', 'friendly', 'neutral', 'formal', 'concise'],
    'key': ['rightCommand', 'rightOption', 'rightControl', 'rightShift'],
    'kind': ['grammar', 'vocabulary', 'punctuation', 'slip', 'possibleRecognitionError', 'style'],
    'verdict': ['keepOriginal', 'recognitionError', 'understood'],
    'grade': ['again', 'hard', 'good', 'easy'],
    'coverage': ['tested', 'modelSupported', 'experimental', 'unsupported'],
    'tint': ['saidright', 'neutral'],
    'settings': ['general', 'modes', 'shortcuts', 'recognition', 'text', 'learning', 'appearance', 'privacy', 'advanced'],
    'theme': ['system', 'light', 'dark'],
    'style': ['glass', 'ink'],
    'size': ['compact', 'regular', 'large'],
    'motion': ['standard', 'gentle', 'minimal'],
    'palette': ['signal', 'ember', 'aurora', 'graphite', 'custom'],
    'icon': ['standard', 'light', 'mono'],
    'presentation': ['card', 'indicator', 'window'],
    'linger': ['short', 'long', 'untilDismissed'],
    'depth': ['brief', 'thorough'],
    'level': ['beginner', 'intermediate', 'advanced'],
    'model': ['whisper-large-v3-turbo', 'parakeet-tdt-0.6b-v3', 'whisper-small', 'apple-on-device'],
    'hintkind': ['grammar', 'vocabulary', 'punctuation', 'slip', 'possibleRecognitionError', 'style'],
    'color': ['blue', 'pink', 'teal', 'violet', 'amber', 'lime', 'white'],
}
# Keys referenced through variables rather than tr("literal").
EXTRA = ['ollama.gemma4_e2b', 'ollama.qwen3_4b', 'ollama.gemma4_e4b', 'capsule.recording', 'capsule.processing', 'capsule.done', 'capsule.doneElsewhere', 'capsule.noSpeech', 'capsule.error', 'capsule.cancelled']

# Synonym keys for settings search: e(..., syn: "syn.x").
SYNONYM = re.compile(r'syn: "([^"]+)"')
LITERAL = re.compile(r'tr\("((?:[^"\\]|\\\([^)]*\))*)"')
SPEC = re.compile(r'%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:l|ll|h)?[@dDuUxXoOfeEgGcCsSpaA]')


def required_keys():
    keys = set(EXTRA)
    for path in SOURCES.rglob('*.swift'):
        for raw in LITERAL.findall(path.read_text()):
            if '\\(' not in raw:
                keys.add(raw)
                continue
            prefix = raw.split('.')[0]
            values = DYNAMIC.get(prefix)
            if values is None:
                print(f'unexpanded dynamic key: {raw} in {path.name}')
                continue
            for value in values:
                keys.add(re.sub(r'\\\([^)]*\)', value, raw))
        keys.update(SYNONYM.findall(path.read_text()))
    return keys


def parse(path):
    text = path.read_text(encoding='utf-8')
    pairs = re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', text, flags=re.M)
    table = {}
    for key, value in pairs:
        if key in table:
            print(f'{path.parent.name}: duplicate key {key}')
        table[key] = value
    return table


def specs(value):
    found = SPEC.findall(value)
    # Normalise positional and plain forms so "%@ %ld" equals "%1$@ %2$ld".
    plain = [re.sub(r'\d+\$', '', s) for s in found]
    positional = all('$' in s for s in found) and found
    if positional:
        order = sorted(found, key=lambda s: int(s[1:s.index('$')]))
        plain = [re.sub(r'\d+\$', '', s) for s in order]
    return plain


def main():
    keys = required_keys()
    problems = 0
    tables = {lang: parse(TABLES / f'{lang}.lproj' / 'Localizable.strings') for lang in LANGS}
    english = tables['en']
    for lang, table in tables.items():
        missing = sorted(keys - table.keys())
        unused = sorted(table.keys() - keys)
        for key in missing:
            print(f'{lang}: missing {key}')
        for key in unused:
            print(f'{lang}: unused {key}')
        problems += len(missing)
        for key in keys & table.keys():
            if lang != 'en' and specs(table[key]) != specs(english.get(key, '')):
                print(f'{lang}: format mismatch in {key}: {table[key]!r}')
                problems += 1
    print(f'{len(keys)} keys, {problems} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
