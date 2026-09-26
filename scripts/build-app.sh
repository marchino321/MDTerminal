#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-release}"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/$CONFIGURATION"
APP_DIR="$ROOT_DIR/dist/MDTerminal.app"
ICON_SOURCE="$ROOT_DIR/Assets/MDTerminalLogo.png"

cd "$ROOT_DIR"
swift build --product MySSH -c "$CONFIGURATION" --build-system native
swift build --product MySSHAskPass -c "$CONFIGURATION" --build-system native

mkdir -p "$APP_DIR/Contents"
rm -rf "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/MySSH" "$APP_DIR/Contents/MacOS/MySSH"
cp "$BUILD_DIR/MySSHAskPass" "$APP_DIR/Contents/MacOS/MySSHAskPass"
if [[ -d "$BUILD_DIR/SwiftTerm_SwiftTerm.bundle" ]]; then
    cp -R "$BUILD_DIR/SwiftTerm_SwiftTerm.bundle" "$APP_DIR/Contents/Resources/"
fi

if [[ -f "$ICON_SOURCE" ]]; then
    ICON_WORK_DIR="$(mktemp -d)"
    ICONSET="$ICON_WORK_DIR/MDTerminal.iconset"
    mkdir -p "$ICONSET"
    sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
    sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/MDTerminal.icns"
    cp "$ICON_SOURCE" "$APP_DIR/Contents/Resources/MDTerminalLogo.png"
    rm -rf "$ICON_WORK_DIR"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>it</string>
    <key>CFBundleExecutable</key><string>MySSH</string>
    <key>CFBundleIdentifier</key><string>com.myssh.desktop</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>MD Terminal</string>
    <key>CFBundleDisplayName</key><string>MD Terminal</string>
    <key>CFBundleIconFile</key><string>MDTerminal</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

chmod +x "$APP_DIR/Contents/MacOS/MySSH" "$APP_DIR/Contents/MacOS/MySSHAskPass"
chmod -R u+w "$APP_DIR"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
