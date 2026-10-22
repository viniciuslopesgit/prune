#!/bin/zsh
# Corre os testes de unidade (Tests/PruneTests). Argumentos extra vão para `swift test`
# (ex.: ./scripts/test.sh --filter ShredderTests).
set -e
cd "$(dirname "$0")/.."

# Só com as Command Line Tools (sem Xcode), o Swift Testing existe mas não está no caminho de pesquisa.
FLAGS=()
if [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
    DEV=/Library/Developer/CommandLineTools/Library/Developer
    FLAGS=(-Xswiftc -F -Xswiftc "$DEV/Frameworks"
           -Xlinker -F -Xlinker "$DEV/Frameworks"
           -Xlinker -rpath -Xlinker "$DEV/Frameworks"
           -Xlinker -rpath -Xlinker "$DEV/usr/lib")
fi

# Em série: alguns testes mexem nas Definições partilhadas (pastas ignoradas).
swift test --no-parallel "${FLAGS[@]}" "$@"
