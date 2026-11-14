#!/usr/bin/env bash
# 6.9 and 6.17: runs nine shortcuts through `shortcuts run`.
# Needs the "OJD ..." shortcuts in the Shortcuts app against an installed build that publishes
# the mod, controller output, and profile actions, the sample package at docs/sdk/sample, and a
# profile named "OJD Shortcut Test" chosen in "OJD Set Profile Value".
set -u
cd "$(dirname "$0")/../.." || exit
work=$(mktemp -d)

run() {
  local name=$1
  shift
  echo "\$ shortcuts run \"$name\"${*:+ $*}"
  shortcuts run "$name" "$@" --output-path "$work/out.txt" 2>&1
  echo "exit $?"
  if [[ -s $work/out.txt ]]; then cat "$work/out.txt"; echo; fi
  rm -f "$work/out.txt"
}

# The folder parameter is a URL, so Shortcuts reads text input only as a `file://` URL.
printf '%s' "file://$PWD/docs/sdk/sample/" >"$work/folder.txt"
printf 'ojd-sample' >"$work/name.txt"

run "OJD List Mod Packages"
run "OJD Install Mod Package" --input-path "$work/folder.txt"
run "OJD List Mod Packages"
echo "\$ ojd mod list"
ojd mod list
run "OJD Remove Mod Package" --input-path "$work/name.txt"
run "OJD List Mod Packages"
echo "\$ ojd controller list"
ojd controller list
# With no controller connected, Shortcuts asks for one in a window, so the run stops instead.
if ojd controller list | grep -q '^No controllers'; then
  echo "No controller connected: OJD Set Controller Light not run."
else
  run "OJD Set Controller Light"
  run "OJD Rumble First Controller"
  run "OJD Set Player First Controller"
fi
# The profile shortcut renames the profile chosen in it to its input; ojd renames it back.
printf 'OJD Shortcut Renamed' >"$work/value.txt"
run "OJD Set Profile Value" --input-path "$work/value.txt"
echo "\$ ojd profile list"
ojd profile list
echo "\$ ojd profile set \"OJD Shortcut Renamed\" name \"OJD Shortcut Test\""
ojd profile set "OJD Shortcut Renamed" name "OJD Shortcut Test"
rm -rf "$work"
