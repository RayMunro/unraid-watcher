#!/bin/zsh
# Builds the app and packages it as dist/Unraid-Watcher-<version>.dmg
set -e
cd "$(dirname "$0")"
VER=1.0
NAME="Unraid Watcher"
VOL="$NAME"
OUT="dist/Unraid-Watcher-$VER.dmg"
./build_app.sh
python3 tools/make_docs_pdf.py
mkdir -p dist; rm -f "$OUT" dist/rw.dmg
STAGE=$(mktemp -d)
cp -R "$NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp docs/Unraid-Watcher-Documentation.pdf "$STAGE/Documentation.pdf"
cp LICENSE "$STAGE/LICENSE.txt"
mkdir "$STAGE/.background"; swift tools/make_dmg_bg.swift "$STAGE/.background/bg.png"
hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -ov dist/rw.dmg >/dev/null
DEV=$(hdiutil attach dist/rw.dmg -readwrite -noverify -noautoopen | awk '/Apple_HFS/ {print $1; exit}')
sleep 2
# Lay out the window (best effort: needs Finder automation permission the first time)
osascript <<OSA || echo "note: couldn't style the window; the DMG still works"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 640}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set background picture of opts to file ".background:bg.png"
    set position of item "$NAME.app" of container window to {180, 170}
    set position of item "Applications" of container window to {480, 170}
    set position of item "Documentation.pdf" of container window to {230, 360}
    set position of item "LICENSE.txt" of container window to {430, 360}
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA
chflags hidden "/Volumes/$VOL/.background" 2>/dev/null || true
sync
hdiutil detach "$DEV" -quiet
hdiutil convert dist/rw.dmg -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f dist/rw.dmg; rm -rf "$STAGE"
ID=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | awk '{print $2}')
[ -n "$ID" ] && codesign --force --sign "$ID" "$OUT"
echo "Built: $PWD/$OUT ($(du -h "$OUT" | cut -f1))"
