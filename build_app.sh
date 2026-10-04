#!/bin/zsh
set -e
cd "$(dirname "$0")"
swift build -c release
BIN=$(swift build -c release --show-bin-path)/UnraidWatcher
APP="Unraid Watcher.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/UnraidWatcher"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Unraid Watcher</string>
<key>CFBundleDisplayName</key><string>Unraid Watcher</string>
<key>CFBundleIdentifier</key><string>com.raymondmunro.unraidwatcher</string>
<key>CFBundleExecutable</key><string>UnraidWatcher</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.4.0</string>
<key>CFBundleVersion</key><string>5</string>
<key>NSHumanReadableCopyright</key><string>© 2026 Ray Munro. Licensed under the GNU General Public License v3.0 or later.</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PL
# Sign with a stable identity when one exists, so Keychain approvals survive rebuilds (ad-hoc signatures change every build).
ID=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | awk '{print $2}')
codesign --force --sign "${ID:--}" "$APP"
echo "Signed with: ${ID:-ad-hoc}"
echo "Built: $PWD/$APP"
