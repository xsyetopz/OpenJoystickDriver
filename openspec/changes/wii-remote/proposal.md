## Why

The Wii Remote (`057E:0306`, and `057E:0330` for the RVL-CNT-01-TR revision) is the one Nintendo Bluetooth controller family with no OpenJoystickDriver protocol. Once macOS Bluetooth has paired it, the remote is a plain `IOHIDDevice` and `IOHIDDeviceSetReport` reaches it, so OJD can read its buttons and sensors and send its LEDs, rumble and speaker data without a kernel extension.
The user decided on 2026-10-25 that Swift code for extension detection, the IR camera and speaker audio is acceptable, so the family covers the whole remote, not only the core buttons.

## What Changes

- New protocol family `NintendoWii` with a protocol description (`Resources/Protocols/nintendo-wii.json`), a Swift driver and a parser test suite built on recorded report fixtures.
- Input: report modes `0x30` to `0x3F`, the core buttons and D-pad, the 10-bit accelerometer, battery and extension state from status reports.
- Extensions: Nunchuk, Classic Controller and Classic Controller Pro, and Motion Plus (gyro), including Motion Plus passthrough. The remote detects the extension on connect and again on hot-plug.
- IR camera: the seven-step register setup with at least 50 ms between writes, and up to four IR points exposed as touch contacts plus a derived pointer.
- Output: player-indicator LEDs, the rumble bit, a status request (battery), and the speaker (4-bit Yamaha ADPCM through reports `0x14`, `0x18`, `0x19` and the speaker registers) exposed as an audio output.
- Two bundled records, `057E:0306` and `057E:0330`, authored under `Resources/Controllers/057e/`; the generated catalog comes from `./Scripts/ojd catalog regenerate --write`.
- New control ids for the pointer (`PointerX`, `PointerY`, `PointerTracking`); motion and touch reuse the existing capability fields.
- Every behavior of the driver has a name, a test and user-facing text (see `design.md` D9).
- Documentation: wiki pages for connecting and using a Wii Remote, `docs/development/wire-protocols.md`, `CHANGELOG.md`.

Not breaking: no existing record, schema value or CLI output changes shape. New schema values are additions.

## Capabilities

### New Capabilities

- `wii-remote`: how OJD reads, configures and drives a Wii Remote and its extensions on macOS.

### Modified Capabilities

None. The requirements of `protocol-descriptions`, `controller-records`, `device-matching` and `control-vocabulary` live in the change `platform-neutral-redesign` and are not in `openspec/specs/` yet. `design.md` D2 and D7 say which of their requirements `wii-remote` relies on, and the tasks add the pointer ids to the vocabulary files of that change.

## Impact

- `Sources/OpenJoystickDriverKit/Protocol/Drivers/Nintendo/` (a `WiiDriver` and its helpers), `ProtocolDriverRegistry.swift` (one `case .nintendoWii`), `PhysicalProtocolID`, `PhysicalControllerOutputCapabilities` (a speaker capability), the `Control` enum.
- `Resources/Protocols/nintendo-wii.json`, `Resources/Controllers/057e/057e-0306.json`, `057e-0330.json`, `Resources/Schemas/` (protocol description sections, `vocabulary.schema.json`), `Resources/ErrorCodes.json`, `Resources/Localization`.
- Tests: `Tests/OpenJoystickDriverKitTests/Protocol/Drivers/Nintendo/`, schema rejection cases, `ProtocolParserCoverageTests` list.
- CLI: `ojd controller speaker play|stop` (see design D8).
- Depends on `platform-neutral-redesign` (records, descriptions, vocabulary) and reuses `declarative-input-layouts` for fixed byte layouts.
- Licenses (user decision, 2026-10-25): OJD moves to PolyForm Noncommercial 1.0.0 plus a separate commercial license, and GPL code cannot be combined with that. WiiBrew is the main reference; wiiuse (GPL-3+) and wiimacmote (no license) supply facts only. The Swift code is written independently from WiiBrew facts and recorded captures, and no code or wording is copied.
- Release: part of alpha.2. Hardware checks may go to external testers through tester builds.

## Out of scope

- Wii Balance Board (also `057E:0306`, product string `Nintendo RVL-WBC-01`) and the Wii U Pro Controller (also `057E:0330`, product string `Nintendo RVL-CNT-01-UC`): the Wii Remote records match by product string (design D3), so neither is driven as a remote. Their drivers are separate changes.
- Guitar Hero, drum, Turntable, uDraw and Wii Fit extensions: an unknown extension ID is reported (D5), not decoded.
- Power-off: no public report exists.
- Pairing automation: pairing is macOS Bluetooth's job.
- SDK endpoint message for speaker audio and pointer mouse emulation beyond the existing `MouseMovement` profile destination.
- Saving audio to the remote's EEPROM or reading Mii data.
