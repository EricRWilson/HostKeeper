#!/bin/zsh
# Builds a release HostKeeper.app (Apple Silicon + Intel) into ./build, plus a .dmg and .zip for downloading.
# Run: ./build-app.sh            (app + dmg + zip)
#      ./build-app.sh --app-only (just the .app, faster)
set -euo pipefail
cd "${0:A:h}"

VERSION=$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/HostKeeper/Version.swift)
BUILD=$(sed -n 's/.*static let build = "\(.*\)"/\1/p' Sources/HostKeeper/Version.swift)
APP="build/HostKeeper.app"
REPO="EricRWilson/HostKeeper"
# Public half of the update signing key; the private half is in the maintainer's Keychain
# and in the SPARKLE_PRIVATE_KEY GitHub secret. Never change it, or installed copies can't update.
SPARKLE_PUBLIC_KEY="3FQVrdakKox+AjQiMzKkvGe41W8jA7XHTAuyM07TFpY="

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/HostKeeper" "$APP/Contents/MacOS/HostKeeper"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>HostKeeper</string>
    <key>CFBundleDisplayName</key><string>HostKeeper</string>
    <key>CFBundleIdentifier</key><string>io.github.ericrwilson.hostkeeper</string>
    <key>CFBundleExecutable</key><string>HostKeeper</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key><string>Free and open source under the MIT License.</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>SUFeedURL</key><string>https://github.com/$REPO/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
</dict>
</plist>
PLIST

# Ad-hoc signature. Without a paid Apple Developer ID the app can't be notarized,
# so people who download it approve it once in System Settings (see README).
codesign --force --deep --sign - "$APP"
echo "Built $APP (version $VERSION, build $BUILD, $(lipo -archs "$APP/Contents/MacOS/HostKeeper"))"

[[ "${1:-}" == "--app-only" ]] && exit 0

ZIP="build/HostKeeper-$VERSION.zip"
DMG="build/HostKeeper-$VERSION.dmg"
rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"

STAGE="build/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "HostKeeper $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG"
rm -rf "$STAGE"

echo "Packaged $DMG and $ZIP"
