#!/bin/zsh
# Builds and installs/updates Prune in /Applications.
#
# Updates the app "in place" (replaces the contents of the existing bundle) instead of sending it to the
# Trash: when an app goes to the Trash, macOS removes its permissions (e.g. Full Disk Access).
# With the stable signature (setup_signing.sh) and this in-place update, permissions are kept
# between versions.
# SKIP_BUILD=1 installs the existing build/Prune.app.
set -e
cd "$(dirname "$0")/.."

[ "$SKIP_BUILD" = "1" ] || ./scripts/build_app.sh

SRC=build/Prune.app
DEST=/Applications/Prune.app

# Quits the app if it is open.
if pgrep -f "$DEST/Contents/MacOS/" >/dev/null; then
    pkill -TERM -f "$DEST/Contents/MacOS/" || true
    for i in {1..10}; do pgrep -f "$DEST/Contents/MacOS/" >/dev/null || break; sleep 0.5; done
fi

if [ -d "$DEST" ]; then
    # Replaces the contents while keeping the same bundle (without going through the Trash).
    rsync -a --delete "$SRC/" "$DEST/"
    echo "✓ Prune updated in $DEST"
else
    ditto "$SRC" "$DEST"
    echo "✓ Prune installed in $DEST"
fi

codesign --verify --deep --strict "$DEST"
# Gives macOS time to register the new version before opening it; if the app launches at the same
# moment as the replacement, it may not see Full Disk Access until it is reopened.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" 2>/dev/null || true
sleep 2
open "$DEST"
