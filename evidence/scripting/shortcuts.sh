#!/usr/bin/env bash
# 6.9 and 6.17: runs six shortcuts through `shortcuts run`, with no window.
# Needs the six "OJD ..." shortcuts built in the Shortcuts app against an installed build that
# publishes the mod and controller output actions, and the sample package at docs/sdk/sample.
set -u
cd "$(dirname "$0")/../.." || exit
work=$(mktemp -d)

run() {
  local name=$1
  shift
  echo "\$ shortcuts run \"$name\" $*"
  shortcuts run "$name" "$@" --output-path "$work/out.txt" 2>&1
  echo "exit $?"
  if [[ -s $work/out.txt ]]; then cat "$work/out.txt"; echo; fi
  rm -f "$work/out.txt"
}

printf '%s' "$PWD/docs/sdk/sample" >"$work/folder.txt"
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
run "OJD Rumble Controller"
run "OJD Set Player Indicator"
run "OJD Set Controller Light"
rm -rf "$work"
