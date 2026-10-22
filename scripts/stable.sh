#!/bin/zsh
# Qual é a versão estável que deve estar no main (regras em scripts/stable.py) e promoção para lá.
#
#   ./scripts/stable.sh                 relatório: estado de cada versão publicada e a candidata
#   ./scripts/stable.sh --apply         promove a candidata para o main; sem candidata, limpa o main
#                                       se tiver ficheiros a mais (ex.: um Pull Request do dev feito à mão)
#   ./scripts/stable.sh --check 1.2.6   só a verificação completa dessa versão, numa cópia limpa
#   ./scripts/stable.sh --dry-run 1.2.9 ensaia a promoção dessa versão (verificações incluídas), sem enviar nada
#
# O main não recebe o histórico do dev: cada versão estável é um commit "Prune X.Y.Z (versão estável)"
# com o conteúdo da tag vX.Y.Z sem os ficheiros de desenvolvimento (.mainignore), por Pull Request.
# Antes, a tag passa a verificação completa numa cópia limpa e o conteúdo do main compila e passa o autoteste.
#
# STABLE_SOAK_HOURS=24  horas de observação depois de publicada (predefinição: 24).
set -e
cd "$(dirname "$0")/.."

APPLY=0 CHECK="" DRY=""
while [ $# -gt 0 ]; do
    case $1 in
        --apply) APPLY=1 ;;
        --check) CHECK=${2#v}; shift ;;
        --dry-run) DRY=${2#v}; shift ;;
        *) echo "Opção desconhecida: $1"; exit 2 ;;
    esac
    shift
done

gh auth status >/dev/null 2>&1 || { echo "✗ O gh não tem sessão iniciada no GitHub (gh auth login)."; exit 1; }

TMP=$(mktemp -d)
WORKTREES=()
cleanup() {
    for w in $WORKTREES; do git worktree remove --force "$w" 2>/dev/null; done
    true
}
trap cleanup EXIT

json() { python3 -I -c "import json,sys; print(json.load(sys.stdin)[\"$1\"] or '')"; }

# Verificação completa do commit exato da tag, numa cópia limpa (sem alterações locais nem caches).
verify_tag() {
    local version=$1 sha=$(git rev-parse "refs/tags/v$1^{commit}")
    git cat-file -e "${sha}:scripts/check.sh" 2>/dev/null \
        || { echo "✗ A $version é anterior ao sistema de testes: não pode ser verificada automaticamente."; return 1; }
    local wt=$TMP/tag-$version
    git worktree add -q --detach "$wt" "$sha"; WORKTREES+=($wt)
    echo "• A verificar a $version numa cópia limpa (compila tudo de raiz; alguns minutos)…"
    if ! (cd "$wt" && ./scripts/check.sh --full >"$wt.log" 2>&1); then
        tail -25 "$wt.log"
        echo "✗ A $version falhou a verificação completa (registo em $wt.log)."
        return 1
    fi
    echo "✓ A $version passou a verificação completa."
}

# Árvore do main para uma versão: a da tag sem os caminhos do .mainignore (a lista em vigor no dev).
main_tree() {
    local tag=v$1 idx=$TMP/index-$1
    GIT_INDEX_FILE=$idx git read-tree "refs/tags/$tag"
    python3 -I scripts/stable.py excluded "refs/tags/$tag" >"$TMP/excluded-$1"
    if [ -s "$TMP/excluded-$1" ]; then
        GIT_INDEX_FILE=$idx git rm -r -q --cached --pathspec-from-file="$TMP/excluded-$1" >/dev/null
    fi
    GIT_INDEX_FILE=$idx git write-tree
}

# O conteúdo do main tem de compilar sozinho (sem testes nem scripts de desenvolvimento) e passar o autoteste.
verify_main_commit() {
    local version=$1 commit=$2 wt=$TMP/main-$1
    # Só podem faltar os ficheiros de desenvolvimento; nada mais pode ser diferente da tag.
    local other=$(git diff --name-status "refs/tags/v$version" "$commit" | grep -v '^D' || true)
    [ -z "$other" ] || { echo "✗ O commit do main difere da tag em mais do que os ficheiros de desenvolvimento:"; print -r -- "$other"; return 1; }
    git worktree add -q --detach "$wt" "$commit"; WORKTREES+=($wt)
    echo "• A compilar o conteúdo do main da $version (sem ficheiros de desenvolvimento)…"
    if ! (cd "$wt" && ./scripts/build_app.sh >"$wt.log" 2>&1); then
        tail -25 "$wt.log"; echo "✗ O conteúdo do main da $version não compila (registo em $wt.log)."; return 1
    fi
    local app=$wt/build/Prune.app out=$wt.selftest
    codesign --verify --deep --strict "$app" 2>/dev/null || { echo "✗ A app do main tem a assinatura inválida."; return 1; }
    perl -e 'alarm shift; exec @ARGV' 300 "$app/Contents/MacOS/Prune" --selftest >"$out" 2>&1 \
        || { tail -20 "$out"; echo "✗ O autoteste da app do main falhou."; return 1; }
    for expected in "Treemap: área total 240000" "SafetyGuard bloqueia pastas críticas: true" \
                    "SafetyGuard resolve ligações (/var/db → /private/var/db): true" \
                    "Destruidor não segue ligações simbólicas: true"; do
        grep -qF -- "$expected" "$out" || { echo "✗ Autoteste do main: falta \"$expected\" (ver $out)."; return 1; }
    done
    echo "✓ O conteúdo do main compila, está assinado e passa o autoteste."
}

