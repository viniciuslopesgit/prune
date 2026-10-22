#!/bin/zsh
# Escreve as notas da Release de uma versão a partir da secção dela no CHANGELOG:
# resumo, instruções de instalação, as listas da versão e a ligação para o histórico.
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
    sys.exit(f"O CHANGELOG não tem a secção ## [{v}].")
body = m.group(1).strip()
cut = body.find("### ")
summary, lists = (body[:cut], body[cut:]) if cut >= 0 else (body, "")
if beta:
    print("> **Beta.** Passa a estável quando cumprir os [critérios de estabilidade](https://github.com/viniciuslopesgit/prune/blob/dev/docs/RELEASE_CRITERIA.md). "
          "Para uso diário, prefira a [última versão estável](https://github.com/viniciuslopesgit/prune/releases/latest).")
    print()
print(summary.strip())
print(f"""
## Instalar

1. Descarregue **Prune-{v}.dmg** (em *Assets*) e arraste o Prune para **Aplicações**.
2. Na primeira abertura, autorize em *Definições do Sistema ▸ Privacidade e segurança ▸ Abrir mesmo assim*, ou no Terminal:
   `xattr -dr com.apple.quarantine /Applications/Prune.app`
3. Siga o assistente de Acesso Total ao Disco.

Verificar o ficheiro: `shasum -a 256 -c SHA256SUMS` na pasta onde descarregou os dois ficheiros.

macOS 14 ou mais recente · Apple silicon e Intel.
""")
if lists:
    print(re.sub(r"^### ", "## ", lists.strip(), flags=re.M))
    print()
print("Histórico completo no [CHANGELOG](https://github.com/viniciuslopesgit/prune/blob/dev/CHANGELOG.md).")
PY
