#!/bin/bash
# Runs the tests. With Xcode this is plain `swift test`. With only the Command Line Tools there is no XCTest,
# and SwiftPM neither finds the Swift Testing framework the tools ship nor runs it, so it reports success with
# zero tests. Passing the framework's folder fixes both. Fails if no test ran, so that can't pass silently.
set -uo pipefail
cd "$(dirname "$0")/.."

flags=()
if [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
  tools="$(xcode-select -p)"
  frameworks="$tools/Library/Developer/Frameworks"
  flags=(-Xswiftc -F"$frameworks"
         -Xlinker -rpath -Xlinker "$frameworks"
         -Xlinker -rpath -Xlinker "$tools/Library/Developer/usr/lib")
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
swift test ${flags[@]+"${flags[@]}"} "$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
if [[ $status -ne 0 ]]; then exit "$status"; fi
if ! grep -Eq "Test run with [1-9][0-9]* tests?|Executed [1-9][0-9]* tests?" "$log"; then
  echo "test.sh: no tests ran" >&2
  exit 1
fi
