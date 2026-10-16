#!/bin/zsh
# Runs every check CI runs, locally, before a pull request or a release:
# unit tests, release build of the app, string tables, Python syntax, shell syntax,
# workflow hygiene and a scan for secrets or personal paths in tracked files.
#
#   scripts/check.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

step() { print -P "%B==> $1%b" }

step "Unit tests"
swift test

step "App target builds (release)"
swift build -c release --product Saywell

step "Localization tables"
python3 -I scripts/check-localization.py

step "Python compiles"
python3 -I -m py_compile Resources/recognizer.py scripts/*.py

step "Shell scripts parse"
for f in scripts/*.sh; do zsh -n "$f"; done

step "Workflows pin actions to commits"
if grep -nE 'uses: [^ ]+@(v[0-9]+|main|master)\s*$' .github/workflows/*.yml; then
  print "Pin these actions to a commit SHA (Dependabot keeps them current)."; exit 1
fi

step "No secrets or personal paths in tracked or new files"
PATTERNS='sk-[A-Za-z0-9_-]{20,}|sk-proj-|ghp_[A-Za-z0-9]{30,}|github_pat_|xox[bap]-|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|/Users/[a-z][a-z0-9_-]+/'
if git ls-files -z --cached --others --exclude-standard | xargs -0 grep -nIE "$PATTERNS" -- 2>/dev/null | grep -vE '^(scripts/check\.sh|\.github/workflows/ci\.yml|CONTINUATION\.md):'; then
  print "Remove the matches above before committing."; exit 1
fi

step "All checks passed"
