#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Install Fonts"
EXECUTABLE_NAME="InstallFonts"
BUILD_DIR=".build/release"
APP_DIR="$APP_NAME.app"

echo "Building release binary..."
swift build -c release

echo "Assembling $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "Signing $APP_DIR (ad-hoc)..."
codesign --force --deep --sign - "$APP_DIR"

echo "Done: $APP_DIR"
echo "Run it with: open \"$APP_DIR\""
