#!/bin/zsh
# Testa, faz commit, envia para o dev e publica a Release, por esta ordem.
# Se um passo falhar, os seguintes não acontecem.
#
#   ./scripts/ship.sh "Mensagem do commit"     verificação completa → commit → push dev → Release
#   ./scripts/ship.sh "…" --install            … e instala a app em /Applications
#   ./scripts/ship.sh "…" --no-release         só commit e push (sem versão nova)
#   ./scripts/ship.sh "…" --no-promote         não promove a versão estável para o main
#
# No fim, se houver uma versão estável mais nova do que a do main (regras em scripts/stable.py),
# é verificada de novo numa cópia limpa e promovida para o main por Pull Request.
#
# Cada Release precisa de uma versão nova: antes, ./scripts/bump_version.sh patch|minor|major
# e preencher a secção dela no CHANGELOG. A tag vX.Y.Z aponta para o commit testado no dev.
# O commit inclui todas as alterações da pasta (git add -A), que são exatamente as que foram testadas.
set -e
cd "$(dirname "$0")/.."

MSG="" RELEASE=1 INSTALL=0 PROMOTE=1
for a in "$@"; do
    case $a in
        --install) INSTALL=1 ;;
        --no-release) RELEASE=0 ;;
        --no-promote) PROMOTE=0 ;;
        --no-install) ;;   # predefinição; aceite por compatibilidade
        -*) echo "Opção desconhecida: $a"; exit 2 ;;
        *) [ -z "$MSG" ] && MSG=$a || { echo "Só uma mensagem de commit, entre aspas."; exit 2; } ;;
    esac
done
[ -n "$MSG" ] || { echo "Uso: ./scripts/ship.sh \"Mensagem do commit\" [--install] [--no-release] [--no-promote]"; exit 2; }

BRANCH=$(git branch --show-current)
[ "$BRANCH" = dev ] || { echo "✗ O ship.sh publica a partir do ramo dev (está em \"$BRANCH\")."; exit 1; }
[ -z "$(git ls-files --unmerged)" ] || { echo "✗ Há conflitos por resolver."; exit 1; }
[ "$(git config core.hooksPath)" = ".githooks" ] || ./scripts/setup_hooks.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
TAG=v$VERSION
if [ $RELEASE = 1 ]; then
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
        echo "✗ A versão $VERSION já foi publicada. Suba a versão: ./scripts/bump_version.sh patch|minor|major"
        echo "  e preencha a secção dela no CHANGELOG (ou use --no-release)."
        exit 1
    fi
    gh auth status >/dev/null 2>&1 || { echo "✗ O gh não tem sessão iniciada no GitHub (gh auth login)."; exit 1; }
fi
echo "• Ramo: dev · versão $VERSION"

# 1. Testes. Nada é registado, enviado ou publicado se falharem.
./scripts/check.sh --full

# 2. Commit do conteúdo que acabou de ser testado.
git add -A
if [ "$(cat .build/check-passed)" != "$(git write-tree)" ]; then
    echo "✗ A pasta mudou durante a verificação. Volte a correr ./scripts/ship.sh."
    exit 1
fi
if git diff --cached --quiet; then
    echo "• Nada novo para registar; o último commit já é o que foi testado."
else
    git commit -q -m "$MSG"
    echo "✓ Commit $(git rev-parse --short HEAD): ${MSG%%$'\n'*}"
fi

# 3. Push para o dev (o hook pre-push confirma que é o conteúdo testado).
git push -q -u origin dev
echo "✓ Enviado para origin/dev"

# 4. Release: DMG da app testada, tag no commit enviado e publicação no GitHub.
if [ $RELEASE = 1 ]; then
    SKIP_BUILD=1 ./scripts/make_dmg.sh
    DMG=build/Prune-$VERSION.dmg
    [ -f "$DMG" ] || { echo "✗ $DMG não foi criado."; exit 1; }
    NOTES=$(mktemp)
    ./scripts/release_notes.sh "$VERSION" >"$NOTES"
    git tag -a "$TAG" -m "Prune $VERSION"
    git push -q origin "$TAG"
    gh release create "$TAG" "$DMG" --title "Prune $VERSION" --notes-file "$NOTES" --verify-tag --latest
    rm -f "$NOTES"
    echo "✓ Release Prune $VERSION publicada: $(gh release view "$TAG" --json url --jq .url)"
fi

# 5. Versão estável para o main: se houver candidata, é verificada numa cópia limpa e promovida
#    por Pull Request (scripts/stable.sh --apply). O dev e a Release já estão publicados nesta altura.
if [ $PROMOTE = 1 ]; then
    echo "• Versão estável para o main:"
    if ! ./scripts/stable.sh --apply; then
        echo "✗ A promoção para o main falhou (o commit, o push para o dev e a Release já estão feitos)."
        exit 1
    fi
fi

# 6. Opcional: instala a app testada em /Applications, sem recompilar.
if [ $INSTALL = 1 ]; then
    SKIP_BUILD=1 ./scripts/install.sh
fi
echo "✓ Concluído."
