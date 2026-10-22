#!/bin/zsh
# Builds Prune and creates Prune.app in the build/ folder.
set -e
cd "$(dirname "$0")/.."

CONFIG=${1:-release}
# UNIVERSAL=0 builds only for this Mac's architecture (faster during development).
UNIVERSAL=${UNIVERSAL:-1}

APP=build/Prune.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "$UNIVERSAL" = "1" ]; then
    # Universal binary (Apple silicon + Intel). Without full Xcode there is no multiple `--arch`,
    # so it builds each architecture and joins them with lipo.
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

# Google Analytics (optional). The keys never go into the repository: they come from environment variables
# or from the analytics.env file (ignored by git; see analytics.env.example). Without them, the app sends nothing.
[ -f analytics.env ] && source ./analytics.env
if [ -n "$GA_MEASUREMENT_ID" ] && [ -n "$GA_API_SECRET" ]; then
    /usr/libexec/PlistBuddy -c "Add :PruneGAMeasurementID string $GA_MEASUREMENT_ID" \
                            -c "Add :PruneGAAPISecret string $GA_API_SECRET" "$APP/Contents/Info.plist"
    echo "• Statistics (Google Analytics) included: $GA_MEASUREMENT_ID"
fi
# Translations (Resources/<language>.lproj). macOS picks the one that matches the system language
# (English by default); the system menus and dialogs follow the same language.
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# Icon (redrawn when scripts/make_icon.swift changes). Each size is drawn in vector,
# so the small ones stay sharp and without the details that only read at large sizes.
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

# Signing. With the local certificate (scripts/setup_signing.sh), the app's identity is stable
# and macOS keeps its permissions between versions. Without it, signs ad hoc (permissions are lost).
IDENTITY=${SIGN_IDENTITY:-"Prune Local Signing"}
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --deep --sign "$IDENTITY" "$APP"
    echo "✓ $APP created (signed with \"$IDENTITY\")"
else
    codesign --force --deep --sign - "$APP"
    echo "✓ $APP created (ad hoc signature)"
    echo "  Tip: run ./scripts/setup_signing.sh once so macOS does not forget the permissions with each version."
fi
