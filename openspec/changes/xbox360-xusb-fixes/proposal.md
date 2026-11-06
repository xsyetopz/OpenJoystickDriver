## Why

The Xbox 360 USB driver (`XUSBDriver`) decides slot presence from a heuristic that waits for pad data and resends the inquiry, never tells the receiver to power a pad off, and has no start sequence for wired clones that stay silent until initialized.
Reference drivers disagree with parts of the earlier research, so each claim was checked against the code and the upstream sources first (see `design.md`).
Behavior that needs a receiver or a clone is gated on hardware checks that the maintainer or tester builds run.

## What Changes

- Slot presence: any valid pad report from a receiver slot is presence. The resend heuristic (`XUSBDriver.swift:57-60`, `:261-264`, `:281-288`) and the XUSB use of `receiverInquiryResendLimit` are removed. A time-based inquiry resend is added only if hardware check H2 fails.
- Receiver power-off: the packet `00 00 08 C0` as a family datum, sent on a deliberate session close (including system sleep) for a slot that reports a controller. Named `ReceiverPowerOffOnClose`. It stays off until hardware checks H4 and H5 pass.
- Guide-hold power-off: named `GuideHoldPowerOff`, 5 s as in Linux `xpad`, a tuning value that can be turned off.
- Wired clone start sequence: the three vendor control reads of `paroj/xpad` commit `3470f9f`, as record data on `045e:028e`, gated by the manufacturer string `SHANWAN`, so a genuine pad never receives them.
- A receiver held by another process (Steam) is reported as `DeviceInUse` with its holder; a test pins that no silent retry loop exists.
- Sleep/wake test for a receiver slot, and a check of the interface-to-slot mapping.
- Source licenses: Linux `xpad` and `paroj/xpad` (GPL) give facts only and all code is written independently; MIT code from `zeromiyi/x360w` may be used with its notice in `THIRD_PARTY_NOTICES.md`.

## Capabilities

### New Capabilities

- `xbox360-wireless-receiver`: slot presence, power-off, ownership reporting and slot mapping of the Xbox 360 wireless receiver.
- `xbox360-wired-init`: the gated start sequence of wired Xbox 360 clones.

### Modified Capabilities

None.

## Impact

- `Sources/OpenJoystickDriverKit/Protocol/Drivers/Xbox/XUSBDriver.swift`, `Resources/Protocols/xbox-xusb.json` (the generator writes its Kit copy), the protocol-description schema and loader for the `receiverPowerOff` datum, `Resources/ControllerPatches/045e/`, regenerated records, `Tests/ProtocolPacketFixtures`, `docs/development/wire-protocols.md`, `THIRD_PARTY_NOTICES.md`.
- Hardware needed: receivers `045e:0291`, `0719` (originals) and `02a9` (clone), at least two pads, a SHANWAN-class wired clone, a genuine wired pad, Steam installed.
