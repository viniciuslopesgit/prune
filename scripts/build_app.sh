#!/bin/zsh
# Compila o Prune e cria Prune.app na pasta build/.
set -e
cd "$(dirname "$0")/.."

CONFIG=${1:-release}
# UNIVERSAL=0 compila só para a arquitetura deste Mac (mais rápido durante o desenvolvimento).
UNIVERSAL=${UNIVERSAL:-1}

APP=build/Prune.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "$UNIVERSAL" = "1" ]; then
    # Binário universal (Apple silicon + Intel). Sem Xcode completo não há `--arch` múltiplo,
    # por isso compila cada arquitetura e junta com lipo.
    for ARCH in arm64 x86_64; do
        swift build -c "$CONFIG" --triple "$ARCH-apple-macosx14.0"
    done
    lipo -create \
        ".build/arm64-apple-macosx/$CONFIG/Prune" \
        ".build/x86_64-apple-macosx/$CONFIG/Prune" \
        -output "$APP/Contents/MacOS/Prune"
else
    swift build -c "$CONFIG"
    cp "$(swift build -c "$CONFIG" --show-bin-path)/Prune" "$APP/Contents/MacOS/Prune"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Google Analytics (opcional). As chaves nunca vão para o repositório: vêm de variáveis de ambiente
# ou do ficheiro analytics.env (ignorado pelo git; ver analytics.env.example). Sem elas, a app não envia nada.
[ -f analytics.env ] && source ./analytics.env
if [ -n "$GA_MEASUREMENT_ID" ] && [ -n "$GA_API_SECRET" ]; then
    /usr/libexec/PlistBuddy -c "Add :PruneGAMeasurementID string $GA_MEASUREMENT_ID" \
                            -c "Add :PruneGAAPISecret string $GA_API_SECRET" "$APP/Contents/Info.plist"
    echo "• Estatísticas (Google Analytics) incluídas: $GA_MEASUREMENT_ID"
fi
# Localização portuguesa (diálogos e menus do sistema em português)
mkdir -p "$APP/Contents/Resources/pt-PT.lproj"
printf '"CFBundleDisplayName" = "Prune";\n' > "$APP/Contents/Resources/pt-PT.lproj/InfoPlist.strings"

# Ícone (refeito quando scripts/make_icon.swift muda). Cada tamanho é desenhado em vetor,
# para os pequenos ficarem nítidos e sem os pormenores que só se leem em tamanho grande.
if [ ! -f build/AppIcon.icns ] || [ scripts/make_icon.swift -nt build/AppIcon.icns ]; then
    ICONSET=build/AppIcon.iconset
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    swiftc -O scripts/make_icon.swift -o build/make_icon
    for s in 16 32 128 256 512; do
        build/make_icon "$ICONSET/icon_${s}x${s}.png" $s
        build/make_icon "$ICONSET/icon_${s}x${s}@2x.png" $((s*2))
    done
    iconutil -c icns "$ICONSET" -o build/AppIcon.icns
    rm -rf "$ICONSET" build/make_icon
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Assinatura. Com o certificado local (scripts/setup_signing.sh), a identidade da app é estável
# e o macOS mantém as permissões entre versões. Sem ele, assina ad-hoc (permissões perdem-se).
IDENTITY=${SIGN_IDENTITY:-"Prune Local Signing"}
# Certificado criado quando a app se chamava MaCClear: continua a servir até criar o novo.
if ! security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY" && [ -z "$SIGN_IDENTITY" ]; then
    security find-identity -p codesigning 2>/dev/null | grep -q "MaCClear Local Signing" && IDENTITY="MaCClear Local Signing"
fi
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --deep --sign "$IDENTITY" "$APP"
    echo "✓ $APP criado (assinado com \"$IDENTITY\")"
else
    codesign --force --deep --sign - "$APP"
    echo "✓ $APP criado (assinatura ad-hoc)"
    echo "  Dica: execute ./scripts/setup_signing.sh uma vez para o macOS não esquecer as permissões a cada versão."
fi
