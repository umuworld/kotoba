#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$PROJECT_DIR/dist/Kotoba.app"

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "Kotoba requires an Apple Silicon Mac running macOS 26 or later." >&2
  exit 1
fi
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if (( ${SDK_VERSION%%.*} < 26 )); then
  echo "macOS SDK 26+ is required. Install Xcode 26+ or matching Command Line Tools." >&2
  exit 1
fi

mkdir -p "$BUILD_DIR/modules" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx26.0 \
  -module-cache-path "$BUILD_DIR/modules" \
  "$PROJECT_DIR"/Sources/*.swift -o "$APP_DIR/Contents/MacOS/Kotoba" \
  -framework AppKit -framework SwiftUI -framework ScreenCaptureKit \
  -framework Speech -framework AVFoundation -framework Security

# Generate the project-owned icon from source; no binary assets are required.
xcrun swift -module-cache-path "$BUILD_DIR/modules" \
  "$PROJECT_DIR/Tools/generate_icon.swift" "$BUILD_DIR/AppIcon.iconset" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

# Default: local ad-hoc signature. A stable installed signing identity is optional.
# This does not notarize the application or modify an installed copy.
codesign --force --sign "${KOTOBA_SIGN_IDENTITY:--}" --identifier local.kotoba.learning "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
printf 'Built: %s\n' "$APP_DIR"
