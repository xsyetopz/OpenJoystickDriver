# Flydigi Vader 4 Pro

This controller connects five ways, and macOS treats each as a separate
device with its own identity and protocol. Observed on firmware 6.9.5.5 with
macOS 26.5.

## Which Mode To Use

| How you connect | Controls | Vibration | Back paddles [^paddles] |
| --- | --- | --- | --- |
| **Dongle, DInput** | ✅ | ✅ full strength | ⚠️ remap only |
| Dongle, XInput | ❌ | — | — |
| Bluetooth, DInput | ✅ | ❌ | ❌ |
| Bluetooth, XInput | ✅ | ❌ | ❌ |
| Switch | ✅ | ⚠️ short pulses | ❌ |

✅ works · ⚠️ works with a caveat · ❌ unavailable

[^paddles]: M1-M4, C and Z. Only dongle DInput mode reports them separately,
    and even there they cannot be passed straight through to a game. See
    [About The Back Paddles](#about-the-back-paddles).

**Use the dongle in DInput mode.** It is the only mode with vibration that also
sees the back paddles as separate buttons. Plug in the 2.4 GHz dongle, set the
slider on the back of the controller to the dongle position, and hold
`O` + `A`.

**Switch mode** is the best wireless choice if you want vibration. Set the
slider to Switch, hold Home for three seconds, and pair it in System Settings.
macOS names it "Pro Controller".

**Bluetooth in DInput mode** is a good wireless choice when you do not need
vibration at all.

Switching modes changes how macOS sees the controller, so a game may ask you to
reassign your buttons afterwards.

## What Each Mode Gives You

**Dongle, DInput.** All standard controls work. Vibration has real strength
control and the two motors can be driven independently. The six extra buttons
(M1-M4, C and Z) send their own signals here, which no other mode does, so a
remapping profile can give each one an action.

**Dongle, XInput.** Not supported. In this mode the controller identifies
itself as a Microsoft Xbox 360 wired controller, an identity real Xbox
controllers also use but reach over a different connection type. The driver
cannot currently tell the two apart, so it does not read this mode. Hold
`O` + `A` to switch the dongle to DInput, which supports everything.

**Bluetooth, DInput.** All controls work. The controller does not accept
vibration commands at all in this mode, so no game can make it rumble.

**Bluetooth, XInput.** All controls work. The controller exposes a vibration
channel in this mode, but the driver does not yet drive it.

**Switch.** Every control works and vibration reaches you, but it uses the
Nintendo HD rumble system, which plays a short pulse per command instead of a
steady buzz. Games built around it feel right; games expecting a simple motor
may feel a repeated tap. Controls appear under Nintendo names, so the triggers
show as ZL and ZR and the bumpers as L and R. The driver lists a player
indicator light for this mode because it shares the Switch Pro Controller
profile, but this controller has no such lights and the setting does nothing.

## About The Back Paddles

The M1-M4, C and Z paddles send their own distinct signals only on the dongle
in DInput mode.

Even there, they cannot be handed to a game directly. The virtual controller
this driver publishes carries the sixteen buttons a standard gamepad has, and
all sixteen are already spoken for, so there is no spare button to put a paddle
on. What you can do is give a paddle its own action in a remapping profile, for
example a keyboard key or a different gamepad button.

In every other mode they are not addressable at all. Each paddle repeats
whichever button it is assigned to inside the controller, so if a paddle is set
to RB, the driver receives an ordinary RB press and cannot tell the two apart.

Those assignments live in the controller's own firmware and are changed with
Flydigi's configuration app, which runs on Windows and mobile only. A macOS-only
owner cannot change them, and a second-hand or previously configured controller
may not match the factory defaults. The assignments on the controller used for
this document are not necessarily the ones yours shipped with.

## Identities

Each mode enumerates as a stable, distinct VID/PID, so each needs its own
catalog record and, where the protocol differs, its own parser.

| Mode | Identity | Parser |
| --- | --- | --- |
| Dongle, DInput | `04B4:2412` | `FlydigiVendor`, the vendor protocol on HID usage page `0xFFA0` |
| Dongle, XInput | `045E:028E` | none; see below |
| Bluetooth, DInput | `D7D7:0041` | `Flydigi` |
| Bluetooth, XInput | `045E:02E0` | `XboxBluetoothHID` |
| Switch | `057E:2009` | `SwitchPro`, the shared Nintendo record |

Three of these are identities the controller borrows rather than owns. In
XInput modes it presents Microsoft Xbox VID/PIDs, and in Switch mode it
presents Nintendo's Switch Pro Controller identity, which is why it reuses a
record written for that hardware.

Borrowing is also why dongle XInput is unsupported. `045E:028E` is the generic
Microsoft Xbox 360 wired identity, and real Xbox 360 controllers using it are
reached over a different connection type than this dongle. A catalog record
names one connection type, so one record cannot currently serve both.

The sections below describe the Bluetooth DInput record specifically.

## Why The Bluetooth DInput Record Exists

The device advertises Generic Desktop GamePad usage, so descriptor-driven
discovery finds it, but three descriptor properties defeat the generic parser:

- the right stick is published on `Z`/`Rz`, which the generic parser maps to
  triggers;
- the analog triggers are published on Simulation page `0x02` as Brake and
  Accelerator, which the generic parser does not read;
- button usages are non-contiguous (1, 2, 4, 5, 7…15), so every index after
  the first gap shifts.

Observed generic-parser behavior before the record: right stick drove the
triggers, LT and RT reported stick clicks, X reported Y, Y reported left
bumper, RB reported Start, LB reported Back, Select reported Guide, Start
reported nothing, and left-stick Y was inverted. The D-pad was correct.

## Report Layout

Report ID `0x01`, 15 bytes. Neutral:
`01 FF FF FF FF 00 00 00 00 00 00 00 00 00 00`.

| Offset | Contents |
| --- | --- |
| 1 | Left stick X, signed, `0x7F` right |
| 2 | Left stick Y, signed, `0x80` up |
| 3 | Right stick X, signed, `0x7F` right |
| 4 | Right stick Y, signed, `0x80` up |
| 9 | Low nibble D-pad hat, `1` up increasing clockwise; `0x10` A, `0x20` B, `0x40` X, `0x80` Y |
| 10 | `0x01` LB, `0x02` RB, `0x04` LT digital, `0x08` RT digital, `0x10` Select, `0x20` Start, `0x40` L3, `0x80` R3 |
| 11 | `0x01` C, `0x02` Z, `0x04` M1, `0x08` M2, `0x10` M3, `0x20` M4 |
| 12 | `0x80` Home |
| 13 | Left trigger, unsigned `0...255` |
| 14 | Right trigger, unsigned `0...255` |

Bytes 5–8 were `0x00` in every observed report.

Byte 10's digital trigger bits accompany, not replace, analog values; the parser
reads position only from bytes 13 and 14.

C, Z, and M1 through M4 are indistinguishable from other buttons on this
transport, so they are not decoded separately here.

## Status

Input decoding is verified against captured reports for every control in the
table. Not yet verified on this hardware:

- consumer-visible input through a signed build and the virtual device;
- reconnect after the controller sleeps;
- rumble or any other physical output.

The controller accepts no output reports on this transport: its report
descriptor declares no Output items and macOS reports a one-byte maximum
output report, so rumble is not reachable here.

## Procedure

Pair the controller over Bluetooth, then confirm the runtime selects this
record rather than the generic fallback:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver \
  --headless controller list
```

The entry should report `protocol=flydigi`. Then check each control:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver \
  --headless controller state
```

Push the left stick fully up; confirm negative Y. Deflect
the right stick and confirm the triggers stay at rest. Press each face button,
bumper, stick click, Select, Start, and Home in turn and confirm the reported
name matches the physical label.
