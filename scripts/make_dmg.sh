#!/bin/zsh
# Creates the installer build/Prune-<version>.dmg (drag to Applications).
# Does not need an Apple Developer account: the app is signed ad hoc (no notarization).
# SKIP_BUILD=1 reuses the existing build/Prune.app.
set -e
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
VOLNAME="Prune"
DMG="build/Prune-$VERSION.dmg"
STAGE=build/dmg-stage
TMP_DMG=build/dmg-tmp.dmg
ASSETS=build/dmg-assets

[ "$SKIP_BUILD" = "1" ] || ./scripts/build_app.sh

# Window background (1x + 2x in a single TIFF).
mkdir -p "$ASSETS"
swift scripts/make_dmg_background.swift "$ASSETS/bg.png" 1
swift scripts/make_dmg_background.swift "$ASSETS/bg@2x.png" 2
tiffutil -cathidpicheck "$ASSETS/bg.png" "$ASSETS/bg@2x.png" -out "$ASSETS/background.tiff" >/dev/null 2>&1

# Disk contents.
rm -rf "$STAGE" "$TMP_DMG" "$DMG"
mkdir -p "$STAGE/.background"
cp -R build/Prune.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "Resources/How to open.txt" "$STAGE/"
cp "$ASSETS/background.tiff" "$STAGE/.background/background.tiff"

# Temporary writable image, to arrange the Finder window.
hdiutil detach "/Volumes/$VOLNAME" -quiet 2>/dev/null || true
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$TMP_DMG" >/dev/null 2>&1
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG" 2>/dev/null | awk -F'\t' '/\/Volumes\// {print $NF}')

# Window layout: app on the left, Applications on the right, instructions in the middle.
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
        set position of item "Applications" of container window to {470, 210}
        set position of item "How to open.txt" of container window to {320, 310}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
then
    echo "⚠️  Could not arrange the Finder window (Automation permission missing)."
    echo "    The DMG still works, but without the background and icon positions."
fi

# Disk icon. It must be applied after the Finder: when saving the window layout,
# the Finder deletes .VolumeIcon.icns and clears the custom icon flag.
cp build/AppIcon.icns "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"

# Opens the window automatically when the DMG is mounted (macOS does not allow it on Apple silicon).
bless --folder "$MOUNT" --openfolder "$MOUNT" 2>/dev/null || true
rm -rf "$MOUNT/.fseventsd"
chmod -Rf go-w "$MOUNT" 2>/dev/null || true
sync
hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force -quiet

# Final compressed, read-only image.
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null 2>&1
rm -f "$TMP_DMG"
rm -rf "$STAGE"
echo "✓ $DMG created ($(du -h "$DMG" | cut -f1))"
