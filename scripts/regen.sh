#!/bin/zsh
# Regenerates ThubanDesk.xcodeproj (build.sh does this on every build; use this to open the project in Xcode).
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
xcodegen generate --quiet && echo "Generated ThubanDesk.xcodeproj"
