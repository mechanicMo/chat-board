#!/bin/bash
# Packages what the end-to-end run needs into one folder: the board under test, the stand-in for Claude, the runner,
# and freshly made demo chats. scripts/e2e.sh calls this; it never touches the installed Chat Board.
#   scripts/e2e-bundle.sh <folder>
# Signs each app with SIGN_IDENTITY (from the environment or ~/.claude/chat-hud/build.env), the same as build.sh,
# because macOS keeps an Accessibility grant only for an app whose signature stays the same between builds.
# E2E_NO_SIGN=1 leaves them unsigned, for a machine that signs them itself.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:?usage: e2e-bundle.sh <folder>}"

env_sign="${SIGN_IDENTITY-}"
settings="$HOME/.claude/chat-hud/build.env"
# shellcheck disable=SC1090
[[ -f "$settings" ]] && source "$settings"
[[ -n "$env_sign" ]] && SIGN_IDENTITY="$env_sign"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release --package-path "$here" >/dev/null
bin="$(swift build -c release --package-path "$here" --show-bin-path)"

mkdir -p "$out"
rm -rf "$out/demo" "$out"/*.app
python3 "$here/demo/make-demo.py" "$out/demo" >/dev/null

# name, executable, bundle id, 1 when it's a background app with no Dock icon
make_app() {
  local name="$1" exe="$2" id="$3" background="$4"
  local app="$out/$name.app"
  mkdir -p "$app/Contents/MacOS"
  cp "$bin/$exe" "$app/Contents/MacOS/$exe"
  local ui=""
  [[ "$background" == 1 ]] && ui="<key>LSUIElement</key><true/>"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>$id</string>
  <key>CFBundleExecutable</key><string>$exe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  $ui
</dict></plist>
PLIST
  if [[ "${E2E_NO_SIGN:-}" != 1 ]]; then
    codesign --force --sign "$SIGN_IDENTITY" "$app" 2>/dev/null
  fi
}

make_app "Chat Board Test" ChatBoard com.mo.chat-board.test 1
make_app "Stand-in Claude" StandIn com.mo.chat-board.standin 0
make_app "Chat Board E2E" E2E com.mo.chat-board.e2e 1
echo "Packaged into $out (signed with $([[ "${E2E_NO_SIGN:-}" == 1 ]] && echo nothing || echo "$SIGN_IDENTITY"))"
