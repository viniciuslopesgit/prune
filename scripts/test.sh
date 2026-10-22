#!/bin/zsh
# Runs the unit tests (Tests/PruneTests). Extra arguments go to `swift test`
# (e.g. ./scripts/test.sh --filter ShredderTests).
set -e
cd "$(dirname "$0")/.."

# With only the Command Line Tools (no Xcode), Swift Testing exists but is not on the search path.
FLAGS=()
if [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
    DEV=/Library/Developer/CommandLineTools/Library/Developer
    FLAGS=(-Xswiftc -F -Xswiftc "$DEV/Frameworks"
           -Xlinker -F -Xlinker "$DEV/Frameworks"
           -Xlinker -rpath -Xlinker "$DEV/Frameworks"
           -Xlinker -rpath -Xlinker "$DEV/usr/lib")
fi

# Serially: some tests change the shared Settings (ignored folders).
swift test --no-parallel "${FLAGS[@]}" "$@"
