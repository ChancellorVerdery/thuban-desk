#!/bin/zsh
# Builds the app (ad-hoc signed). Regenerates the Xcode project from project.yml first (it is not committed).
# DERIVED=<dir> overrides the DerivedData path (use a private one when several people build at once);
# CONFIG=Release builds Release. Prints only errors/warnings from our sources and the result.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
CONFIG="${CONFIG:-Debug}"
DERIVED="${DERIVED:-.build/DerivedData}"
LOG="${DERIVED}/xcodebuild.log"
mkdir -p "$DERIVED"
xcodegen generate --quiet || exit 1
xcodebuild -project ThubanDesk.xcodeproj -scheme ThubanDesk -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build "$@" > "$LOG" 2>&1
STATUS=$?
grep -E "(error|warning): " "$LOG" | grep -E "ThubanDesk/|ThubanDeskCore/|xcodebuild: error" | grep -v "DerivedData" | sort -u | head -60
grep -E "\*\* BUILD (SUCCEEDED|FAILED) \*\*" "$LOG" || echo "** BUILD RESULT UNKNOWN (see $LOG) **"
echo "App: $DERIVED/Build/Products/$CONFIG/Thuban Desk.app"
exit $STATUS
