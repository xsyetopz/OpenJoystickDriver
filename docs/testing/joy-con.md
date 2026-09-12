# Joy-Con input validation

The catalog imports left Joy-Con `057e:2006` and right Joy-Con `057e:2007` from the
Nintendo HID registrations and HID IDs pinned in `ControllerSources.lock.json`
(Linux revision `44696aa3a489d2baf58efa61b37833f100072bee`). The importer produces
HID records with `joyConLeft` or `joyConRight` layout selection. No local override
or manually authored generated record is used.

## Current evidence

Source-backed: numeric identities, Nintendo full-report layout, IMU enable request,
side-specific primary and SL/SR controls, and the available side's rumble channel.
Rail bits follow [Linux hid-nintendo](https://github.com/torvalds/linux/blob/893e11787f78e43b534e252249ac3fff4d1333f8/drivers/hid/hid-nintendo.c):
left SR/SL use bits 20/21, and right SR/SL use bits 4/5 of the 24-bit button field.

Product tests cover registry selection, HID discovery identities, absent-stick filtering,
opposite-half button filtering, three raw IMU samples, startup command shape, and neutral
rumble bytes for the absent motor. These fixtures are constructed from protocol facts;
they are not captures from physical Joy-Cons.

Implemented in constructed tests: explicit exact-identity paired sessions, one combined remapping
and virtual-output state, configurable left/right/disabled gyro selection, calibrated gyro routing,
stable side normalization, disconnect cleanup, and stale session-ID rejection. Pairing is
process-local and must be explicitly recreated after a disconnect. Charging Grip USB identity and
composite-controller behavior are not covered by these two Bluetooth identities.

## Physical acceptance still required

Use the candidate signed app and record its version, commit, macOS version, and each exact
runtime device selector. Connect each half by Bluetooth separately, then connect both.
Verify that discovery identifies each half and that each physical stick moves only its
corresponding normalized stick. Exercise press/release for every primary and rail button; check
that disconnecting a half releases its output and that reconnect starts fresh.

Verify raw IMU sample delivery after startup, receipt-time gaps, idle behavior, and side
orientation before claiming calibrated motion support. Verify the available rumble motor
and player LEDs independently. Record physical acquisition and virtual-device recognition
separately from parsed input. Repeat the implemented independent and paired routes with a real
consumer.

No hardware, signed consumer, calibration, or paired-session acceptance is claimed here.
