#!/bin/zsh
# Unit tests for the core package (fixtures + URLProtocol stubs only; never touches Google).
set -uo pipefail
cd "$(dirname "$0")/../Packages/ThubanDeskCore"
swift test 2>&1 | tee "${TMPDIR:-/tmp}/thuban-desk-test.log" | grep -E "error:|failed|Executed .* tests" | tail -25
exit ${pipestatus[1]}
