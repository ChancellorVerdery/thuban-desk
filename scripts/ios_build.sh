#!/bin/zsh
# Builds the iOS app (target DeskiOS, "Thuban Desk.app") for the iOS Simulator, unsigned. Regenerates the Xcode
# project from project.yml first. CONFIG=Release for a Release build; DERIVED=<dir> overrides the DerivedData path
# (default .build/DerivedData-iOS). Prints only errors/warnings from our sources and the result.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
CONFIG="${CONFIG:-Debug}"
DERIVED="${DERIVED:-.build/DerivedData-iOS}"
LOG="${DERIVED}/xcodebuild-ios.log"
mkdir -p "$DERIVED"
xcodegen generate --quiet || exit 1
xcodebuild -project ThubanDesk.xcodeproj -scheme DeskiOS -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build "$@" > "$LOG" 2>&1
STATUS=$?
grep -E "(error|warning): " "$LOG" | grep -E "DeskiOS/|ThubanDesk/|ThubanDeskCore/|xcodebuild: error" | grep -v "DerivedData" | sort -u | head -80
grep -E "\*\* BUILD (SUCCEEDED|FAILED) \*\*" "$LOG" || echo "** BUILD RESULT UNKNOWN (see $LOG) **"
echo "App: $DERIVED/Build/Products/$CONFIG-iphonesimulator/Thuban Desk.app"
exit $STATUS
