#!/bin/zsh
# iOS visual smoke, fully offline: builds (unless SKIP_BUILD=1), boots its OWN simulator "Thuban Desk Smoke"
# (iPhone 17 / iOS 26.5, created when missing), installs the app and launches it with the in-process fake Google
# (THUBAN_DESK_FIXTURES=1 — nothing reaches the network, sends are refused), the clock pinned to Thu Sep 24 2026
# 2:40 PM and THUBAN_DESK_SMOKE=1. The app walks its scenes (DeskiOS/App/SmokeHarness.swift); for each one this
# script takes `xcrun simctl io <udid> screenshot` into the output folder. Then the same on "Thuban Desk Smoke iPad"
# (iPad Pro 13-inch, whose portrait width already gets the full sidebar + list + thread layout; a headless simulator
# cannot be rotated) unless IPAD=0. Launch env vars go through the SIMCTL_CHILD_ prefix.
# Usage: scripts/ios_smoke.sh [output-dir]  (default .build/ios-smoke)   SCENES=mail,thread limits the walk.
# KEEP_BOOTED=1 leaves the smoke simulators running afterwards.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/ios_sim.sh
ROOT="$PWD"
OUT="${1:-$ROOT/.build/ios-smoke}"
DERIVED="${DERIVED:-.build/DerivedData-iOS}"
APP="$ROOT/$DERIVED/Build/Products/Debug-iphonesimulator/Thuban Desk.app"
NOW_VALUE="${NOW:-2026-09-24T14:40:00-04:00}"
# Status-bar clock: NOW_VALUE with ".000" fractional seconds, the only ISO shape simctl accepts.
STATUS_CLOCK=$(print -r -- "$NOW_VALUE" | sed -E 's/(T[0-9]{2}:[0-9]{2}:[0-9]{2})([+Z-])/\1.000\2/')

if [[ "${SKIP_BUILD:-0}" != "1" || ! -d "$APP" ]]; then
  DERIVED="$DERIVED" scripts/ios_build.sh || exit 1
fi
rm -rf "$OUT"; mkdir -p "$OUT"

run_device() {
  local name="$1" type="$2" clock="$3" udid data state last=-1 deadline rc=0 line="" index="" scene="" shot=""
  udid=$(ios_sim_udid "$name" "$type") || return 1
  echo "== $name ($udid)"
  ios_sim_boot "$udid"
  # --time must be a full ISO string WITH fractional seconds (or a 24-hour "H:MM", which the iPad shows as AM);
  # anything else (e.g. "2:40 PM", or ISO without ".000") is rejected and the real wall clock shows. The iPad's
  # status-bar date stays the real one; simctl does not pin it.
  xcrun simctl status_bar "$udid" override --time "$clock" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 >/dev/null 2>&1 \
    || echo "   WARNING: status-bar override failed; screenshots show the real clock"
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$udid" "$APP" || return 1
  SIMCTL_CHILD_THUBAN_DESK_FIXTURES=1 SIMCTL_CHILD_THUBAN_DESK_SMOKE=1 SIMCTL_CHILD_THUBAN_DESK_NOW="$NOW_VALUE" \
  SIMCTL_CHILD_THUBAN_DESK_SMOKE_SCENES="${SCENES:-}" \
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" > /dev/null || return 1
  data=$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data) || return 1
  state="$data/Documents/smoke/state.txt"
  deadline=$((SECONDS + 420))
  while (( SECONDS < deadline )); do
    if [[ -f "$state" ]]; then
      line=$(<"$state")
      if [[ "$line" == done ]]; then echo "   done"; break; fi
      if [[ "$line" == error* ]]; then echo "   FAILED: $line"; rc=1; break; fi
      index="${line%% *}"; scene="${line#* }"
      if [[ "$index" == <-> ]] && (( index > last )); then
        # A screenshot occasionally stalls; give it 15 s, then move on (the scene is reported missing).
        xcrun simctl io "$udid" screenshot --type=png "$OUT/$scene.png" > /dev/null 2>&1 &
        shot=$!
        for _ in {1..75}; do kill -0 $shot 2>/dev/null || break; sleep 0.2; done
        if kill -0 $shot 2>/dev/null; then kill $shot 2>/dev/null; echo "   $scene: screenshot timed out"; rc=3; else echo "   $scene"; fi
        print -n "$index" > "$data/Documents/smoke/ack.txt"
        last=$index
      fi
    fi
    sleep 0.2
  done
  (( SECONDS >= deadline )) && { echo "   TIMEOUT waiting for the app"; rc=2; }
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl status_bar "$udid" clear 2>/dev/null || true
  [[ "${KEEP_BOOTED:-0}" == "1" ]] || xcrun simctl shutdown "$udid" 2>/dev/null || true
  return $rc
}

STATUS=0
run_device "Thuban Desk Smoke" "" "$STATUS_CLOCK" || STATUS=$?
if [[ "${IPAD:-1}" == "1" ]]; then
  run_device "Thuban Desk Smoke iPad" "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB" "$STATUS_CLOCK" || STATUS=$?
fi
echo "--- screenshots in $OUT:"
ls -1 "$OUT"/*.png 2>/dev/null | sed "s|$OUT/||" || echo "(none)"
exit $STATUS
