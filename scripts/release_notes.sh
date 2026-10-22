#!/bin/zsh
# Writes a version's Release notes from its section in the CHANGELOG:
# summary, installation instructions, the version's lists and the link to the history.
#   ./scripts/release_notes.sh 1.2.6 [--beta]
set -e
cd "$(dirname "$0")/.."
VERSION=${1:-$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)}
python3 - "$VERSION" "${2:-}" <<'PY'
import sys, re
v, beta = sys.argv[1], sys.argv[2] == "--beta"
s = open("CHANGELOG.md", encoding="utf-8").read()
m = re.search(rf"^## \[{re.escape(v)}\][^\n]*\n(.*?)(?=^## \[|^\[\d)", s, re.M | re.S)
if not m:
    sys.exit(f"The CHANGELOG has no ## [{v}] section.")
body = m.group(1).strip()
cut = body.find("### ")
summary, lists = (body[:cut], body[cut:]) if cut >= 0 else (body, "")
if beta:
    print("> **Beta.** Becomes stable once it meets the [stability criteria](https://github.com/viniciuslopesgit/prune/blob/dev/docs/RELEASE_CRITERIA.md). "
          "For everyday use, prefer the [latest stable version](https://github.com/viniciuslopesgit/prune/releases/latest).")
    print()
print(summary.strip())
print(f"""
## Install

1. Download **Prune-{v}.dmg** (under *Assets*) and drag Prune to **Applications**.
2. On first launch, allow it in *System Settings ▸ Privacy & Security ▸ Open Anyway*, or in Terminal:
   `xattr -dr com.apple.quarantine /Applications/Prune.app`
3. Follow the Full Disk Access assistant.

Verify the file: `shasum -a 256 -c SHA256SUMS` in the folder where you downloaded both files.

macOS 14 or later · Apple silicon and Intel. The interface follows the system language (English or Portuguese).
""")
if lists:
    print(re.sub(r"^### ", "## ", lists.strip(), flags=re.M))
    print()
print("Full history in the [CHANGELOG](https://github.com/viniciuslopesgit/prune/blob/dev/CHANGELOG.md).")
PY
