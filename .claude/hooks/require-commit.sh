#!/bin/zsh
# Claude Code Stop hook: does not let Claude finish with uncommitted changes.
# Project rule (CLAUDE.md): rigorous tests and, if they pass, automatic commit.
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" || exit 0
INPUT=$(cat)
# If it was already blocked once in this answer (e.g. failing tests), lets it finish to avoid a loop.
[ "$(print -r -- "$INPUT" | jq -r '.stop_hook_active // false')" = true ] && exit 0
CHANGES=$(git status --porcelain 2>/dev/null)
git fetch -q origin dev 2>/dev/null
UNPUSHED=$(git log --oneline origin/dev..dev 2>/dev/null)
[ -z "$CHANGES" ] && [ -z "$UNPUSHED" ] && exit 0
REASON="There is unpublished work in Prune (mandatory rule in CLAUDE.md). Bump the version (./scripts/bump_version.sh patch|minor|major), fill in its section in the CHANGELOG and run ./scripts/ship.sh \"<descriptive message>\": rigorous tests → commit → push to dev → Release. If the tests fail, fix and repeat; never --no-verify. If you cannot solve it, explain to the user what failed.
Uncommitted changes:
${CHANGES:-(none)}
Commits not yet pushed to origin/dev:
${UNPUSHED:-(none)}"
jq -n --arg r "$REASON" '{decision: "block", reason: $r}'
