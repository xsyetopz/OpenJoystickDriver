# Flydigi Vader 5S (USB)

USB identity 37D7:2801, the Vader 5S over a cable. Two modes, both unverified: no tester has sent the USB interface dump. Card F2 in [Flydigi tester checks](flydigi-tester-checks.md) lists the files to send.

## Modes

| Mode | Selected by | Protocol | Endpoints |
| --- | --- | --- | --- |
| `default` (GIP) | No key; runs when no other mode matches | `XboxGIP` | In 0x81, out 0x01, `SetConfiguration1BeforeClaim`, 200 ms settle |
| `xusb` | Interface class, subclass, protocol FF/5D/01 | `XboxXUSB`, variant `Wired` | In 0x81, out 0x01 |

The record's `usb.endpoints` (in 0x81, out 0x01) are the `XboxXUSB` defaults; `XboxGIP` defaults are in 0x82, out 0x02. A record-level override must differ from at least one mode's default, so this pair is valid: it moves GIP and leaves XUSB.

Interface FF/47/D0, or neither interface, runs the default GIP mode. With neither, the log line `No mode of 37D7:2801 matched` names the interface classes seen. `ojd controller show 37D7:2801` reports the running mode.

## Evidence

Commit `98b7b0eb6` (2026-07-12) added the GIP record with provenance `source: local-hardware` and `verified: true`: endpoints 0x81 and 0x01, `SetConfiguration1BeforeClaim`, 200 ms settle. This is evidence about that commit, not the current record, which has no provenance field. Read it with:

```bash
git show 98b7b0eb6:Resources/ControllerOverrides/37d7/37d7-2801.json
```

Linux `xpad` binds 37D7 as a 360-class pad, so the record also holds the `xusb` mode.

## Status

Not checked on hardware: the pad's interface, `xusb` endpoints, controls each mode delivers.

## Procedure

1. Connect the pad by cable.
2. Run these (`ojd` is the [command-line tool](../../wiki/Command-Line.md)):

   ```bash
   ojd controller list
   ojd controller show 37D7:2801
   ojd controller watch 37D7:2801
   ```

3. Read the mode in the `show` output.
4. Press each control. Check the name matches the label.
