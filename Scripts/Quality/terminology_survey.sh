#!/usr/bin/env bash
# Counts the terms for each D22 concept in the English strings, the `ojd` help, and the wiki.
# Run from the repository root after `swift build --product OpenJoystickDriver`.
# Usage: Scripts/Quality/terminology_survey.sh [WORKDIR]   (default .build/terminology)
set -euo pipefail

work=${1:-.build/terminology}
mkdir -p "$work"
export OJD_RUN_REPOSITORY_CLI=1
ln -sf OpenJoystickDriver .build/debug/ojd
ojd=.build/debug/ojd

# strings.tsv: <file>:<line> TAB <value> for each en-US .strings value and .stringsdict <string>.
: >"$work/strings.tsv"
while IFS= read -r f; do
  perl -ne 'print "$ARGV:$.\t$1\n" if /^"[^"]+"\s*=\s*"(.*)";\s*$/ || m{^\s*<string>(.*)</string>\s*$}' "$f" >>"$work/strings.tsv"
done < <(find Sources -path '*/en-US.lproj/*' \( -name '*.strings' -o -name '*.stringsdict' \) | sort)

# help.tsv: "ojd <path>" TAB <help line>, for `ojd --help` and every subcommand's `--help`.
walk() {
  local out label
  out=$("$ojd" "$@" --help 2>&1)
  label="ojd${*:+ $*}"
  printf '%s\n' "$out" | awk -v l="$label" '{printf "%s\t%s\n", l, $0}'
  printf '%s\n' "$out" |
    awk '/^SUBCOMMANDS:/{f=1;next} f&&/^  [a-z]/{print $1} f&&/^[A-Z]+:/{f=0}' |
    while read -r s; do [ "$s" = help ] || walk "$@" "$s"; done
}
walk >"$work/help.tsv"

# wiki.tsv: wiki/<page>:<line> TAB <line>.
: >"$work/wiki.tsv"
for f in wiki/*.md; do
  perl -ne 'chomp; print "$ARGV:$.\t$_\n"' "$f" >>"$work/wiki.tsv"
done

# count FILE REGEX -> "lines/pages first-two-locations"
count() {
  perl -e '
    my ($file, $re) = @ARGV; $re = qr/$re/i;
    open my $fh, "<", $file or die; my ($n, %pg, @ex) = (0);
    while (<$fh>) {
      chomp; my ($loc, $text) = split /\t/, $_, 2;
      next unless defined $text && $text =~ $re;
      $n++; (my $p = $loc) =~ s/:\d+$//; $pg{$p}++;
      push @ex, $loc if @ex < 2;
    }
    printf "%d\t%d\t%s\n", $n, scalar(keys %pg), join(", ", @ex);
  ' "$1" "$2"
}

# concept NAME, then term LABEL REGEX lines.
echo "| Concept | Term | Regex | Strings | Help lines | Wiki lines (pages) | Strings example | Help example | Wiki example |"
echo "| --- | --- | --- | ---: | ---: | ---: | --- | --- | --- |"
term() {
  local concept=$1 label=$2 re=$3 s h w
  s=$(count "$work/strings.tsv" "$re")
  h=$(count "$work/help.tsv" "$re")
  w=$(count "$work/wiki.tsv" "$re")
  local sn hn wn wp se he we
  IFS=$'\t' read -r sn _ se <<<"$s"
  IFS=$'\t' read -r hn _ he <<<"$h"
  IFS=$'\t' read -r wn wp we <<<"$w"
  se=${se//Sources\/OpenJoystickDriverKit\/Resources\/en-US.lproj\//}
  we=${we//wiki\//}
  echo "| $concept | $label | \`$re\` | $sn | $hn | $wn ($wp) | ${se:--} | ${he:--} | ${we:--} |"
}

C1="1 Profile"
term "$C1" "profile" '\bprofiles?\b'
term "$C1" "remapping profile" 'remapping profiles?'
term "$C1" "mapping" '\bmappings?\b'
term "$C1" "preset" '\bpresets?\b'

C2="2 Virtual gamepad"
term "$C2" "virtual gamepad" 'virtual gamepads?'
term "$C2" "virtual device" 'virtual devices?'
term "$C2" "virtual controller" 'virtual controllers?'
term "$C2" "virtual HID" 'virtual HID'
term "$C2" "persona" '\bpersonas?\b'
term "$C2" "virtual joystick" 'virtual joysticks?'

C3="3 Virtual gamepad kind"
term "$C3" "kind" '\bkinds?\b'
term "$C3" "persona" '\bpersonas?\b'
term "$C3" "SDLCompatible" 'SDLCompatible'
term "$C3" "GameControllerCompatible" 'GameControllerCompatible'
term "$C3" "Generic (HID gamepad)" '\bGeneric\b'
term "$C3" "SDL-compatible (spaced)" 'SDL[- ]compatible'
term "$C3" "For Steam and SDL games" 'for steam and sdl'
term "$C3" "For Apple Game Controller games" 'for apple game controller'
term "$C3" "backend" '\bbackends?\b'

C4="4 Who reads the controller"
term "$C4" "Served by" 'served by'
term "$C4" "Handled by" 'handled by'
term "$C4" "Left to macOS" 'left to macos'
term "$C4" "macOS (native)" 'macos \(native\)'
term "$C4" "OpenJoystickDriver (virtual)" 'openjoystickdriver \(virtual\)'
term "$C4" "native" '\bnative(ly)?\b'
term "$C4" "owner / ownership" '\bowner(ship)?\b'

C5="5 DriverKit extension"
term "$C5" "Xbox USB driver" 'xbox usb driver'
term "$C5" "Driver Extension" 'driver extensions?'
term "$C5" "system extension" 'system extensions?'
term "$C5" "transport extension" 'transport[- ]extensions?'
term "$C5" "DriverKit" 'driverkit'
term "$C5" "dext" '\bdexts?\b'
term "$C5" "USB driver (any)" 'usb drivers?'
term "$C5" "driver (any)" '\bdrivers?\b'

C6="6 How a controller reaches the Mac"
term "$C6" "connection" '\bconnections?\b'
term "$C6" "transport" '\btransports?\b'
term "$C6" "Wireless Link" 'wireless link'
term "$C6" "wireless" '\bwireless\b'
term "$C6" "receiver / dongle" '\b(receivers?|dongles?)\b'
term "$C6" "cable / wired" '\b(cables?|wired)\b'
term "$C6" "bus" '\bbus\b'

C7="7 What the controller's own switch selects"
term "$C7" "mode" '\bmodes?\b'
term "$C7" "protocol" '\bprotocols?\b'
term "$C7" "switch" '\bswitch(es)?\b'
