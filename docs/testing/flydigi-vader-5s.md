# Flydigi Vader 5S (USB)

USB identity `37D7:2801`, the Flydigi Vader 5S over a cable. The record serves two modes and neither is verified: no tester has sent the USB interface dump of this pad. Card F2 in [Flydigi tester checks](flydigi-tester-checks.md) lists the files a tester sends.

## Modes

| Mode | Selected by | Protocol | Endpoints |
| --- | --- | --- | --- |
| `default` (GIP) | No key; it runs when no other mode matches | `XboxGIP` | In `0x81`, out `0x01`, `SetConfiguration1BeforeClaim`, 200 ms settle |
| `xusb` | An interface with class, subclass and protocol `FF/5D/01` | `XboxXUSB`, variant `Wired` | In `0x81`, out `0x01` |

The record's `usb.endpoints` (in `0x81`, out `0x01`) are the `XboxXUSB` defaults and differ from the `XboxGIP` defaults (in `0x82`, out `0x02`). A record-level override has to differ from the default of at least one mode, so this pair is valid: it moves the GIP mode and leaves the XUSB mode on its defaults.

A pad with an interface `FF/47/D0` runs the default mode, which is GIP. A pad with neither interface also runs the default mode, and the log line `No mode of 37D7:2801 matched` names the interface classes seen, so the log shows what the pad exposed. `ojd controller show 37D7:2801` reports the mode that runs.

## Evidence

Commit `98b7b0eb6` (2026-07-12) added the GIP record with the recorded provenance `source: local-hardware` and `verified: true`. That is evidence about the state of the pad at that commit: a GIP record with endpoints `0x81` and `0x01`, `SetConfiguration1BeforeClaim` and a 200 ms settle time. It is not verification of the current record. The provenance field is not part of the record format, so the current record carries no such claim. Read the commit with:

```bash
git show 98b7b0eb6:Resources/ControllerOverrides/37d7/37d7-2801.json
```

Linux `xpad` binds `37D7` as a 360-class pad, which is why the record also holds the `xusb` mode.

## Status

Unverified. Not yet checked on hardware: which interface the pad shows, whether the `xusb` endpoints are those of the record, and the controls each mode delivers.

## Procedure

Connect the pad with a cable, then run (`ojd` is the [command-line tool](../../wiki/Command-Line.md)):

```bash
ojd controller list
ojd controller show 37D7:2801
ojd controller watch 37D7:2801
```

`show` reports the mode that runs. Press each control in turn and confirm the reported name matches the physical label.
