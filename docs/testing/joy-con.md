# Joy-Con Input Validation

A Joy-Con is one half of a Nintendo Switch controller. You can use one alone, or pair a left and a right to make one controller. The left Joy-Con is 057e:2006 and the right is 057e:2007. OJD takes both from the Nintendo HID list pinned in `ControllerSources.lock.json` (Linux revision `44696aa3a489d2baf58efa61b37833f100072bee`). They're HID records with the `joy-con-left` or `joy-con-right` layout quirk. There's no hand-written record or override.

## What's Been Checked

| How it was checked | What it covers |
| --- | --- |
| Read from source code | Identities, Nintendo's full-report layout, the request that turns on motion, each side's main and SL/SR buttons, the rumble motor on the side you have |
| Product tests (protocol facts, no real captures) | Which record OJD picks, HID discovery identities, ignoring the missing stick and the other half's buttons, three raw motion samples, the startup command's shape, quiet rumble bytes for the missing motor |
| Tests on made-up input | Pairing sessions with exact identities, one shared remapping and virtual-gamepad state, choosing which gyro to use (left, right, off), routing the calibrated gyro, making both sides look alike, cleanup after a disconnect, refusing an old session ID |

The rail buttons follow [Linux hid-nintendo][1]: left SR/SL are bits 20/21, right are bits 4/5 of the 24-bit button field.

A pair lasts only while the app runs. Make it again after a disconnect. Not covered: the Charging Grip's USB identity and how the halves act as one composite controller.

[1]: https://github.com/torvalds/linux/blob/893e11787f78e43b534e252249ac3fff4d1333f8/drivers/hid/hid-nintendo.c

## Still Needs a Real Test

1. Use the signed test app. Write down its version, commit, the macOS version, and each exact device selector.
2. Connect each half by Bluetooth, then both.
3. Check that OJD names each half and that each stick moves only its own stick.
4. Press and let go of every main and rail button.
5. Disconnect one half. Check that its output lets go and that reconnecting starts clean.
6. Before you claim motion is calibrated, check that raw motion arrives after startup, how big the gaps are, how it acts at rest, and which way is up.
7. Check the rumble motor and the player lights one at a time.
8. Write down whether OJD got the device and whether games saw the virtual gamepad, apart from whether input read right.
9. Repeat with one half and with a pair, in a real game.

There's no result yet from hardware, a signed game, calibration, or a pair.
