#!/usr/bin/env bash
# usage: candidate.sh <name> <persona> <vid-hex> <pid-hex> <version> <productName> <seconds> [probe tags...]
# Publishes the virtual gamepad of the connected 8BitDo Ultimate 2C (2DC8:301B) with one identity over
# the persona's report layout, through a user VirtualDevices file, then runs each probe for <seconds>.
# Probe tags: gc, sdl-hidapi-default, sdl-hidapi-on, sdl-hidapi-off. Default: all four, one after another.
# A first tag `parallel` runs the listed probes at the same time, for a run where the maintainer presses
# each control once.
# Logs: candidates/<name>.<tag>.txt. Remove the VirtualDevices file afterward with `candidate.sh --clear`.
set -u
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
OUT=$ROOT/docs/development/virtual-profile-selection/candidates
FILE="$HOME/Library/Application Support/OpenJoystickDriver/VirtualDevices/2dc8-301b.plist"
ojd() { (exec -a ojd /Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver "$@"); }
if [ "${1:-}" = --clear ]; then rm -f "$FILE"; sleep 3; ojd virtual show; exit 0; fi
name=$1 persona=$2 vid=$3 pid=$4 version=$5 product=$6 seconds=$7; shift 7
tags=("$@"); [ ${#tags[@]} -eq 0 ] && tags=(gc sdl-hidapi-default sdl-hidapi-on sdl-hidapi-off)
mkdir -p "$OUT"
cat > "$FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>apiVersion</key><string>openjoystickdriver/v1alpha3</string>
	<key>identity</key>
	<dict>
		<key>manufacturer</key><string>Microsoft</string>
		<key>productID</key><integer>$((16#$pid))</integer>
		<key>productName</key><string>$product</string>
		<key>vendorID</key><integer>$((16#$vid))</integer>
		<key>version</key><integer>$version</integer>
	</dict>
	<key>kind</key><string>VirtualDevice</string>
	<key>match</key>
	<dict>
		<key>productID</key><integer>12315</integer>
		<key>vendorID</key><integer>11720</integer>
	</dict>
	<key>persona</key><string>$persona</string>
</dict>
</plist>
EOF
sleep 4
cd "$ROOT" || exit 1
parallel=no
if [ "${tags[0]}" = parallel ]; then parallel=yes; tags=("${tags[@]:1}"); fi
probe() {
  local tag=$1 log=$OUT/$name.$tag.txt
  {
    echo "# candidate=$name persona=$persona identity=$vid:$pid version=$version productName=\"$product\" tag=$tag"
    echo "# started: $(date -u +%FT%TZ)"
    echo "# ojd virtual show:"; ojd virtual show 2>&1 | sed 's/^/#   /'
  } > "$log"
  case $tag in
    gc) just diagnose-gamecontroller --seconds "$seconds" >> "$log" 2>&1 ;;
    sdl-hidapi-default) just diagnose-sdl3 --seconds "$seconds" --wait-devices 5 >> "$log" 2>&1 ;;
    sdl-hidapi-on) SDL_JOYSTICK_HIDAPI=1 just diagnose-sdl3 --seconds "$seconds" --wait-devices 5 >> "$log" 2>&1 ;;
    sdl-hidapi-off) SDL_JOYSTICK_HIDAPI=0 just diagnose-sdl3 --seconds "$seconds" --wait-devices 5 >> "$log" 2>&1 ;;
  esac
  echo "# probe exit: $?" >> "$log"
}
for tag in "${tags[@]}"; do
  if [ $parallel = yes ]; then probe "$tag" & else probe "$tag"; fi
done
wait
