#!/bin/zsh
# DELIBERATE live check against the real Google Calendar (never run by build/test/smoke): creates ONE clearly
# labelled test event on the calendar you name, reads it back, deletes it and confirms it is gone.
# Requires a signed-in account (Settings → Accounts) and:
#   scripts/live_check.sh "<calendar id or name>" [account-email]
set -uo pipefail
cd "$(dirname "$0")/../Packages/ThubanDeskCore"
if [[ $# -lt 1 ]]; then echo "usage: scripts/live_check.sh <calendar id or name> [account-email]"; exit 2; fi
THUBAN_DESK_LIVE_CHECK=create-and-delete-test-event THUBAN_DESK_LIVE_CALENDAR="$1" THUBAN_DESK_LIVE_ACCOUNT="${2:-}" \
  swift run -q thuban-desk-live-check
