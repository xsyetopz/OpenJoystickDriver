# Flydigi Vader 5S (USB)

USB identity 37D7:2801 is the Vader 5S on a cable. The record has two modes, and neither is confirmed, because no tester has sent the USB interface list yet. Card F2 in [Flydigi tester checks](flydigi-tester-checks.md) lists the files to send.

## Modes

A mode is one way the controller can talk. OJD picks the mode from what the controller says about itself:

| Mode | Picked when | Protocol | Endpoints |
| --- | --- | --- | --- |
| `default` (GIP) | No key; runs when no other mode matches | `XboxGIP` | In 0x81, out 0x01, `SetConfiguration1BeforeClaim`, 200 ms wait |
| `xusb` | The interface class, subclass, and protocol are FF/5D/01 | `XboxXUSB`, variant `Wired` | In 0x81, out 0x01 |

The record's `usb.endpoints` (in 0x81, out 0x01) are the `XboxXUSB` defaults. `XboxGIP`'s defaults are in 0x82, out 0x02. A record-wide setting must differ from at least one mode's default, so this pair is allowed: it changes GIP and leaves XUSB alone.

Interface FF/47/D0, or neither interface, runs the default GIP mode. With neither, the log line `No mode of 37D7:2801 matched` lists the interface classes OJD saw. `ojd controller show 37D7:2801` shows the mode in use.

## Evidence

Commit `98b7b0eb6` (2026-07-12) added the GIP record marked `source: local-hardware` and `verified: true`, with endpoints 0x81 and 0x01, `SetConfiguration1BeforeClaim`, and a 200 ms wait. That's evidence about that commit. The record in this checkout has no field for where its data came from. Read the file from that commit with:

```bash
git show 98b7b0eb6:Resources/ControllerOverrides/37d7/37d7-2801.json
```

Linux's `xpad` treats 37D7 as an Xbox 360-style controller, so the record also has the `xusb` mode.

## Status

Not checked on hardware: the controller's interface, the `xusb` endpoints, and which controls each mode sends.

## Steps

1. Plug the controller in with a cable.
2. Run these (`ojd` is the [command-line tool](../../wiki/Command-Line.md)):

   ```bash
   ojd controller list
   ojd controller show 37D7:2801
   ojd controller watch 37D7:2801
   ```

3. Read the mode in the `show` output.
4. Press each control. Check that the name matches the label on the controller.
