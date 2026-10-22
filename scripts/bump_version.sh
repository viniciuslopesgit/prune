#!/bin/zsh
# Sobe a versão (patch, minor ou major) no Info.plist e abre a secção dela no CHANGELOG.
#   ./scripts/bump_version.sh patch    1.2.5 → 1.2.6   correções e alterações internas
#   ./scripts/bump_version.sh minor    1.2.5 → 1.3.0   funcionalidades novas
#   ./scripts/bump_version.sh major    1.2.5 → 2.0.0   mudanças incompatíveis
# Depois, preencher a secção no CHANGELOG: um parágrafo de resumo (vai para o topo da Release)
# e as listas ### Adicionado / Alterado / Corrigido / Removido.
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
    *) echo "Uso: ./scripts/bump_version.sh patch|minor|major"; exit 2 ;;
esac
grep -q "^## \[$NEW\]" CHANGELOG.md && { echo "✗ O CHANGELOG já tem a secção $NEW."; exit 1; }

# sed em vez de PlistBuddy, para manter a formatação do ficheiro (o PlistBuddy reescreve-o todo).
sed -i '' -e "s|<key>CFBundleShortVersionString</key><string>$OLD</string>|<key>CFBundleShortVersionString</key><string>$NEW</string>|" \
          -e "s|<key>CFBundleVersion</key><string>$BUILD</string>|<key>CFBundleVersion</key><string>$((BUILD + 1))</string>|" $PLIST
[ "$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" $PLIST)" = "$NEW" ] \
    && [ "$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" $PLIST)" = "$((BUILD + 1))" ] \
    || { echo "✗ Não foi possível atualizar a versão em $PLIST."; exit 1; }

TODAY=$(date +%Y-%m-%d)
REPO=https://github.com/viniciuslopesgit/prune
python3 - "$NEW" "$TODAY" "$REPO" <<'PY'
import sys, re
new, today, repo = sys.argv[1:]
p = "CHANGELOG.md"
s = open(p, encoding="utf-8").read()
i = s.index("\n## [")
s = s[:i] + f"\n## [{new}] - {today}\n\nRESUMO DA VERSÃO\n\n### Alterado\n- \n" + s[i:]
# Ligação da versão no fim do ficheiro, antes das outras.
m = re.search(r"^\[\d", s, re.M)
link = f"[{new}]: {repo}/releases/tag/v{new}\n"
s = s[:m.start()] + link + s[m.start():] if m else s.rstrip() + "\n\n" + link
open(p, "w", encoding="utf-8").write(s)
PY
echo "✓ $OLD → $NEW (build $((BUILD + 1))). Preencha a secção ## [$NEW] no CHANGELOG.md."
