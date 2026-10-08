#!/bin/bash
# Prepare a Developer ID distribution. No credentials in this script or output.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-prepare}"
case "$MODE" in prepare|notarize) ;; *) echo "Usage: Release/distribute.sh [prepare|notarize]" >&2; exit 2;; esac
: "${CODE_SIGN_IDENTITY:?Select a Developer ID Application certificate from Keychain.}"
: "${RELEASE_BUNDLE_ID:?Set your final bundle ID, for example com.yourcompany.reelswhilegpt.}"
[[ "$CODE_SIGN_IDENTITY" == 'Developer ID Application:'* ]] || { echo "A Developer ID Application certificate is required." >&2; exit 2; }
[[ "$RELEASE_BUNDLE_ID" =~ ^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$ && "$RELEASE_BUNDLE_ID" != local.* ]] || { echo "Choose a permanent unique bundle ID under your own namespace." >&2; exit 2; }
cd "$TASK_ROOT"
./build.sh
APP="$TASK_ROOT/dist/Reels While GPT.app"
/usr/bin/codesign --verify --deep --strict "$APP"
if [[ "$MODE" == notarize ]]; then
  : "${NOTARY_PROFILE:?Provide the name of a notarytool profile stored in macOS Keychain.}"
  DEV_PATH="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
  NOTARY="$DEV_PATH/usr/bin/notarytool"
  STAPLER="$DEV_PATH/usr/bin/stapler"
  [[ -x "$NOTARY" && -x "$STAPLER" ]] || { echo "Install/configure Xcode command-line tools first." >&2; exit 2; }
  "$NOTARY" submit "$TASK_ROOT/dist/ReelsWhileGPT-arm64.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format plist > "$TASK_ROOT/dist/notarization-status.plist"
  STATUS="$(/usr/libexec/PlistBuddy -c 'Print :status' "$TASK_ROOT/dist/notarization-status.plist")"
  [[ "$STATUS" == Accepted ]] || { echo "Notarization was not accepted. Inspect Apple's result before distributing." >&2; exit 1; }
  "$STAPLER" staple "$APP"
  "$STAPLER" validate "$APP"
  /usr/sbin/spctl --assess --type execute --verbose "$APP"
  /usr/bin/ditto -c -k --keepParent --norsrc --noextattr "$APP" "$TASK_ROOT/dist/ReelsWhileGPT-arm64.zip"
  echo "Notarized archive ready. This script does not publish/upload it to your website."
else
  echo "Developer ID archive prepared; NOT notarized yet. Run notarize only when you authorize submission to Apple."
fi
cd "$TASK_ROOT/dist"
/usr/bin/shasum -a 256 ReelsWhileGPT-arm64.zip > SHA256SUMS.txt