# Leva a versão para o main por Pull Request. $2 descreve o motivo. Com --dry-run, para antes de enviar.
promote() {
    local version=$1 why=$2 tag=v$1
    git fetch -q origin main
    local tree=$(main_tree "$version")
    if [ "$tree" = "$(git rev-parse 'origin/main^{tree}')" ]; then
        echo "• O main já tem a $version só com os ficheiros essenciais."; return 0
    fi
    verify_tag "$version"
    local commit=$(printf 'Prune %s (versão estável)\n\n%s\nConteúdo da tag %s do dev, sem os ficheiros de desenvolvimento (.mainignore).\n' \
        "$version" "$why" "$tag" | git commit-tree "$tree" -p origin/main)
    verify_main_commit "$version" "$commit"
    if [ -n "$DRY" ]; then
        echo "✓ Ensaio: o commit $commit seria enviado para o main ($(wc -l <"$TMP/excluded-$version" | tr -d ' ') ficheiros de desenvolvimento retirados)."
        git ls-tree -r --name-only "$commit" >"$TMP/main-files"
        echo "  Ficheiros no main: $(wc -l <"$TMP/main-files" | tr -d ' ') (lista em $TMP/main-files)"
        return 0
    fi

    mkdir -p .build
    print -r -- "$tree" >.build/stable-verified   # o hook pre-push só deixa enviar para o main esta árvore
    local branch=stable/$tag
    git push -q -f origin "${commit}:refs/heads/${branch}"
    local removed=$(wc -l <"$TMP/excluded-$version" | tr -d ' ')
    local body="$why

- Conteúdo da tag \`$tag\`, sem $removed ficheiros de desenvolvimento (lista em \`.mainignore\` no dev).
- A tag passou \`./scripts/check.sh --full\` numa cópia limpa; o conteúdo do main compila, está assinado e passa o autoteste.

$(python3 -I scripts/stable.py | sed 's/^/    /')"
    local url=$(gh pr create --base main --head "$branch" --title "Versão estável: Prune $version" --body "$body")
    echo "✓ Pull Request: $url"
    gh pr merge "$url" --merge --delete-branch
    git fetch -q origin main
    if [ "$(git rev-parse 'origin/main^{tree}')" = "$tree" ]; then
        echo "✓ O main tem agora a Prune $version, só com os ficheiros essenciais."
        # A Release deixa de ser beta e passa a ser a "Latest" (a que o README manda descarregar).
        gh release edit "$tag" --prerelease=false --latest >/dev/null
        echo "✓ Release $tag marcada como estável (Latest)."
    else
        echo "⚠️  O main foi atualizado, mas o conteúdo não é o esperado: reveja com git diff $commit origin/main."
        return 1
    fi
}

if [ -n "$DRY" ]; then
    git rev-parse -q --verify "refs/tags/v$DRY" >/dev/null || { echo "✗ Não há a tag v$DRY."; exit 1; }
    promote "$DRY" "Ensaio da promoção da **Prune $DRY**."
    exit 0
fi

if [ -n "$CHECK" ]; then
    git rev-parse -q --verify "refs/tags/v$CHECK" >/dev/null || { echo "✗ Não há a tag v$CHECK."; exit 1; }
    verify_tag "$CHECK"
    exit 0
fi

python3 -I scripts/stable.py
[ $APPLY = 1 ] || exit 0

REPORT=$(python3 -I scripts/stable.py --json)
CANDIDATE=$(print -r -- "$REPORT" | json candidate)
MAIN=$(print -r -- "$REPORT" | json main)
if [ -n "$CANDIDATE" ]; then
    promote "$CANDIDATE" "Promove a **Prune $CANDIDATE** a versão estável."
elif [ -n "$MAIN" ] && git cat-file -e "refs/tags/v${MAIN}:.mainignore" 2>/dev/null; then
    # Sem versão nova: confirma que o main tem só os ficheiros essenciais da versão que já lá está.
    promote "$MAIN" "Limpa o main: mantém a **Prune $MAIN**, só com os ficheiros essenciais para a compilar."
elif [ -n "$MAIN" ]; then
    echo "• Nada a promover. A $MAIN no main é anterior ao main só com ficheiros essenciais:"
    echo "  o main fica limpo quando a próxima versão estável for promovida."
else
    echo "• Nada a promover."
fi
