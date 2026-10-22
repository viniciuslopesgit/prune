#!/bin/zsh
# Qual é a versão estável que deve estar no main (regras em scripts/stable.py).
#
#   ./scripts/stable.sh            relatório: estado de cada versão publicada e a candidata
#   ./scripts/stable.sh --apply    se houver candidata: volta a correr a verificação completa numa
#                                  cópia limpa do commit da tag e promove-a para o main por Pull Request
#   ./scripts/stable.sh --check 1.2.6   só a verificação completa dessa versão, numa cópia limpa
#
# STABLE_SOAK_HOURS=24  horas de observação depois de publicada (predefinição: 24).
set -e
cd "$(dirname "$0")/.."

APPLY=0 CHECK=""
while [ $# -gt 0 ]; do
    case $1 in
        --apply) APPLY=1 ;;
        --check) CHECK=${2#v}; shift ;;
        *) echo "Opção desconhecida: $1"; exit 2 ;;
    esac
    shift
done

gh auth status >/dev/null 2>&1 || { echo "✗ O gh não tem sessão iniciada no GitHub (gh auth login)."; exit 1; }
if [ -n "$CHECK" ]; then
    CANDIDATE=$CHECK
    git rev-parse -q --verify "refs/tags/v$CANDIDATE" >/dev/null || { echo "✗ Não há a tag v$CANDIDATE."; exit 1; }
else
    python3 -I scripts/stable.py
    [ $APPLY = 1 ] || exit 0
    CANDIDATE=$(python3 -I scripts/stable.py --json | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["candidate"] or "")')
    [ -n "$CANDIDATE" ] || { echo "• Nada a promover."; exit 0; }
fi
TAG=v$CANDIDATE
SHA=$(git rev-parse "refs/tags/$TAG^{commit}")
TREE=$(git rev-parse "refs/tags/$TAG^{tree}")
git cat-file -e "${SHA}:scripts/check.sh" 2>/dev/null \
    || { echo "✗ A $CANDIDATE é anterior ao sistema de testes: não pode ser verificada nem promovida automaticamente."; exit 1; }

# 1. Verificação completa do commit exato da tag, numa cópia limpa (sem alterações locais nem caches).
WT=$(mktemp -d)/prune-$CANDIDATE
trap 'git worktree remove --force "$WT" 2>/dev/null; true' EXIT
git worktree add -q --detach "$WT" "$SHA"
echo "• A verificar a $CANDIDATE numa cópia limpa (compila tudo de raiz; alguns minutos)…"
if ! (cd "$WT" && ./scripts/check.sh --full >"$WT.log" 2>&1); then
    tail -25 "$WT.log"
    echo "✗ A $CANDIDATE falhou a verificação completa: não é promovida (registo em $WT.log)."
    exit 1
fi
echo "✓ A $CANDIDATE passou a verificação completa."
[ -n "$CHECK" ] && exit 0
mkdir -p .build
print -r -- "$TREE" >.build/stable-verified   # o hook pre-push só deixa enviar para o main esta árvore

# 2. Promoção por Pull Request para o main, com merge (como as anteriores).
BRANCH=stable/$TAG
git push -q -f origin "${SHA}:refs/heads/${BRANCH}"
NOTES="Promove a **Prune $CANDIDATE** a versão estável.

$(python3 -I scripts/stable.py | sed 's/^/    /')

Verificada de novo numa cópia limpa do commit da tag \`$TAG\` (\`./scripts/check.sh --full\`)."
URL=$(gh pr create --base main --head "$BRANCH" --title "Versão estável: Prune $CANDIDATE" --body "$NOTES")
echo "✓ Pull Request: $URL"
gh pr merge "$URL" --merge --delete-branch
git fetch -q origin main
if git diff --quiet "refs/tags/$TAG" origin/main; then
    echo "✓ O main tem agora a Prune $CANDIDATE (conteúdo igual ao da tag $TAG)."
else
    echo "⚠️  O main foi atualizado, mas o conteúdo difere da tag $TAG: reveja com git diff $TAG origin/main."
    exit 1
fi
