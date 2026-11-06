#!/bin/bash
# Builds Chat Board, renders the made-up demo chats to a PNG and checks the status bar column holds all four
# status colors (purple, orange, green, gray). See check-colors.swift for exactly what is measured.
# Uses `swift build`, not build.sh, so the installed app is never touched. Never reads real chats.
#   scripts/snapshot-check.sh [out.png]
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
width=460
height=640

swift build -c release --package-path "$here" --product ChatBoard >/dev/null
bin="$(swift build -c release --package-path "$here" --show-bin-path)/ChatBoard"

demo="$(mktemp -d)"
trap 'rm -rf "$demo"' EXIT
python3 "$here/demo/make-demo.py" "$demo" >/dev/null
out="${1:-$demo/board.png}"

CHAT_BOARD_DEMO="$demo" "$bin" --snapshot "$out" --width "$width" --height "$height"
[[ -s "$out" ]] || { echo "FAIL: no snapshot written"; exit 1; }
swift "$here/scripts/check-colors.swift" "$out" "$width"
