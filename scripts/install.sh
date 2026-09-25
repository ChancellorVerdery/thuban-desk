#!/bin/zsh
# Release build → /Applications/Thuban Desk.app (replaces any existing copy, relaunches it if it was running).
set -uo pipefail
cd "$(dirname "$0")/.."
CONFIG=Release DERIVED=.build/DerivedData-Release scripts/build.sh || exit 1
SRC=".build/DerivedData-Release/Build/Products/Release/Thuban Desk.app"
DEST="/Applications/Thuban Desk.app"
WAS_RUNNING=0
if pgrep -f "/Applications/Thuban Desk.app/Contents/MacOS" >/dev/null; then WAS_RUNNING=1; pkill -f "/Applications/Thuban Desk.app/Contents/MacOS"; sleep 1; fi
rm -rf "$DEST"
cp -R "$SRC" "$DEST" || exit 1
echo "Installed $DEST"
if [[ "$WAS_RUNNING" == "1" ]]; then open "$DEST"; fi
