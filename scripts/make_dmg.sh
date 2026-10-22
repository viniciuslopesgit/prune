#!/bin/zsh
# Cria o instalador build/Prune-<versão>.dmg (arrastar para Aplicações).
# Não precisa de conta Apple Developer: a app vai assinada ad-hoc (sem notarização).
# SKIP_BUILD=1 reaproveita o build/Prune.app existente.
set -e
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
VOLNAME="Prune"
DMG="build/Prune-$VERSION.dmg"
STAGE=build/dmg-stage
TMP_DMG=build/dmg-tmp.dmg
ASSETS=build/dmg-assets

[ "$SKIP_BUILD" = "1" ] || ./scripts/build_app.sh

# Fundo da janela (1x + 2x num só TIFF).
mkdir -p "$ASSETS"
swift scripts/make_dmg_background.swift "$ASSETS/bg.png" 1
swift scripts/make_dmg_background.swift "$ASSETS/bg@2x.png" 2
tiffutil -cathidpicheck "$ASSETS/bg.png" "$ASSETS/bg@2x.png" -out "$ASSETS/background.tiff" >/dev/null 2>&1

# Conteúdo do disco.
rm -rf "$STAGE" "$TMP_DMG" "$DMG"
mkdir -p "$STAGE/.background"
cp -R build/Prune.app "$STAGE/"
ln -s /Applications "$STAGE/Aplicações"
cp "Resources/Como abrir.txt" "$STAGE/"
cp "$ASSETS/background.tiff" "$STAGE/.background/background.tiff"

# Imagem gravável temporária, para ajustar a janela do Finder.
hdiutil detach "/Volumes/$VOLNAME" -quiet 2>/dev/null || true
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$TMP_DMG" >/dev/null 2>&1
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG" 2>/dev/null | awk -F'\t' '/\/Volumes\// {print $NF}')

# Disposição da janela: app à esquerda, Aplicações à direita, instruções ao centro.
if ! osascript <<EOF
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 548}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 104
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "Prune.app" of container window to {170, 210}
        set position of item "Aplicações" of container window to {470, 210}
        set position of item "Como abrir.txt" of container window to {320, 310}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
then
    echo "⚠️  Não foi possível ajustar a janela do Finder (falta a permissão de Automação)."
    echo "    O DMG funciona na mesma, mas sem o fundo e as posições dos ícones."
fi

# Ícone do disco. Tem de ser aplicado depois do Finder: ao gravar a disposição da janela,
# o Finder apaga o .VolumeIcon.icns e limpa a marca de ícone personalizado.
cp build/AppIcon.icns "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"

# Abre a janela automaticamente quando o DMG é montado (o macOS não o permite em Apple silicon).
bless --folder "$MOUNT" --openfolder "$MOUNT" 2>/dev/null || true
rm -rf "$MOUNT/.fseventsd"
chmod -Rf go-w "$MOUNT" 2>/dev/null || true
sync
hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force -quiet

# Imagem final comprimida e só de leitura.
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null 2>&1
rm -f "$TMP_DMG"
rm -rf "$STAGE"
echo "✓ $DMG criado ($(du -h "$DMG" | cut -f1))"
