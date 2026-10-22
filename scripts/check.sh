#!/bin/zsh
# Portão de qualidade: tudo o que tem de passar antes de um commit ou de um deploy.
#
#   ./scripts/check.sh          rápido (antes de cada commit): scripts, segredos, testes novos,
#                               compilação sem avisos, testes de unidade e cobertura mínima
#   ./scripts/check.sh --full   tudo o anterior e ainda (antes de push/deploy): versão e CHANGELOG,
#                               build/Prune.app universal e assinado, e o autoteste da app
#
# --staged   verifica o que está no índice do git (usado pelo hook pre-commit)
#
# Quando a verificação completa passa, guarda a "impressão digital" da árvore testada em
# .build/check-passed: um commit/push desse mesmo conteúdo não volta a correr tudo.
set -e
cd "$(dirname "$0")/.."

FULL=0 STAGED=0
for a in "$@"; do
    case $a in
        --full) FULL=1 ;;
        --staged) STAGED=1 ;;
        *) echo "Opção desconhecida: $a"; exit 2 ;;
    esac
done

# Cobertura mínima de linhas (%) nos ficheiros que apagam ou decidem o que se apaga.
# Só se sobe: baixar um valor exige justificação no commit.
typeset -A MIN_COVERAGE=(
    Core/SafetyGuard.swift 95
    Features/Shredder/Shredder.swift 95
    Core/Cleaning/Cleaner.swift 75
    Core/Cleaning/CleanItem.swift 90
    Core/FileSystem.swift 70
    Features/Duplicates/DuplicateFinder.swift 85
    Features/SpaceLens/SpaceScanner.swift 85
    Core/Formatting.swift 75
    Core/LaunchItemParser.swift 100
)

STEP=0
step() { STEP=$((STEP + 1)); print -P "%B[$STEP] $1%b"; }
fail() { print -P "%F{red}✗ $1%f"; exit 1; }
ok() { print -P "%F{green}  ✓ $1%f"; }

# Ficheiros alterados em relação ao HEAD (no índice com --staged; senão, também os não registados).
changed() {
    if [ $STAGED = 1 ]; then
        git diff --cached --name-only --diff-filter="$1"
    else
        git diff HEAD --name-only --diff-filter="$1"
        if [[ "$1" == *A* ]]; then git ls-files --others --exclude-standard; fi
    fi
}

# Árvore git do conteúdo atual (sem mexer no índice verdadeiro).
worktree_hash() {
    local idx=$(mktemp)
    rm -f "$idx"
    GIT_INDEX_FILE=$idx git read-tree HEAD
    GIT_INDEX_FILE=$idx git add -A
    GIT_INDEX_FILE=$idx git write-tree
    rm -f "$idx"
}

START=$SECONDS
mkdir -p .build

