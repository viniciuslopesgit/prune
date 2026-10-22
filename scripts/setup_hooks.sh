#!/bin/zsh
# Turns on the repository hooks (.githooks): quick check before each commit and
# full check before each push. Run it once per clone.
set -e
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
echo "✓ Hooks on: pre-commit (./scripts/check.sh) and pre-push (./scripts/check.sh --full)."
