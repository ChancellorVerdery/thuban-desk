#!/bin/zsh
# Shared simulator helpers for the iOS scripts (sourced, not run).
#   ios_sim_udid "<name>" [device type id]  → UDID of the named simulator on the newest iOS runtime (26.5 when
#                                              present), creating it when missing (default iPhone 17 or the newest iPhone).
#   ios_sim_boot <udid>                      → boots it (if needed) and waits until it is ready.
BUNDLE_ID="org.thuban.desk.ios"

ios_sim_runtime() {
  local rt
  rt=$(xcrun simctl list runtimes available -j | /usr/bin/python3 -c '
import json, sys
rts = [r for r in json.load(sys.stdin)["runtimes"] if r.get("platform") == "iOS" and r.get("isAvailable")]
want = [r for r in rts if r["version"].startswith("26.5")]
pick = (want or sorted(rts, key=lambda r: [int(x) for x in r["version"].split(".")]))[-1] if rts else None
print(pick["identifier"] if pick else "")')
  echo "$rt"
}

ios_sim_default_type() {
  xcrun simctl list devicetypes -j | /usr/bin/python3 -c '
import json, sys
types = [t for t in json.load(sys.stdin)["devicetypes"] if t.get("productFamily") == "iPhone"]
ids = [t["identifier"] for t in types]
if "com.apple.CoreSimulator.SimDeviceType.iPhone-17" in ids:
    print("com.apple.CoreSimulator.SimDeviceType.iPhone-17")
else:
    plain = [t for t in types if "Pro" not in t["name"] and "Plus" not in t["name"] and "Max" not in t["name"] and "e" != t["name"][-1:]]
    print((plain or types)[-1]["identifier"])'
}

ios_sim_udid() {
  local name="$1" type="${2:-}" runtime udid
  runtime=$(ios_sim_runtime)
  [[ -z "$runtime" ]] && { echo "No iOS simulator runtime installed (Xcode → Settings → Components)." >&2; return 1; }
  udid=$(xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, sys
name, runtime = sys.argv[1], sys.argv[2]
devs = json.load(sys.stdin)["devices"].get(runtime, [])
hit = [d for d in devs if d["name"] == name and d.get("isAvailable", True)]
print(hit[0]["udid"] if hit else "")' "$name" "$runtime")
  if [[ -z "$udid" ]]; then
    [[ -z "$type" ]] && type=$(ios_sim_default_type)
    udid=$(xcrun simctl create "$name" "$type" "$runtime") || return 1
    echo "Created simulator \"$name\" ($type, $runtime): $udid" >&2
  fi
  echo "$udid"
}

ios_sim_boot() {
  local udid="$1"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b > /dev/null
}
