#!/bin/zsh
# Tests, commits, pushes to dev and publishes the Release, in this order.
# If a step fails, the following ones do not happen.
#
#   ./scripts/ship.sh "Commit message"     full check → commit → push dev → beta Release
#   ./scripts/ship.sh "…" --install        … and installs the app in /Applications
#   ./scripts/ship.sh "…" --no-release     commit and push only (no new version)
#   ./scripts/ship.sh "…" --no-promote     does not promote the stable version to main
#
# At the end, if there is a stable version newer than main's (rules in scripts/stable.py),
# it is verified again in a clean copy and promoted to main through a Pull Request.
#
# Each Release needs a new version: first, ./scripts/bump_version.sh patch|minor|major
# and fill in its section in the CHANGELOG. The vX.Y.Z tag points to the commit tested on dev.
# The commit includes every change in the folder (git add -A), which are exactly the ones that were tested.
set -e
cd "$(dirname "$0")/.."

MSG="" RELEASE=1 INSTALL=0 PROMOTE=1
for a in "$@"; do
    case $a in
        --install) INSTALL=1 ;;
        --no-release) RELEASE=0 ;;
        --no-promote) PROMOTE=0 ;;
        --no-install) ;;   # default; accepted for compatibility
        -*) echo "Unknown option: $a"; exit 2 ;;
        *) [ -z "$MSG" ] && MSG=$a || { echo "Only one commit message, in quotes."; exit 2; } ;;
    esac
done
[ -n "$MSG" ] || { echo "Usage: ./scripts/ship.sh \"Commit message\" [--install] [--no-release] [--no-promote]"; exit 2; }

BRANCH=$(git branch --show-current)
[ "$BRANCH" = dev ] || { echo "✗ ship.sh publishes from the dev branch (you are on \"$BRANCH\")."; exit 1; }
[ -z "$(git ls-files --unmerged)" ] || { echo "✗ There are unresolved conflicts."; exit 1; }
[ "$(git config core.hooksPath)" = ".githooks" ] || ./scripts/setup_hooks.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
TAG=v$VERSION
if [ $RELEASE = 1 ]; then
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
        echo "✗ Version $VERSION has already been published. Bump the version: ./scripts/bump_version.sh patch|minor|major"
        echo "  and fill in its section in the CHANGELOG (or use --no-release)."
        exit 1
    fi
    gh auth status >/dev/null 2>&1 || { echo "✗ gh is not signed in to GitHub (gh auth login)."; exit 1; }
fi
echo "• Branch: dev · version $VERSION"

# 1. Tests. Nothing is committed, pushed or published if they fail.
./scripts/check.sh --full

# 2. Commit of the content that was just tested.
git add -A
if [ "$(cat .build/check-passed)" != "$(git write-tree)" ]; then
    echo "✗ The folder changed during the check. Run ./scripts/ship.sh again."
    exit 1
fi
if git diff --cached --quiet; then
    echo "• Nothing new to commit; the last commit is already the one that was tested."
else
    git commit -q -m "$MSG"
    echo "✓ Commit $(git rev-parse --short HEAD): ${MSG%%$'\n'*}"
fi

# 3. Push to dev (the pre-push hook confirms it is the tested content).
git push -q -u origin dev
echo "✓ Pushed to origin/dev"

# 4. Release: DMG of the tested app, tag on the pushed commit and publication on GitHub.
if [ $RELEASE = 1 ]; then
    SKIP_BUILD=1 ./scripts/make_dmg.sh
    DMG=build/Prune-$VERSION.dmg
    [ -f "$DMG" ] || { echo "✗ $DMG was not created."; exit 1; }
    # DMG checksum, so people who download it can confirm the file was not altered.
    SUMS=build/SHA256SUMS
    (cd build && shasum -a 256 "Prune-$VERSION.dmg") >"$SUMS"
    NOTES=$(mktemp)
    ./scripts/release_notes.sh "$VERSION" --beta >"$NOTES"
    git tag -a "$TAG" -m "Prune $VERSION"
    git push -q origin "$TAG"
    # Published as a pre-release (beta): only becomes "Latest" when stable.sh promotes it to stable.
    gh release create "$TAG" "$DMG" "$SUMS" --title "Prune $VERSION" --notes-file "$NOTES" --verify-tag --prerelease
    rm -f "$NOTES"
    echo "✓ Release Prune $VERSION published as beta: $(gh release view "$TAG" --json url --jq .url)"
fi

# 5. Stable version to main: if there is a candidate, it is verified in a clean copy and promoted
#    through a Pull Request (scripts/stable.sh --apply). dev and the Release are already published by now.
if [ $PROMOTE = 1 ]; then
    echo "• Stable version to main:"
    if ! ./scripts/stable.sh --apply; then
        echo "✗ The promotion to main failed (the commit, the push to dev and the Release are already done)."
        exit 1
    fi
fi

# 6. Optional: installs the tested app in /Applications, without rebuilding.
if [ $INSTALL = 1 ]; then
    SKIP_BUILD=1 ./scripts/install.sh
fi
echo "✓ Done."
