#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP="build/CodexContextBar.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS"

clang -fobjc-arc \
  -Wall -Wextra \
  -framework Cocoa \
  -mmacosx-version-min=13.0 \
  -o "$APP/Contents/MacOS/CodexContextBar" \
  main.m

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Codex Context Bar</string>
    <key>CFBundleDisplayName</key><string>Codex Context Bar</string>
    <key>CFBundleIdentifier</key><string>local.codex-context-bar</string>
    <key>CFBundleExecutable</key><string>CodexContextBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$PWD/$APP"
