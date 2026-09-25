#!/bin/zsh
# Visual smoke test, fully offline: builds (unless SKIP_BUILD=1), launches the Debug binary with a temporary
# THUBAN_DESK_HOME seeded with the sample accounts, THUBAN_DESK_FIXTURES=1 (every request is answered by the
# in-process fake Google — nothing reaches the network, sends are refused) and THUBAN_DESK_SMOKE=<out dir>.
# The app walks the registered scenes, writes one PNG each and quits. Only this smoke instance is ever stopped.
# Usage: scripts/smoke.sh [output-dir]  (default .build/smoke)   SCENES=calendar,mail  limits to scenes by prefix.
# NOW=2026-09-24T14:40:00-04:00 (default) pins the clock so screens match the design artboards.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="${1:-$ROOT/.build/smoke}"
DERIVED="${DERIVED:-.build/DerivedData}"
APP="$ROOT/$DERIVED/Build/Products/Debug/Thuban Desk.app/Contents/MacOS/Thuban Desk"
LOG="${TMPDIR:-/tmp}/thuban-desk-smoke-$$.log"

if [[ "${SKIP_BUILD:-0}" != "1" || ! -x "$APP" ]]; then
  DERIVED="$DERIVED" scripts/build.sh || exit 1
fi

HOME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/thuban-desk-smoke-home.XXXXXX")"
rm -rf "$OUT"; mkdir -p "$OUT"
echo "Smoke home: $HOME_DIR"
echo "Output:     $OUT"
THUBAN_DESK_SMOKE="$OUT" THUBAN_DESK_HOME="$HOME_DIR" THUBAN_DESK_FIXTURES=1 \
THUBAN_DESK_NOW="${NOW:-2026-09-24T14:40:00-04:00}" THUBAN_DESK_SMOKE_SCENES="${SCENES:-}" \
  "$APP" > "$LOG" 2>&1 &
PID=$!
for i in {1..240}; do
  kill -0 "$PID" 2>/dev/null || break
  sleep 1
done
if kill -0 "$PID" 2>/dev/null; then
  echo "TIMEOUT: smoke instance still running after 240 s; stopping it (pid $PID only)"; kill "$PID" 2>/dev/null; STATUS=2
else
  wait "$PID"; STATUS=$?; echo "App exited with status $STATUS"
fi
echo "--- app output (last 40 lines of $LOG):"; tail -40 "$LOG"
echo "--- screenshots:"; ls -1 "$OUT"/*.png 2>/dev/null || echo "(none)"
rm -rf "$HOME_DIR"
exit $STATUS
