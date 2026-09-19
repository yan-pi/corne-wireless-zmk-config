#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BINARY="$ROOT/.build/release/corne-battery"
PLIST="$HOME/Library/LaunchAgents/sh.indianboy.corne-battery.plist"
DEVICE_NAME=${CORNE_DEVICE_NAME:-Corne}

if [ ! -x "$BINARY" ]; then
  swift build --configuration release --package-path "$ROOT"
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>sh.indianboy.corne-battery</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BINARY</string><string>monitor</string><string>--name</string><string>$DEVICE_NAME</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/corne-battery.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/corne-battery.error.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
printf '%s\n' "Installed $PLIST for device name '$DEVICE_NAME'."
