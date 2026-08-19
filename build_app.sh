#!/bin/bash
set -e

echo "🔨 Building Dynamico (Release target arm64)..."
swift build -c release

APP_DIR="Dynamico.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

echo "📦 Assembling $APP_DIR bundle..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp -f .build/release/Dynamico "$MACOS_DIR/Dynamico"

if [ -f "AppIcon.icns" ]; then
    cp -f "AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DOCTYPE/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Dynamico</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.dynamico.notch</string>
    <key>CFBundleName</key>
    <string>Dynamico</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>CFBundleURLName</key>
            <string>com.dynamico.notch.oauth</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>notchnook</string>
            </array>
        </dict>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "🚀 Installing into main /Applications directory..."
rm -rf /Applications/Dynamico.app
cp -R "$APP_DIR" /Applications/Dynamico.app
touch /Applications/Dynamico.app

# Import metadata into Spotlight index & LaunchServices
mdimport /Applications/Dynamico.app 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f /Applications/Dynamico.app 2>/dev/null || true

echo "✅ App installed into /Applications/Dynamico.app!"
