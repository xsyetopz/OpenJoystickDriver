## Why

The bundled Flydigi support is one Bluetooth record and two USB records, and it leaves out most of what these pads send:

- `Resources/Protocols/vendor-flydigi.json` decodes the 15-byte report of `D7D7:0041` but nothing at byte 11, where C, Z and the four back buttons are. `docs/testing/flydigi-vader-4-pro.md` lists them as decoded and says they reach no consumer; the description names only `Guide` as an added control, so they are not decoded.
- `37D7:2801` (Vader 5S) is one `XboxGIP` mode. The evidence for GIP is a July record whose provenance field no longer exists in the record format, and Linux `xpad` binds `37D7` as a 360-class pad. Nobody can say from the tree which interface the pad shows.
- `37D7:2401` (Vader 5 Pro 2.4 GHz dongle), `04B4:2412` (Apex 4, DInput) and any Flydigi output have no record, and `docs/development/wire-protocols.md` states that the Flydigi family "takes no output".
- `wiki/Supported-Controllers.md` has no Flydigi entry.

The user has no Flydigi pad to test here; external users do. The plan therefore ships the best record the sources support, marks it unverified, and gives testers exact captures to send back.

## What Changes

- Decode byte 11 of the Bluetooth report: C and Z as `Auxiliary1` and `Auxiliary2`, the four back buttons as the four paddle controls. The report offsets count the report ID as byte 0; the captured reports in `FlydigiParserTests` already fix that. A tester capture confirms which physical button each paddle control is.
- Check the Guide bit (byte 12, mask 128) and the stick range against a tester sweep. The record's range (-128 to 127, from the captured neutral `FF`) stays unless the sweep shows another extreme.
- `37D7:2801` serves both interfaces it may show: one `XboxGIP` mode (`FF/47/D0`) and one `XboxXUSB` mode (`FF/5D/01`), selected by interface signature. A tester confirms which appears. `docs/testing/flydigi-vader-5s.md` records the July GIP evidence as evidence of the pad's state at that time, not as verification.
- Add `37D7:2401` (Vader 5 Pro dongle): `XboxXUSB` on interface 0, and the extended 32-byte report (`5A A5 EF`) on HID interface 1 after the init writes and the test-mode write. A declarative layout (16-bit axes, button bits, triggers) carries the controls; a Swift driver is added only for the gyro and accelerometer fields that the record format cannot describe.
- Add `04B4:2412` (Apex 4, DInput; vendor usage page `0xFFA0`, input report 4, output report 5).
- Vendor output with `5A A5 cmd len payload sum8` framing, limited to the named commands: grip rumble (command 18, with the trigger motors) and trigger force modes (81 and 82). Every other command (screen upload, UID, sync) is not sent.
- Documents: `docs/testing/flydigi-vader-4-pro.md`, new test documents for the 5S, 5 Pro and Apex 4, `docs/development/wire-protocols.md`, `wiki/Supported-Controllers.md`, `CHANGELOG.md`.
- Licenses: OJD is licensed under PolyForm Noncommercial 1.0.0 with a commercial license. Code from ahungry/vader3, BANANASJIM, LARo, ControlLab, Vader-5S and LeeeSe (GPL, AGPL or unlicensed) is a source of facts only (offsets, byte values, framing); the Swift and the records are written independently. Sources under MIT, BSD, zlib, CC0 or Apache-2.0 (openflydigi `PROTOCOL.md`, uiltonlopes `docs/protocol.md`) may be used with their notice kept in `THIRD_PARTY_NOTICES.md`. A task that adds such a source adds the notice in the same commit.

Out of scope: the screen upload (CDC `FFAA:5555`), UID and sync commands, unknown PIDs (Vader 4 Pro wired and dongle, Vader 5 Pro wired and Switch, Apex 5 DInput), changing the Microsoft `045E:028E` record that the Apex 4 XInput mode shares. This is part of alpha.2.

## Capabilities

### New Capabilities

- `flydigi-controllers`: which Flydigi identities have a record and in which modes, the inputs and outputs each mode delivers, the vendor commands OJD sends, and what the documents say.

### Modified Capabilities

None. The `controller-records`, `protocol-descriptions` and `device-matching` requirements these records use are added by `platform-neutral-redesign`; this change supplies data, one possible Swift driver and documents for them.

## Impact

- `Resources/Protocols/vendor-flydigi.json`, `Resources/Controllers/d7d7/`, `Resources/Controllers/37d7/`, `Resources/Controllers/04b4/` (created), then `./Scripts/ojd catalog regenerate --write` and, for any match-list change, `./Scripts/ojd driverkit generate`.
- A Swift driver and its description only if the motion fields require one (`Sources/OpenJoystickDriverKit/Protocol/`).
- `Tests/OpenJoystickDriverKitTests/Protocol/Drivers/Vendor/FlydigiParserTests.swift` and new tests beside it; `SchemaRejections` cases for any rejected record.
- `docs/testing/`, `docs/development/wire-protocols.md`, `docs/development/compatibility-sources.md`, `THIRD_PARTY_NOTICES.md`, `wiki/Supported-Controllers.md`, `CHANGELOG.md`.
- Depends on `platform-neutral-redesign` for the record format, and on `declarative-input-layouts`, which lands first: every field this change adds to `vendor-flydigi.json` and the records uses `bitOffset` and `bitSize`, not `byte` and `mask`.