step "Sintaxe dos scripts"
for f in scripts/*.sh .githooks/*(N); do
    zsh -n "$f" || fail "Erro de sintaxe em $f"
    [ -x "$f" ] || fail "$f não é executável (chmod +x $f)."
done
ok "scripts e hooks"

step "Segredos"
if git ls-files --error-unmatch analytics.env >/dev/null 2>&1 || git diff --cached --name-only | grep -qx analytics.env; then
    fail "analytics.env não pode ir para o repositório."
fi
if [ -f analytics.env ]; then
    # Os valores reais das chaves não podem aparecer em nenhum ficheiro do commit.
    for v in $(sed -n 's/^GA_[A-Z_]*=//p' analytics.env | tr -d "\"'"); do
        [ ${#v} -ge 6 ] || continue
        if [ $STAGED = 1 ]; then
            git diff --cached -U0 | grep -qF -- "$v" && fail "Uma chave de analytics.env aparece nas alterações do commit."
        else
            git grep -qF -- "$v" && fail "Uma chave de analytics.env está num ficheiro registado no git."
            git diff HEAD | grep -qF -- "$v" && fail "Uma chave de analytics.env aparece nas alterações."
        fi
    done
fi
/usr/libexec/PlistBuddy -c "Print :PruneGAAPISecret" Resources/Info.plist >/dev/null 2>&1 \
    && fail "Resources/Info.plist não pode ter PruneGAAPISecret (é injetado no build)."
ok "nenhuma chave nas alterações"

step "Funcionalidades novas trazem testes"
NEW_SOURCES=(${(f)"$(changed A | grep -E '^Sources/.*\.swift$' | sort -u)"})
if [ ${#NEW_SOURCES} -gt 0 ]; then
    TESTS_TOUCHED=$(changed AM | grep -cE '^Tests/.*\.swift$' || true)
    if [ "$TESTS_TOUCHED" = 0 ] && [ "$ALLOW_NO_TESTS" != 1 ]; then
        print "  Ficheiros novos sem nenhum teste novo ou alterado em Tests/:"
        for f in $NEW_SOURCES; do print "    $f"; done
        fail "Acrescente testes em Tests/PruneTests (ou, só para código de interface, ALLOW_NO_TESTS=1)."
    fi
    ok "${#NEW_SOURCES} ficheiro(s) novo(s), com testes"
else
    ok "nenhum ficheiro novo em Sources"
fi

step "Compilação sem avisos"
if ! swift build -Xswiftc -warnings-as-errors >.build/check-build-debug.log 2>&1; then
    grep -E "(warning|error):" .build/check-build-debug.log | sort -u | head -30
    fail "A compilação falhou ou tem avisos."
fi
ok "debug, avisos tratados como erros"

step "Testes de unidade"
LOG=.build/check-tests.log
if ! ./scripts/test.sh --enable-code-coverage >$LOG 2>&1; then
    grep -E "✘|error:" $LOG | grep -v "^✘ Suite" | head -40
    fail "Há testes a falhar (registo completo em $LOG)."
fi
ok "$(grep -oE 'Test run with [0-9]+ tests in [0-9]+ suites' $LOG | sed 's/Test run with/passaram/; s/tests in/testes em/; s/suites/grupos/')"

step "Cobertura mínima"
BIN=$(swift build --show-bin-path)
REPORT=$(xcrun llvm-cov report "$BIN/PrunePackageTests.xctest/Contents/MacOS/PrunePackageTests" \
    -instr-profile "$BIN/codecov/default.profdata" -ignore-filename-regex='Tests/|\.build/')
LOW=0
for file min in ${(kv)MIN_COVERAGE}; do
    pct=$(print -r -- "$REPORT" | awk -v f="$file" '$1 == f { gsub("%", "", $10); print $10 }')
    if [ -z "$pct" ]; then
        print -P "%F{red}    $file não aparece no relatório de cobertura%f"; LOW=1
    elif (( pct < min )); then
        print -P "%F{red}    $file: $pct% (mínimo $min%)%f"; LOW=1
    fi
done
[ $LOW = 0 ] || fail "Cobertura abaixo do mínimo."
ok "${#MIN_COVERAGE} ficheiros críticos acima do mínimo"

if [ $FULL = 1 ]; then
    step "Versão e CHANGELOG"
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
    BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Resources/Info.plist)
    [[ $VERSION =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail "CFBundleShortVersionString \"$VERSION\" não é X.Y.Z."
    [[ $BUILD =~ '^[0-9]+$' ]] || fail "CFBundleVersion \"$BUILD\" não é um número."
    grep -q "^## \[$VERSION\]" CHANGELOG.md || fail "O CHANGELOG não tem a secção ## [$VERSION]."
    NOTES=$(./scripts/release_notes.sh "$VERSION") || fail "Não foi possível gerar as notas da Release."
    SECTION=$(awk -v v="## [$VERSION]" 'index($0, v) == 1 { on = 1; next } /^## \[|^\[[0-9]/ { on = 0 } on' CHANGELOG.md)
    print -r -- "$SECTION" | grep -qE 'RESUMO DA VERSÃO|^- *$' && fail "A secção ## [$VERSION] do CHANGELOG está por preencher."
    print -r -- "$SECTION" | grep -qE '^- .+' || fail "A secção ## [$VERSION] do CHANGELOG não tem nenhuma alteração listada."
    plutil -lint -s Resources/Info.plist || fail "Resources/Info.plist inválido."
    ok "$VERSION ($BUILD) no CHANGELOG"

    step "Compilar build/Prune.app"
    ./scripts/build_app.sh >.build/check-build.log 2>&1 || { tail -30 .build/check-build.log; fail "build_app.sh falhou."; }
    APP=build/Prune.app
    ARCHS=$(lipo -archs $APP/Contents/MacOS/Prune)
    [[ $ARCHS == *arm64* && $ARCHS == *x86_64* ]] || fail "O binário não é universal ($ARCHS)."
    codesign --verify --deep --strict $APP 2>/dev/null || fail "Assinatura inválida."
    [ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' $APP/Contents/Info.plist)" = "$VERSION" ] \
        || fail "A versão da app compilada não é $VERSION."
    ok "universal ($ARCHS), assinada, versão $VERSION"

    step "Autoteste da app compilada"
    # Corre todas as análises da app real, só em leitura. O resultado fica em .build (tem nomes de
    # apps e ficheiros deste Mac) e só as linhas de verificação aparecem aqui.
    OUT=.build/check-selftest.log
    perl -e 'alarm shift; exec @ARGV' 300 $APP/Contents/MacOS/Prune --selftest >$OUT 2>&1 \
        || { tail -20 $OUT; fail "O autoteste falhou, bloqueou ou excedeu 5 min."; }
    for expected in \
        "AppleScript em processo: ok=true linhas=2" \
        "Treemap: área total 240000" \
        "Versões: true false false" \
        "SafetyGuard bloqueia pastas críticas: true" \
        "SafetyGuard resolve ligações (/var/db → /private/var/db): true" \
        "Destruidor não segue ligações simbólicas: true"; do
        grep -qF -- "$expected" $OUT || fail "Autoteste: falta \"$expected\" (ver $OUT)."
    done
    ok "todas as análises correram; 6 verificações certas"

    worktree_hash >.build/check-passed
fi

KIND=rápida; [ $FULL = 1 ] && KIND=completa
print -P "%F{green}%B✓ Verificação $KIND passou em $((SECONDS - START)) s.%b%f"
