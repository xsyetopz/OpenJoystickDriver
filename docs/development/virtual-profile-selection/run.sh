#!/usr/bin/env bash
# usage: run.sh <profile> <tag> <command...>
# Feeds frames.jsonl to `ojd virtual feed --as <profile>` while the probe command runs; logs both.
ROOT=/Users/krystian/CodeProjects/xsyetopz/OpenJoystickDriver/.claude/worktrees/agent-a455542383e1e2af7
D=$ROOT/docs/development/virtual-profile-selection
profile=$1; tag=$2; shift 2
log=$D/$profile.$tag.log
{
  echo "# profile=$profile tag=$tag"
  echo "# probe: $*"
  echo "# started: $(date -u +%FT%TZ)"
} > "$log"
(exec -a ojd /Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver virtual feed --as "$profile" < "$D/frames.jsonl" > "$D/$profile.$tag.feed.log" 2>&1) &
feedpid=$!
sleep 1.5
cd "$ROOT"
env "$@" >> "$log" 2>&1
echo "# probe exit: $?" >> "$log"
wait $feedpid
echo "# feed exit: $?" >> "$log"
