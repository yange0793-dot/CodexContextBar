#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
./build.sh >/dev/null

DEST="/Applications/CodexContextBar.app"
PLIST="$HOME/Library/LaunchAgents/local.codex-context-bar.plist"

pkill -x CodexContextBar 2>/dev/null || true
rm -rf "$DEST"
cp -R build/CodexContextBar.app "$DEST"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>local.codex-context-bar</string>
    <key>ProgramArguments</key>
    <array><string>$DEST/Contents/MacOS/CodexContextBar</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID/local.codex-context-bar" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"
echo "Installed: $DEST"
