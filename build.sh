#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --product UCLockMenuBar
APP="$PWD/Build/UC Lock.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/UCLockMenuBar "$APP/Contents/MacOS/UCLockMenuBar"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuIcon.png "$APP/Contents/Resources/MenuIcon.png"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>UCLockMenuBar</string>
    <key>CFBundleIdentifier</key><string>com.secureu.uclock</string>
    <key>CFBundleName</key><string>UC Lock</string>
    <key>CFBundleDisplayName</key><string>UC Lock</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.4.3</string>
    <key>CFBundleVersion</key><string>9</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --identifier com.secureu.uclock --sign - "$APP" 2>/dev/null || true
echo "Built: $APP"

# The installed copy in ~/Applications is canonical. Keep the build output out of
# Launchpad and Spotlight so macOS never shows a second identical app.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PWD/Build/UC Lock.app" 2>/dev/null || true
touch "$PWD/Build/.metadata_never_index"
