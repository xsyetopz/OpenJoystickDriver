# Joy-Con Input Validation

Left Joy-Con 057e:2006 and right 057e:2007 come from Nintendo HID registrations pinned in `ControllerSources.lock.json` (Linux revision `44696aa3a489d2baf58efa61b37833f100072bee`), as HID records with the `joy-con-left` or `joy-con-right` layout quirk. No override or hand-written record exists.

## Current Evidence

| Evidence | Covers |
| --- | --- |
| Source-backed | Identities, Nintendo full-report layout, IMU enable request, side-specific primary and SL/SR controls, the available side's rumble channel |
| Product tests (protocol facts, no physical captures) | Registry selection, HID discovery identities, absent-stick and opposite-half button filtering, three raw IMU samples, startup command shape, neutral rumble bytes for the absent motor |
| Constructed tests | Exact-identity paired sessions, one combined remapping and virtual-gamepad state, gyro selection (left, right, disabled), calibrated gyro routing, side normalization, disconnect cleanup, stale session ID rejection |

Rail bits follow [Linux hid-nintendo][1]: left SR/SL bits 20/21, right bits 4/5 of the 24-bit button field.

Pairing is process-local; recreate it after a disconnect. Excluded: the Charging Grip USB identity and composite-controller behavior.

[1]: https://github.com/torvalds/linux/blob/893e11787f78e43b534e252249ac3fff4d1333f8/drivers/hid/hid-nintendo.c

## Physical Acceptance Still Required

1. Use the candidate signed app. Record its version, commit, macOS version, each exact device selector.
2. Connect each half by Bluetooth, then both.
3. Check discovery names each half and each stick moves only its own stick.
4. Press and release every primary and rail button.
5. Disconnect a half. Check its output releases and reconnect starts fresh.
6. Before claiming calibrated motion, check raw IMU delivery after startup, receipt-time gaps, idle behavior, orientation.
7. Check the rumble motor and player LEDs separately.
8. Record physical acquisition and virtual-gamepad recognition separately from parsed input.
9. Repeat single and paired routes with a real consumer.

No hardware, signed consumer, calibration, or paired-session result exists.
