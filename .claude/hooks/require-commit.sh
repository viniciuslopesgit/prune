#!/bin/zsh
# Hook Stop do Claude Code: não deixa o Claude terminar com alterações por registar.
# Regra do projeto (CLAUDE.md): testes rigorosos e, se passarem, commit automático.
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" || exit 0
INPUT=$(cat)
# Se já foi bloqueado uma vez nesta resposta (ex.: testes a falhar), deixa terminar para não ficar em ciclo.
[ "$(print -r -- "$INPUT" | jq -r '.stop_hook_active // false')" = true ] && exit 0
CHANGES=$(git status --porcelain 2>/dev/null)
git fetch -q origin dev 2>/dev/null
UNPUSHED=$(git log --oneline origin/dev..dev 2>/dev/null)
[ -z "$CHANGES" ] && [ -z "$UNPUSHED" ] && exit 0
REASON="Há trabalho por publicar no Prune (regra obrigatória do CLAUDE.md). Sobe a versão (./scripts/bump_version.sh patch|minor|major), preenche a secção dela no CHANGELOG e corre ./scripts/ship.sh \"<mensagem descritiva>\": testes rigorosos → commit → push para o dev → Release. Se os testes falharem, corrige e repete; nunca --no-verify. Se não conseguires resolver, explica ao utilizador o que falhou.
Alterações por registar:
${CHANGES:-(nenhuma)}
Commits por enviar para origin/dev:
${UNPUSHED:-(nenhum)}"
jq -n --arg r "$REASON" '{decision: "block", reason: $r}'
