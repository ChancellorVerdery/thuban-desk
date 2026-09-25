#!/bin/zsh
# Release build of the iOS app installed into the simulator "Thuban iPhone" (iPhone 17 / iOS 26.5, created when
# missing; booted and left running). Then, ONLY when `xcrun devicectl list devices` shows a paired iPhone AND a signing
# team is given in DEVELOPMENT_TEAM, a signed device build installed on that iPhone. Otherwise prints how to enable it.
# The installed app talks to the real Google only after you sign in; nothing here launches it.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/ios_sim.sh
export PATH="$HOME/.local/bin:$PATH"
DERIVED=".build/DerivedData-iOS-Release"

# 1. Simulator
CONFIG=Release DERIVED="$DERIVED" scripts/ios_build.sh || exit 1
APP="$DERIVED/Build/Products/Release-iphonesimulator/Thuban Desk.app"
UDID=$(ios_sim_udid "Thuban iPhone") || exit 1
ios_sim_boot "$UDID"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP" || exit 1
echo "Installed on simulator \"Thuban iPhone\" ($UDID). Open it with: open -a Simulator; xcrun simctl launch $UDID $BUNDLE_ID"

# 2. A real iPhone (optional)
DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /(available|connected)/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F-]+$/) { print $i; exit } }')
if [[ -z "$DEVICE" ]]; then
  echo "No paired iPhone found (xcrun devicectl list devices). To install on your iPhone: connect it, trust this Mac,"
  echo "turn on Developer Mode, then run: DEVELOPMENT_TEAM=<your team id> scripts/ios_install.sh"
  exit 0
fi
if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "Paired iPhone $DEVICE found, but no signing team. Sign in to Xcode with your Apple ID (Settings → Accounts),"
  echo "then run: DEVELOPMENT_TEAM=<your team id> scripts/ios_install.sh"
  exit 0
fi
LOG="$DERIVED/xcodebuild-device.log"
xcodebuild -project ThubanDesk.xcodeproj -scheme DeskiOS -configuration Release -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" build > "$LOG" 2>&1
if ! grep -q "\*\* BUILD SUCCEEDED \*\*" "$LOG"; then
  grep -E "error: " "$LOG" | sort -u | head -20
  echo "Device build failed (see $LOG)"; exit 1
fi
xcrun devicectl device install app --device "$DEVICE" "$DERIVED/Build/Products/Release-iphoneos/Thuban Desk.app" || exit 1
echo "Installed on iPhone $DEVICE."
