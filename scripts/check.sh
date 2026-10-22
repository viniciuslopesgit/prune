#!/bin/zsh
# Quality gate: everything that must pass before a commit or a deploy.
#
#   ./scripts/check.sh          quick (before each commit): scripts, secrets, translations, new tests,
#                               warning-free build, unit tests and minimum coverage
#   ./scripts/check.sh --full   all of the above plus (before push/deploy): version and CHANGELOG,
#                               universal, signed build/Prune.app, and the app's self-test
#
# --staged   checks what is in the git index (used by the pre-commit hook)
#
# When the full check passes, it saves the "fingerprint" of the tested tree in
# .build/check-passed: a commit/push of that same content does not run everything again.
set -e
cd "$(dirname "$0")/.."

FULL=0 STAGED=0
for a in "$@"; do
    case $a in
        --full) FULL=1 ;;
        --staged) STAGED=1 ;;
        *) echo "Unknown option: $a"; exit 2 ;;
    esac
done

# Minimum line coverage (%) in the files that delete or decide what gets deleted.
# Only goes up: lowering a value requires a justification in the commit.
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

# Files changed relative to HEAD (in the index with --staged; otherwise, also untracked ones).
changed() {
    if [ $STAGED = 1 ]; then
        git diff --cached --name-only --diff-filter="$1"
    else
        git diff HEAD --name-only --diff-filter="$1"
        if [[ "$1" == *A* ]]; then git ls-files --others --exclude-standard; fi
    fi
}

# Git tree of the current content, the same `git add -A` would give (without touching the real index).
# Starts from the index, not HEAD: a file removed with `git rm --cached` stays out.
worktree_hash() {
    local idx=$(mktemp)
    cp "$(git rev-parse --git-path index)" "$idx" 2>/dev/null || { rm -f "$idx"; GIT_INDEX_FILE=$idx git read-tree HEAD; }
    GIT_INDEX_FILE=$idx git add -A
    GIT_INDEX_FILE=$idx git write-tree
    rm -f "$idx"
}

START=$SECONDS
mkdir -p .build

