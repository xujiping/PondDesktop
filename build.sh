#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
DEV=false
if [[ "${1:-}" == "--dev" ]]; then
    DEV=true; shift
fi
OUTPUT_DIR="${1:-$PROJECT_DIR/build}"
APP_DIR="$OUTPUT_DIR/一池.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
BUILD_DIR="$PROJECT_DIR/.build"
mkdir -p "$BUILD_DIR"
# --dev 只编译本机架构并跳过 lipo，用于日常开发迭代；发布仍用双架构全量构建。
ARCHES=(arm64 x86_64)
if $DEV; then ARCHES=($(uname -m)); fi
for ARCH in $ARCHES; do
    xcrun swiftc -O -target "$ARCH-apple-macosx13.0" -framework AppKit -framework SpriteKit -framework SwiftUI -framework Combine "$PROJECT_DIR/Sources/"*.swift -o "$BUILD_DIR/PondDesktop-$ARCH"
done
if [[ ${#ARCHES} -eq 2 ]]; then
    xcrun lipo -create "$BUILD_DIR/PondDesktop-arm64" "$BUILD_DIR/PondDesktop-x86_64" -output "$APP_DIR/Contents/MacOS/PondDesktop"
else
    cp "$BUILD_DIR/PondDesktop-${ARCHES[1]}" "$APP_DIR/Contents/MacOS/PondDesktop"
fi
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>一池</string>
<key>CFBundleDisplayName</key><string>一池</string>
<key>CFBundleIdentifier</key><string>studio.yichi.PondDesktop</string>
<key>CFBundleVersion</key><string>7</string>
<key>CFBundleShortVersionString</key><string>1.6.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleExecutable</key><string>PondDesktop</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
if [[ -f "$PROJECT_DIR/AppIcon.icns" ]]; then cp "$PROJECT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"; fi
codesign --force --sign - "$APP_DIR"
if $DEV; then print "已构建（${ARCHES[1]} 单架构）：$APP_DIR"; else print "已构建：$APP_DIR"; fi
