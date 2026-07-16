#!/usr/bin/env bash
# Build Claude Deck Mini, assemble the .app bundle (binary + deckd + venv +
# bundled Claude Code plugin), install it to /Applications, and register the
# plugin with Claude Code.
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="$(pwd)"
APP_NAME="Claude Deck Mini"
VERSION="0.1.0"

echo "==> Building release binary"
swift build -c release --product ClaudeDeck
BIN="$(swift build -c release --show-bin-path)/ClaudeDeck"

echo "==> Creating Python venv + installing deckd deps"
python3 -m venv deckd/venv
deckd/venv/bin/pip install --quiet --upgrade pip
deckd/venv/bin/pip install --quiet -r deckd/requirements.txt

echo "==> Assembling $APP_NAME.app"
APP=".build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeDeck"

# Bundle the Python helper + its venv.
cp -R deckd "$APP/Contents/Resources/deckd"
rm -rf "$APP/Contents/Resources/deckd/__pycache__"

# Write the bundled Claude Code plugin tree.
PLUGIN_DIR="$APP/Contents/Resources/claude-deck-plugin"
"$BIN" write-plugin "$PLUGIN_DIR" "$VERSION"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>uk.robaldred.claude-deck-mini</string>
  <key>CFBundleExecutable</key><string>ClaudeDeck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Installing to /Applications"
DEST="/Applications/$APP_NAME.app"
rm -rf "$DEST"
cp -R "$APP" "$DEST"

echo "==> Registering the Claude Code plugin"
"$DEST/Contents/MacOS/ClaudeDeck" register-plugin \
  "$DEST/Contents/Resources/claude-deck-plugin" "$VERSION"

echo
echo "Installed $DEST"
echo "• Launch it from /Applications (it lives in the menu bar, no Dock icon)."
echo "• Start a NEW Claude Code session so the plugin's hooks activate."
echo "• Plug in your Stream Deck Mini — keys populate as sessions report status."
