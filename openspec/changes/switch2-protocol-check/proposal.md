## Why

The Switch 2 driver (`Switch2Driver`) decodes the 64-byte report `0x05` with one button and stick table for USB and Bluetooth LE, leaves the IMU undecoded, and resends rumble every 12 ms.
A community macOS project (`caqlayan/procon2-mac`, MIT) documents report `0x09`, a different layout and a 4 ms rumble stream. The two sources cannot both be right for the same report without a capture, so this change gathers evidence first and writes code only after the captures exist.

## What Changes

- Capture first: record the input reports of a Pro Controller 2, a GameCube controller and both Joy-Con 2 over USB and Bluetooth LE with the packet capture of the app, and check that the capture keeps every report ID. Fixtures come from those captures.
- Reconcile report `0x05` (OJD, SDL) with report `0x09` (procon2-mac): decide from the captures which report carries the state, whether both exist, and what the driver does with the other.
- Bluetooth LE layout: compare every button bit and both sticks with the one table OJD uses; add a per-transport table only if a capture differs.
- Decode the IMU (accelerometer and gyroscope with flash bias and sample timestamp) after the layout is settled.
- Rumble cadence: measure 4, 8 and 12 ms on hardware, then keep 12 ms or change the datum.
- Check the records for `057E:2069`, `2073`, `2066` and `2067`, and note that SDL names `2068` (Joy-Con pair), which has no record.
- Source licenses: SDL (zlib) code may be used with its notice in `THIRD_PARTY_NOTICES.md`; `procon2-mac` is MIT (its README was read, not its source). GPL sources give facts only.

## Capabilities

### New Capabilities

- `switch2-protocol`: input report identification, motion samples, rumble cadence and records of the Switch 2 family.

### Modified Capabilities

None.

## Impact

- `Sources/OpenJoystickDriverKit/Protocol/Drivers/Nintendo/Switch2Driver.swift`, `Resources/Protocols/nintendo-switch2.json` (and its copy under `Sources/OpenJoystickDriverKit/Resources/Protocols/`), `Sources/OpenJoystickDriverKit/Bluetooth/Switch2BluetoothLEHub.swift` if the capture shows a framing difference, `Resources/ControllerPatches/057e/`, regenerated records, `Tests/ProtocolPacketFixtures`, `docs/development/wire-protocols.md`.
- Hardware needed: Pro Controller 2 (`2069`), NSO GameCube controller (`2073`), Joy-Con 2 left and right (`2067`, `2066`), over USB-C and Bluetooth LE.
