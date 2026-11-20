#!/bin/bash
# Build Claudette and wrap it into build/Claudette.app (menubar-only, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ClaudetteApp"
[ -x "$BIN" ] || { echo "build product missing: $BIN" >&2; exit 1; }

APP="${APP_OUT:-build/Claudette.app}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Claudette"

# Art export (manifest + PNGs); the app falls back to shape placeholders if it is missing.
[ -f art/export/manifest.json ] || { echo "art/export/manifest.json missing (run scripts/art.sh)" >&2; exit 1; }
mkdir -p "$APP/Contents/Resources"
cp -R art/export "$APP/Contents/Resources/art"
rm -f "$APP/Contents/Resources/art/sheet.png"

# App icon (committed; rebuild with scripts/icon.sh).
[ -f art/icon/AppIcon.icns ] || { echo "art/icon/AppIcon.icns missing (run scripts/icon.sh)" >&2; exit 1; }
cp art/icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>app.claudette.Claudette</string>
  <key>CFBundleName</key><string>Claudette</string>
  <key>CFBundleExecutable</key><string>Claudette</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
