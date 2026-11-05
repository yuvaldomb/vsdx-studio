#!/bin/sh
set -e
cd "$(dirname "$0")"
swift build -c release
APP="dist/VSDX Studio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/VSDXStudio" "$APP/Contents/MacOS/VSDXStudio"
cp Info.plist "$APP/Contents/Info.plist"
if [ -f "dist/AppIcon.icns" ]; then
  cp "dist/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$APP"
echo "$APP"
