#!/bin/zsh
# Hook Stop do Claude Code: não deixa o Claude terminar com alterações por registar.
# Regra do projeto (CLAUDE.md): testes rigorosos e, se passarem, commit automático.
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" || exit 0
INPUT=$(cat)
# Se já foi bloqueado uma vez nesta resposta (ex.: testes a falhar), deixa terminar para não ficar em ciclo.
[ "$(print -r -- "$INPUT" | jq -r '.stop_hook_active // false')" = true ] && exit 0
CHANGES=$(git status --porcelain 2>/dev/null)
[ -z "$CHANGES" ] && exit 0
REASON="Há alterações por registar no Prune (regra obrigatória do CLAUDE.md). Corre ./scripts/ship.sh \"<mensagem descritiva>\" --no-install: só faz commit se a verificação completa passar. Se falhar, corrige e repete; nunca --no-verify. Se não conseguires resolver, explica ao utilizador o que falhou. Alterações:
$CHANGES"
jq -n --arg r "$REASON" '{decision: "block", reason: $r}'
