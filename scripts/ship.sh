#!/bin/zsh
# Testa, faz commit e instala, por esta ordem. Se um passo falhar, os seguintes não acontecem.
#
#   ./scripts/ship.sh "Mensagem do commit"          verificação completa → commit → /Applications
#   ./scripts/ship.sh "…" --dmg                     … e cria build/Prune-<versão>.dmg
#   ./scripts/ship.sh "…" --push                    … e envia o ramo atual para o GitHub
#   ./scripts/ship.sh "…" --no-install              não mexe em /Applications
#
# O commit inclui todas as alterações da pasta (git add -A), que são exatamente as que foram testadas.
set -e
cd "$(dirname "$0")/.."

MSG="" DMG=0 PUSH=0 INSTALL=1
for a in "$@"; do
    case $a in
        --dmg) DMG=1 ;;
        --push) PUSH=1 ;;
        --no-install) INSTALL=0 ;;
        -*) echo "Opção desconhecida: $a"; exit 2 ;;
        *) [ -z "$MSG" ] && MSG=$a || { echo "Só uma mensagem de commit, entre aspas."; exit 2; } ;;
    esac
done
[ -n "$MSG" ] || { echo "Uso: ./scripts/ship.sh \"Mensagem do commit\" [--dmg] [--push] [--no-install]"; exit 2; }

[ -z "$(git ls-files --unmerged)" ] || { echo "✗ Há conflitos por resolver."; exit 1; }
[ "$(git config core.hooksPath)" = ".githooks" ] || ./scripts/setup_hooks.sh

BRANCH=$(git branch --show-current)
echo "• Ramo: $BRANCH"

# 1. Testes. Nada é registado nem instalado se falharem.
./scripts/check.sh --full

# 2. Commit do conteúdo que acabou de ser testado.
git add -A
if [ "$(cat .build/check-passed)" != "$(git write-tree)" ]; then
    echo "✗ A pasta mudou durante a verificação. Volte a correr ./scripts/ship.sh."
    exit 1
fi
if git diff --cached --quiet; then
    echo "• Nada novo para registar; o último commit já é o que foi testado."
else
    git commit -q -m "$MSG"
    echo "✓ Commit $(git rev-parse --short HEAD): $MSG"
fi

# 3. Deploy: a app testada (build/Prune.app) vai para /Applications, sem recompilar.
if [ $INSTALL = 1 ]; then
    SKIP_BUILD=1 ./scripts/install.sh
fi
if [ $DMG = 1 ]; then
    SKIP_BUILD=1 ./scripts/make_dmg.sh
fi
if [ $PUSH = 1 ]; then
    git push -u origin "$BRANCH"
fi
echo "✓ Concluído."
