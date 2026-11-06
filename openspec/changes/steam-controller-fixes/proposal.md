## Why

The Steam Controller drivers (2015 `ValveSteamController`, 2026 `ValveSteamTriton`) drop two touch inputs the hardware reports, never use the Triton pad haptic report, and start the 2015 pad with a shorter sequence than SDL.
The earlier research mixed real gaps with items the code already covers; each claim was checked against the code, SDL `release-3.4.16` and Linux `hid-steam.c` (see `design.md`).
Behavior that changes what the controller does is gated on hardware checks that the maintainer or tester builds run.

## What Changes

- Grip capacitive touch of the Triton (bit 28 right, bit 29 left of the button word) decodes into the control ids `RightGripTouch` and `LeftGripTouch`; the vocabulary, crosswalk, schema and every id list gain them (`./Scripts/ojd vocabulary regenerate --write`).
- Triton pad haptic pulse: output report `0x81` (side, on time, off time, repeat count) behind a named output command and capability. Rumble report `0x80` stays as it is; it matches SDL, and a test pins its layout.
- 2015 USB and Bluetooth LE activation adds `LOAD_DEFAULT_SETTINGS` (`0x8E`) and `SMOOTH_ABSOLUTE_MOUSE = 0` (setting 24), as SDL sends. The deactivation is compared with SDL's close sequence.
- Triton lizard handling: optional `CLEAR_DIGITAL_MAPPINGS` and watchdog off (setting 71 = 0), as Linux sends; adopted only if hardware checks pass, together with a deactivation that restores the controller.
- Dongle `1304` and `1305` interface selection (2 to 5) is already in the code; a test for `1305` and a hardware check of the real interface numbers are added.
- Source licenses: SDL (zlib) code may be used with its notice in `THIRD_PARTY_NOTICES.md`. Linux `hid-steam.c` (GPL) gives facts only; all code is written independently.

## Capabilities

### New Capabilities

- `steam-controller-protocols`: grip touch, pad haptic pulse, 2015 activation and Triton lizard handling.

### Modified Capabilities

None.

## Impact

- `Sources/OpenJoystickDriverKit/Protocol/Drivers/Valve/`, `Resources/Protocols/valve-steam-controller.json` and `valve-steam-triton.json` (and their copies under `Sources/OpenJoystickDriverKit/Resources/Protocols/`), `Resources/Schemas/vocabulary.schema.json`, `Resources/Vocabulary/crosswalk.json`, the `Control` type, output command and capability types, virtual mapping, presentation names, localization bundles, `Tests/ProtocolPacketFixtures`, `Tests/RepositoryScripts/test_control_vocabulary.py`, equivalence snapshots, `docs/development/wire-protocols.md`.
- Hardware needed: a 2026 Steam Controller (USB, Bluetooth LE `1303`, dongles `1304`/`1305` if available), a 2015 Steam Controller (USB `1102`, dongle `1142`, Bluetooth LE `1106`).
