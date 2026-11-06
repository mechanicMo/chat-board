#!/bin/bash
# Builds Chat Board.app into ~/Applications. Run again after changing the sources.
#
# Optional settings, from the environment or from ~/.claude/chat-hud/build.env (kept outside the repo):
#   BUNDLE_ID      the app's bundle identifier (default com.github.chat-board)
#   SIGN_IDENTITY  a code-signing certificate's name (default "-", a throwaway ad-hoc signature)
# macOS ties the Accessibility permission to the signature. An ad-hoc signature changes on every build, so
# the permission has to be granted again each time; a fixed certificate keeps it. The certificate also has
# to be trusted for code signing (security add-trusted-cert -p codeSign), or macOS ignores the grant.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$HOME/Applications/Chat Board.app"

# Values already in the environment win over the file.
env_bundle="${BUNDLE_ID-}"
env_sign="${SIGN_IDENTITY-}"
settings="$HOME/.claude/chat-hud/build.env"
if [[ -f "$settings" ]]; then
  # shellcheck disable=SC1090
  source "$settings"
fi
[[ -n "$env_bundle" ]] && BUNDLE_ID="$env_bundle"
[[ -n "$env_sign" ]] && SIGN_IDENTITY="$env_sign"
BUNDLE_ID="${BUNDLE_ID:-com.github.chat-board}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release --package-path "$here" --product ChatBoard
bin="$(swift build -c release --package-path "$here" --show-bin-path)/ChatBoard"

mkdir -p "$app/Contents/MacOS"
# Copy beside the old binary, then rename over it: a running copy keeps its own file instead of having
# its code overwritten underneath it.
cp "$bin" "$app/Contents/MacOS/ChatBoard.new"
mv -f "$app/Contents/MacOS/ChatBoard.new" "$app/Contents/MacOS/ChatBoard"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Chat Board</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>ChatBoard</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
PLIST

if [[ "$SIGN_IDENTITY" != "-" ]] && ! security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
  echo "Certificate \"$SIGN_IDENTITY\" not found; signing ad-hoc instead." >&2
  SIGN_IDENTITY="-"
fi
codesign --force --sign "$SIGN_IDENTITY" "$app"
echo "Built $app ($BUNDLE_ID, signed with $SIGN_IDENTITY)"
