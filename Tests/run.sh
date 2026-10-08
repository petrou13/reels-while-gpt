#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DEV="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
COMPILER="$DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
SDK="$DEV/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
if [[ ! -x "$COMPILER" || ! -d "$SDK" ]]; then
  COMPILER="$(/usr/bin/xcrun --find swiftc)"
  SDK="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
fi
TEMP="$(mktemp -d /private/tmp/ReelsWhileGPT-tests.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
"$COMPILER" -swift-version 5 -sdk "$SDK" -module-cache-path "$TEMP/cache" \
 Sources/SecurityPolicy.swift Sources/Browser.swift Sources/NativeChat.swift Sources/Permissions.swift Sources/Playback.swift Sources/Swipe.swift Sources/Localization.swift Sources/UserStatus.swift Sources/SingleInstance.swift Sources/Engine.swift Tests/main.swift -framework WebKit -o "$TEMP/tests"
"$TEMP/tests"
if command -v node >/dev/null; then node Tests/detector.test.js; node Tests/reels.test.js; node Tests/pip.test.js; node Tests/swipe.test.js; node Tests/seek.test.js; else echo "DOM tests: install Node.js or run with its absolute path"; fi
