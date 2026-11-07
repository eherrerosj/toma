#!/bin/sh
# Builds Toma Personal.app from the Swift package.
#   ./build.sh       →  ./Toma Personal.app
#   ./build.sh dmg   →  ./Toma Personal.app and ./Toma.dmg (drag-to-Applications disk image)
set -eu
cd "$(dirname "$0")"
VERSION=$(cat VERSION)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
BUILD_COMMIT_SHA=${BUILD_COMMIT_SHA:-$(git rev-parse HEAD)}
[ "$(git rev-parse HEAD)" = "$BUILD_COMMIT_SHA" ] || { echo 'HEAD differs from the requested build commit.' >&2; exit 1; }

# Universal binary: Apple silicon and Intel.
swift build -c release --arch arm64 --arch x86_64
APP='Toma Personal.app'
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_DIR=$(swift build --show-bin-path -c release --arch arm64 --arch x86_64)
cp "$BIN_DIR/Toma" "$APP/Contents/MacOS/Toma"
cp Resources/Toma.icns "$APP/Contents/Resources/Toma.icns"
# English is the base; the Spanish lproj covers the Spanish UI (Strings.swift uses the English text as key).
for L in en es; do cp -R "Resources/$L.lproj" "$APP/Contents/Resources/$L.lproj"; done
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.eherrerosj.toma</string>
  <key>CFBundleName</key><string>Toma Personal</string>
  <key>CFBundleDisplayName</key><string>Toma Personal</string>
  <key>CFBundleExecutable</key><string>Toma</string>
  <key>CFBundleIconFile</key><string>Toma</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>TomaBuildCommit</key><string>$BUILD_COMMIT_SHA</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>es</string></array>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Felipe Basurto. MIT License.</string>
  <key>NSScreenCaptureUsageDescription</key><string>Toma records the region of the screen you choose.</string>
  <key>NSMicrophoneUsageDescription</key><string>Toma records your voice along with the screen when you choose “Mac Sound and Microphone”.</string>
</dict></plist>
PLIST

# Local builds are ad hoc unless a developer explicitly selects a signing identity.
IDENTITY=${SIGNING_IDENTITY:--}
TIMESTAMP=--timestamp=none
if [ "$IDENTITY" != - ]; then TIMESTAMP=--timestamp; fi
if [ "${REQUIRE_NOTARIZATION:-0}" = 1 ]; then
  case "$IDENTITY" in 'Developer ID Application:'*) ;; *) echo 'A Developer ID Application identity is required.' >&2; exit 1 ;; esac
  [ -n "${SIGNING_TEAM:-}" ] || { echo 'SIGNING_TEAM is required.' >&2; exit 1; }
fi
# Hardened runtime blocks the microphone unless the entitlement says otherwise.
ENTITLEMENTS=$(mktemp)
cat > "$ENTITLEMENTS" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.device.audio-input</key><true/>
</dict></plist>
ENT
codesign --force --options runtime $TIMESTAMP --entitlements "$ENTITLEMENTS" --sign "${IDENTITY:--}" --identifier io.github.eherrerosj.toma "$APP"
rm -f "$ENTITLEMENTS"
if [ "${REQUIRE_NOTARIZATION:-0}" = 1 ]; then
  codesign --verify --deep --strict --all-architectures -R "anchor apple generic and identifier \"io.github.eherrerosj.toma\" and certificate leaf[subject.OU] = \"$SIGNING_TEAM\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists" "$APP"
fi
[ "$(git rev-parse HEAD)" = "$BUILD_COMMIT_SHA" ] || { echo 'HEAD changed during the build.' >&2; exit 1; }
echo "Listo: $APP ($VERSION)"

[ "${1:-}" = "dmg" ] || exit 0

# Disk image: Toma Personal.app next to an Applications shortcut, laid out by Finder on a white
# background with an arrow (Resources/dmg-background.tiff, drawn by scripts/background.swift).
DMG=Toma.dmg
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Aplicaciones"
rm -f "$DMG" Toma-rw.dmg
hdiutil create -quiet -volname 'Toma Personal'  -srcfolder "$STAGE" -fs HFS+ -format UDRW -size 20m Toma-rw.dmg
rm -rf "$STAGE"
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen Toma-rw.dmg | awk '/Apple_HFS/ {print $1}')
cp Resources/Toma.icns "/Volumes/Toma Personal/.VolumeIcon.icns"
mkdir -p "/Volumes/Toma Personal/.background" && cp Resources/dmg-background.tiff "/Volumes/Toma Personal/.background/background.tiff"
SetFile -a C "/Volumes/Toma Personal" 2>/dev/null || true
if [ "${LAYOUT_DMG:-1}" = 1 ]; then
osascript <<APPLESCRIPT || echo "(sin maquetar: Finder no respondió)"
tell application "Finder"
  tell disk "Toma Personal"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 740, 440}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "Toma Personal.app" of container window to {140, 150}
    set position of item "Aplicaciones" of container window to {400, 150}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
fi
sync
hdiutil detach -quiet "$DEVICE"
hdiutil convert -quiet Toma-rw.dmg -format ULFO -o "$DMG"
rm -f Toma-rw.dmg
codesign --force $TIMESTAMP --sign "${IDENTITY:--}" "$DMG"

# Notarize and staple, so Gatekeeper opens the DMG without «Abrir igualmente». Needs a Developer ID
# signature and a notarytool keychain profile (create it once: xcrun notarytool store-credentials toma).
NOTARY_PROFILE=${NOTARY_PROFILE:-toma}
if [ "$TIMESTAMP" = "--timestamp" ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  echo "Notarizado y grapado: $DMG"
else
  [ "${REQUIRE_NOTARIZATION:-0}" != 1 ] || { echo 'Notarization credentials are unavailable.' >&2; exit 1; }
  echo "(sin notarizar: falta certificado Developer ID o perfil de notarytool \"$NOTARY_PROFILE\")"
fi
echo "Listo: $DMG"
