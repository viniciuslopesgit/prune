#!/bin/zsh
# Bumps the version (patch, minor or major) in Info.plist and opens its section in the CHANGELOG.
#   ./scripts/bump_version.sh patch    1.2.5 → 1.2.6   fixes and internal changes
#   ./scripts/bump_version.sh minor    1.2.5 → 1.3.0   new features
#   ./scripts/bump_version.sh major    1.2.5 → 2.0.0   incompatible changes
# Then fill in the section in the CHANGELOG: a summary paragraph (goes at the top of the Release)
# and the ### Added / Changed / Fixed / Removed lists.
set -e
cd "$(dirname "$0")/.."

PLIST=Resources/Info.plist
OLD=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" $PLIST)
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" $PLIST)
parts=(${(s:.:)OLD})
case $1 in
    patch) NEW="$parts[1].$parts[2].$((parts[3] + 1))" ;;
    minor) NEW="$parts[1].$((parts[2] + 1)).0" ;;
    major) NEW="$((parts[1] + 1)).0.0" ;;
    *) echo "Usage: ./scripts/bump_version.sh patch|minor|major"; exit 2 ;;
esac
grep -q "^## \[$NEW\]" CHANGELOG.md && { echo "✗ The CHANGELOG already has a $NEW section."; exit 1; }

# sed instead of PlistBuddy, to keep the file's formatting (PlistBuddy rewrites all of it).
sed -i '' -e "s|<key>CFBundleShortVersionString</key><string>$OLD</string>|<key>CFBundleShortVersionString</key><string>$NEW</string>|" \
          -e "s|<key>CFBundleVersion</key><string>$BUILD</string>|<key>CFBundleVersion</key><string>$((BUILD + 1))</string>|" $PLIST
[ "$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" $PLIST)" = "$NEW" ] \
    && [ "$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" $PLIST)" = "$((BUILD + 1))" ] \
    || { echo "✗ Could not update the version in $PLIST."; exit 1; }

TODAY=$(date +%Y-%m-%d)
REPO=https://github.com/viniciuslopesgit/prune
python3 - "$NEW" "$TODAY" "$REPO" <<'PY'
import sys, re
new, today, repo = sys.argv[1:]
p = "CHANGELOG.md"
s = open(p, encoding="utf-8").read()
i = s.index("\n## [")
s = s[:i] + f"\n## [{new}] - {today}\n\nRELEASE SUMMARY\n\n### Changed\n- \n" + s[i:]
# Version link at the end of the file, before the others.
m = re.search(r"^\[\d", s, re.M)
link = f"[{new}]: {repo}/releases/tag/v{new}\n"
s = s[:m.start()] + link + s[m.start():] if m else s.rstrip() + "\n\n" + link
open(p, "w", encoding="utf-8").write(s)
PY
echo "✓ $OLD → $NEW (build $((BUILD + 1))). Fill in the ## [$NEW] section in CHANGELOG.md."
