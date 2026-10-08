#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# Use the selected Xcode toolchain; require a standard macOS SDK installation.
DEV="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
COMPILER="$DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
SDK="$DEV/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
if [[ ! -x "$COMPILER" || ! -d "$SDK" ]]; then
  COMPILER="$(/usr/bin/xcrun --find swiftc)"
  SDK="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
fi
DEST="$PWD/dist/Reels While GPT.app"
STAGING="$(mktemp -d /private/tmp/ReelsWhileGPT-build.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Reels While GPT.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
"$COMPILER" -swift-version 5 -O -target arm64-apple-macosx13.0 -sdk "$SDK" \
  -module-cache-path "$STAGING/module-cache" Sources/*.swift \
  -framework AppKit -framework SwiftUI -framework ApplicationServices -framework WebKit \
  -o "$APP/Contents/MacOS/ReelsWhileGPT"
"$COMPILER" -swift-version 5 -O -target arm64-apple-macosx13.0 -sdk "$SDK" \
  -module-cache-path "$STAGING/module-cache" Sources/ScriptRunner/main.swift \
  -o "$APP/Contents/MacOS/ScriptRunner"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGN_ARGS=(--force --sign "$IDENTITY" --options runtime --entitlements "$PWD/Release/App.entitlements")
if [[ "$IDENTITY" != "-" ]]; then SIGN_ARGS+=(--timestamp); fi
/usr/bin/codesign "${SIGN_ARGS[@]}" "$APP/Contents/MacOS/ScriptRunner"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE NOTICE "$APP/Contents/Resources/"
if [[ -n "${RELEASE_BUNDLE_ID:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $RELEASE_BUNDLE_ID" "$APP/Contents/Info.plist"
fi
cp Resources/detector.js Resources/reels.js Resources/pip.js Resources/swipe.js Resources/seek.js Resources/PrivacyInfo.xcprivacy Resources/AppIcon.icns Resources/AppIcon.png "$APP/Contents/Resources/"
/usr/bin/xattr -cr "$APP"
/usr/bin/codesign "${SIGN_ARGS[@]}" "$APP"
/usr/bin/codesign --verify --strict "$APP"
mkdir -p "$PWD/dist"
rm -rf "$DEST"
/usr/bin/ditto --norsrc --noextattr "$APP" "$DEST"
/usr/bin/xattr -cr "$DEST"
/usr/bin/codesign --verify --deep --strict "$DEST"
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr "$APP" "$PWD/dist/ReelsWhileGPT-arm64.zip"
echo "Built: $DEST"
