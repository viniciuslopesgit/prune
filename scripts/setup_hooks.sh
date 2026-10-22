#!/bin/zsh
# Liga os hooks do repositório (.githooks): verificação rápida antes de cada commit e
# completa antes de cada push. Corre-se uma vez por clone.
set -e
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
echo "✓ Hooks ativos: pre-commit (./scripts/check.sh) e pre-push (./scripts/check.sh --full)."