step "Script syntax"
for f in scripts/*.sh .githooks/*(N); do
    zsh -n "$f" || fail "Syntax error in $f"
    [ -x "$f" ] || fail "$f is not executable (chmod +x $f)."
done
ok "scripts and hooks"

step "Script tests"
python3 -I -m unittest discover -s scripts/tests >.build/check-scripts.log 2>&1 \
    || { tail -30 .build/check-scripts.log; fail "The script tests failed."; }
ok "$(grep -oE '^Ran [0-9]+ tests' .build/check-scripts.log | sed 's/^Ran/passed:/') (scripts/tests)"

step "Secrets"
if git ls-files --error-unmatch analytics.env >/dev/null 2>&1 || git diff --cached --name-only | grep -qx analytics.env; then
    fail "analytics.env cannot go into the repository."
fi
if [ -f analytics.env ]; then
    # The real key values cannot appear in any file of the commit.
    for v in $(sed -n 's/^GA_[A-Z_]*=//p' analytics.env | tr -d "\"'"); do
        [ ${#v} -ge 6 ] || continue
        if [ $STAGED = 1 ]; then
            git diff --cached -U0 | grep -qF -- "$v" && fail "A key from analytics.env appears in the commit changes."
        else
            git grep -qF -- "$v" && fail "A key from analytics.env is in a file tracked by git."
            git diff HEAD | grep -qF -- "$v" && fail "A key from analytics.env appears in the changes."
        fi
    done
fi
/usr/libexec/PlistBuddy -c "Print :PruneGAAPISecret" Resources/Info.plist >/dev/null 2>&1 \
    && fail "Resources/Info.plist cannot have PruneGAAPISecret (it is injected at build time)."
ok "no keys in the changes"

step "Translations"
LOC=$(python3 -I scripts/check_localization.py 2>&1) || { print -r -- "$LOC" | head -30; fail "Texts without a translation, or translations no longer used (scripts/check_localization.py)."; }
ok "$LOC"

step "Tracked files"
IGNORED=$(git ls-files --cached --ignored --exclude-standard)
if [ -n "$IGNORED" ]; then
    print -r -- "$IGNORED" | sed 's/^/    /' | head -20
    fail "There are files tracked by git that .gitignore excludes (git rm --cached <file>)."
fi
ok "no ignored file tracked by git"

step "New features come with tests"
NEW_SOURCES=(${(f)"$(changed A | grep -E '^Sources/.*\.swift$' | sort -u)"})
if [ ${#NEW_SOURCES} -gt 0 ]; then
    TESTS_TOUCHED=$(changed AM | grep -cE '^Tests/.*\.swift$' || true)
    if [ "$TESTS_TOUCHED" = 0 ] && [ "$ALLOW_NO_TESTS" != 1 ]; then
        print "  New files without any new or changed test in Tests/:"
        for f in $NEW_SOURCES; do print "    $f"; done
        fail "Add tests in Tests/PruneTests (or, for interface-only code, ALLOW_NO_TESTS=1)."
    fi
    ok "${#NEW_SOURCES} new file(s), with tests"
else
    ok "no new files in Sources"
fi

step "Warning-free build"
if ! swift build -Xswiftc -warnings-as-errors >.build/check-build-debug.log 2>&1; then
    grep -E "(warning|error):" .build/check-build-debug.log | sort -u | head -30
    fail "The build failed or has warnings."
fi
ok "debug, warnings treated as errors"

step "Unit tests"
LOG=.build/check-tests.log
if ! ./scripts/test.sh --enable-code-coverage >$LOG 2>&1; then
    # ✘ is the failing test; ↳ are its comments (e.g. the cause recorded by the test itself).
    grep -E "✘|↳|error:" $LOG | grep -vE "^✘ Suite|↳ (Testing Library|Target Platform)" | head -40
    fail "Some tests are failing (full log in $LOG)."
fi
ok "$(grep -oE 'Test run with [0-9]+ tests in [0-9]+ suites' $LOG | sed 's/Test run with/passed:/')"
# Skipped tests are not failures, but they are not evidence either: always show them, with the reason.
SKIPPED=$(grep -E 'Test .* skipped' $LOG | sed -E 's/^[^T]*Test /Test /' || true)
if [ -n "$SKIPPED" ]; then
    print -P "%F{yellow}  ⚠ skipped on this machine:%f"
    print -r -- "$SKIPPED" | sed 's/^/      /'
fi

step "Minimum coverage"
BIN=$(swift build --show-bin-path)
REPORT=$(xcrun llvm-cov report "$BIN/PrunePackageTests.xctest/Contents/MacOS/PrunePackageTests" \
    -instr-profile "$BIN/codecov/default.profdata" -ignore-filename-regex='Tests/|\.build/')
LOW=0
# Without an inference context (some virtual machines) the similar-photos test is skipped, and with it
# the clustering code: only then, and only for that file, the minimum is lower. It is always reported.
if print -r -- "$SKIPPED" | grep -q "Vision unavailable on this machine"; then
    MIN_COVERAGE[Features/Duplicates/DuplicateFinder.swift]=80
    print -P "%F{yellow}  ⚠ Vision unavailable: minimum for DuplicateFinder.swift lowered to 80%% on this machine%f"
fi
for file min in ${(kv)MIN_COVERAGE}; do
    pct=$(print -r -- "$REPORT" | awk -v f="$file" '$1 == f { gsub("%", "", $10); print $10 }')
    if [ -z "$pct" ]; then
        print -P "%F{red}    $file is not in the coverage report%f"; LOW=1
    elif (( pct < min )); then
        print -P "%F{red}    $file: $pct% (minimum $min%)%f"; LOW=1
    fi
done
[ $LOW = 0 ] || fail "Coverage below the minimum."
ok "${#MIN_COVERAGE} critical files above the minimum"

if [ $FULL = 1 ]; then
    step "Version and CHANGELOG"
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
    BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Resources/Info.plist)
    [[ $VERSION =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail "CFBundleShortVersionString \"$VERSION\" is not X.Y.Z."
    [[ $BUILD =~ '^[0-9]+$' ]] || fail "CFBundleVersion \"$BUILD\" is not a number."
    grep -q "^## \[$VERSION\]" CHANGELOG.md || fail "The CHANGELOG has no ## [$VERSION] section."
    NOTES=$(./scripts/release_notes.sh "$VERSION") || fail "Could not generate the Release notes."
    SECTION=$(awk -v v="## [$VERSION]" 'index($0, v) == 1 { on = 1; next } /^## \[|^\[[0-9]/ { on = 0 } on' CHANGELOG.md)
    print -r -- "$SECTION" | grep -qE 'RELEASE SUMMARY|^- *$' && fail "The ## [$VERSION] section of the CHANGELOG is not filled in."
    print -r -- "$SECTION" | grep -qE '^- .+' || fail "The ## [$VERSION] section of the CHANGELOG lists no changes."
    plutil -lint -s Resources/Info.plist || fail "Resources/Info.plist is invalid."
    ok "$VERSION ($BUILD) in the CHANGELOG"

    step "Build build/Prune.app"
    ./scripts/build_app.sh >.build/check-build.log 2>&1 || { tail -30 .build/check-build.log; fail "build_app.sh failed."; }
    APP=build/Prune.app
    ARCHS=$(lipo -archs $APP/Contents/MacOS/Prune)
    [[ $ARCHS == *arm64* && $ARCHS == *x86_64* ]] || fail "The binary is not universal ($ARCHS)."
    codesign --verify --deep --strict $APP 2>/dev/null || fail "Invalid signature."
    [ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' $APP/Contents/Info.plist)" = "$VERSION" ] \
        || fail "The built app's version is not $VERSION."
    ok "universal ($ARCHS), signed, version $VERSION"

    step "Self-test of the built app"
    # Runs every scan of the real app, read-only. The output stays in .build (it has names of
    # apps and files on this Mac) and only the check lines show here.
    OUT=.build/check-selftest.log
    perl -e 'alarm shift; exec @ARGV' 300 $APP/Contents/MacOS/Prune --selftest >$OUT 2>&1 \
        || { tail -20 $OUT; fail "The self-test failed, hung or took more than 5 min."; }
    for expected in \
        "AppleScript in process: ok=true lines=2" \
        "Treemap: total area 240000" \
        "Versions: true false false" \
        "SafetyGuard blocks critical folders: true" \
        "SafetyGuard resolves links (/var/db → /private/var/db): true" \
        "Shredder does not follow symbolic links: true"; do
        grep -qF -- "$expected" $OUT || fail "Self-test: missing \"$expected\" (see $OUT)."
    done
    ok "every scan ran; 6 checks correct"

    worktree_hash >.build/check-passed
fi

KIND=quick; [ $FULL = 1 ] && KIND=full
print -P "%F{green}%B✓ $KIND check passed in $((SECONDS - START)) s.%b%f"
