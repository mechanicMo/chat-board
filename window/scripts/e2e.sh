#!/bin/bash
# Runs the end-to-end tests: the real board beside a stand-in for Claude, driven by real key presses and clicks.
# See Sources/E2E/main.swift for the list of tests.
#
# The run takes over the keyboard and mouse for a few minutes, so it belongs on a machine nobody is using.
# Point it at one in ~/.claude/chat-hud/e2e.env (kept outside the repo):
#   E2E_HOST=user@host        ssh target; leave unset to run on this Mac
#   E2E_SSH_KEY=~/.ssh/key    optional key for that host
#   E2E_REMOTE_DIR=chat-board-e2e   folder on that host (relative to its home)
#   E2E_REMOTE_SIGN="<name>"  sign on that host with this certificate instead of signing here
# That machine has to be logged in with its screen unlocked, and the first run there needs Accessibility granted
# to "Chat Board E2E" and "Chat Board Test" (System Settings > Privacy & Security > Accessibility).
#
#   scripts/e2e.sh                   run everything
#   E2E_ONLY=search,focus scripts/e2e.sh   run some groups (docking focus search dictation order archive config)
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
settings="$HOME/.claude/chat-hud/e2e.env"
# shellcheck disable=SC1090
[[ -f "$settings" ]] && source "$settings"

local_dir="$(mktemp -d)"
trap 'rm -rf "$local_dir"' EXIT

# Starts a script inside the logged-in user's session on the host, the only way to reach its screen over ssh,
# through a one-shot launchd job, and waits until the script leaves the file it promises.
#   in_session <label> <script on the host> <file it writes when done> <timeout seconds>
in_session() {
  local label="$1" script="$2" done_file="$3" timeout="$4"
  ssh "${ssh_opts[@]}" "$E2E_HOST" bash -s <<SCRIPT
set -u
uid=\$(id -u)
plist="/tmp/$label.plist"
cat > "\$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$script</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
PLIST
launchctl bootout "gui/\$uid/$label" 2>/dev/null
launchctl bootstrap "gui/\$uid" "\$plist" || { echo "could not start $label in the user's session"; exit 3; }
for _ in \$(seq 1 $timeout); do [ -e "$done_file" ] && break; sleep 1; done
launchctl bootout "gui/\$uid/$label" 2>/dev/null
[ -e "$done_file" ] || { echo "$label didn't finish within $timeout s"; exit 4; }
SCRIPT
}

if [[ -z "${E2E_HOST:-}" ]]; then
  echo "No E2E_HOST set: running on this Mac. Hands off the keyboard and mouse until it finishes."
  for n in 5 4 3 2 1; do printf "%s " "$n"; sleep 1; done; echo
  "$here/scripts/e2e-bundle.sh" "$local_dir"
  E2E_ONLY="${E2E_ONLY:-}" open -W --env "E2E_DIR=$local_dir" --env "E2E_ONLY=${E2E_ONLY:-}" "$local_dir/Chat Board E2E.app"
  cat "$local_dir/results.txt"
  [[ "$(cat "$local_dir/DONE" 2>/dev/null)" == pass ]]
  exit $?
fi

remote="${E2E_REMOTE_DIR:-chat-board-e2e}"
ssh_opts=(-o ConnectTimeout=20)
[[ -n "${E2E_SSH_KEY:-}" ]] && ssh_opts+=(-i "${E2E_SSH_KEY/#\~/$HOME}" -o IdentitiesOnly=yes)

if [[ -n "${E2E_REMOTE_SIGN:-}" ]]; then
  E2E_NO_SIGN=1 "$here/scripts/e2e-bundle.sh" "$local_dir"
else
  "$here/scripts/e2e-bundle.sh" "$local_dir"
fi

home="$(ssh "${ssh_opts[@]}" "$E2E_HOST" 'echo $HOME')"
dir="$home/$remote"

# The two scripts that run on the host, inside its user session.
cat > "$local_dir/sign.sh" <<SIGN
for app in "$dir"/*.app; do codesign --force --sign "${E2E_REMOTE_SIGN:-}" "\$app" >> "$dir/sign.log" 2>&1 || { echo 1 > "$dir/signed"; exit; }; done
echo 0 > "$dir/signed"
SIGN
cat > "$local_dir/run.sh" <<RUN
E2E_DIR="$dir" E2E_ONLY="${E2E_ONLY:-}" "$dir/Chat Board E2E.app/Contents/MacOS/E2E" > "$dir/runner.log" 2>&1
[ -e "$dir/DONE" ] || echo fail > "$dir/DONE"
RUN
rsync -a --delete -e "ssh ${ssh_opts[*]}" "$local_dir/" "$E2E_HOST:$remote/"

if [[ -n "${E2E_REMOTE_SIGN:-}" ]]; then
  in_session com.mo.chat-board.e2e-sign "$dir/sign.sh" "$dir/signed" 300 > "$local_dir/sign-out.txt" 2>&1 || true
  if [[ "$(ssh "${ssh_opts[@]}" "$E2E_HOST" "cat '$dir/signed' 2>/dev/null")" != 0 ]]; then
    echo "Signing on $E2E_HOST failed. Its screen has to be unlocked, and the keychain may be asking to allow codesign:"
    cat "$local_dir/sign-out.txt"; ssh "${ssh_opts[@]}" "$E2E_HOST" "cat '$dir/sign.log' 2>/dev/null"; exit 1
  fi
fi

set +e
in_session com.mo.chat-board.e2e-run "$dir/run.sh" "$dir/DONE" 900
job=$?
set -e
ssh "${ssh_opts[@]}" "$E2E_HOST" "cat '$dir/results.txt' 2>/dev/null || cat '$dir/runner.log'"
[[ $job -eq 0 && "$(ssh "${ssh_opts[@]}" "$E2E_HOST" "cat '$dir/DONE' 2>/dev/null")" == pass ]]
