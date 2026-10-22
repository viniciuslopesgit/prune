#!/bin/zsh
# Compila e instala/atualiza o Prune em /Applications.
#
# Atualiza a app "no lugar" (substitui o conteúdo do pacote existente) em vez de a mandar para o
# Lixo: quando uma app vai para o Lixo, o macOS remove as permissões dela (ex.: Acesso Total ao
# Disco). Com a assinatura estável (setup_signing.sh) e esta atualização no lugar, as permissões
# mantêm-se entre versões.
# SKIP_BUILD=1 instala o build/Prune.app existente.
set -e
cd "$(dirname "$0")/.."

[ "$SKIP_BUILD" = "1" ] || ./scripts/build_app.sh

SRC=build/Prune.app
DEST=/Applications/Prune.app

# Fecha a app se estiver aberta.
if pgrep -f "$DEST/Contents/MacOS/" >/dev/null; then
    pkill -TERM -f "$DEST/Contents/MacOS/" || true
    for i in {1..10}; do pgrep -f "$DEST/Contents/MacOS/" >/dev/null || break; sleep 0.5; done
fi

if [ -d "$DEST" ]; then
    # Substitui o conteúdo mantendo o mesmo pacote (sem passar pelo Lixo).
    rsync -a --delete "$SRC/" "$DEST/"
    echo "✓ Prune atualizado em $DEST"
else
    ditto "$SRC" "$DEST"
    echo "✓ Prune instalado em $DEST"
fi

codesign --verify --deep --strict "$DEST"
# Dá tempo ao macOS para registar a versão nova antes de a abrir; se a app arrancar no mesmo
# instante da substituição, pode ficar sem ver o Acesso Total ao Disco até ser reaberta.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" 2>/dev/null || true
sleep 2
open "$DEST"
