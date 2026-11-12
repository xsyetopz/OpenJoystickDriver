#!/usr/bin/env bash
# usage: replace.sh <name>
# Measures what a running GameController program and a running SDL3 program observe when OJD replaces
# the 2C's (2DC8:301B) virtual gamepad: both probes run 45 s; at 12 s `ojd virtual set
# game-controller-compatible` and at 27 s `ojd virtual reset` replace the gamepad. Every line carries
# the wall clock in ms, and each probe runs under `script` so its output reaches the log unbuffered.
# Logs: replace/<name>.{gc,sdl,commands}.txt
set -u
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
OUT=$ROOT/docs/development/virtual-profile-selection/replace
name=$1
mkdir -p "$OUT"
cd "$ROOT" || exit 1
ojd() { (exec -a ojd /Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver "$@"); }
stamp() { perl -MTime::HiRes=time -ne '$|=1; printf "%.3f %s", time, $_'; }
just diagnose-gamecontroller --seconds 1 > /dev/null 2>&1
just diagnose-sdl3 --seconds 1 > /dev/null 2>&1
script -q /dev/null just diagnose-gamecontroller --seconds 45 2>&1 | stamp > "$OUT/$name.gc.txt" &
script -q /dev/null just diagnose-sdl3 --seconds 45 --wait-devices 5 2>&1 | stamp > "$OUT/$name.sdl.txt" &
{
  sleep 12
  echo "set game-controller-compatible"; ojd virtual set game-controller-compatible 2DC8:301B 2>&1
  echo "set returned"
  sleep 15
  echo "reset"; ojd virtual reset 2DC8:301B 2>&1
  echo "reset returned"
} | stamp > "$OUT/$name.commands.txt"
wait
