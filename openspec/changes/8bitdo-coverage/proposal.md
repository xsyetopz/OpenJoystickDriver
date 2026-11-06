## Why

The bundled catalog has records for ten `2DC8` product IDs, and only `2DC8:310A` is verified on hardware. Several 8BitDo identities that testers can plug in have no record (`301D`, `6012`, `6013`, `3107`, `901B`), two records state a protocol that nothing confirms (`301C` copies the `301B` layout, `3109` is `XboxXUSB`), and the `301B` record maps two usages to each right-stick axis while `docs/testing/8bitdo-ultimate-2c.md` says the stick is on `Z` and `Rz`.
Two 8BitDo bootloader identities (`2DC8:3208`, `2DC8:5750`) can brick a pad when written to, and nothing in the specs forbids traffic to them.
The maintainer owns none of these pads. Testers who own the Ultimate 2C run captures through a tester build, so the plan ships the best record each source supports, marks it unverified, and turns it into a verified one when a tester's capture comes back.

## What Changes

- Best record now, verified later: for each identity in scope, write the record the sources support (the project's own 2C records, the HID usage tables, the research notes), cover it with a test whose fixture is named as source-derived, and list the controller in the Unverified tier. A tester check per identity sends back a descriptor dump and a packet capture; the result replaces the fixture and moves the row to Community-verified, or corrects the record.
- Decisions that a tester capture settles, with the starting choice written in the record's test document:
  - `301C`: idle receiver (one HID interface that is replaced by `310A` after about 6 seconds) or a DInput mode that needs its own layout.
  - `3109`: configuration or standby HID mode, or `XboxXUSB`.
  - `301B` right stick: which of `Z`, `Rx`, `Ry`, `Rz` the descriptor declares for it. The starting record maps `Z` and `Rz` only, as the test document states; the extra `Rx` and `Ry` entries come out.
  - `6012`: whether the cable descriptor (145 bytes) and the dongle descriptor (113 bytes) need separate modes or one usage map covers both.
  - `310B`: whether the Pro 3 and the Ultimate 2 in Switch or Xbox mode can be told apart.
- Add records for `301D` (Ultimate 2C wired, DInput), `6012` (Ultimate 2 DInput), `6013` (Ultimate 2 receiver), `3107` (Ultimate 2 dongle, idle) and `901B` (Ultimate 3-mode, Bluetooth, Xbox).
- Map `L4`, `R4`, `P1` and `P2` to `LeftPaddle1`, `LeftPaddle2`, `RightPaddle1` and `RightPaddle2` for the models that report them as separate inputs.
- Decide, from a tester's macOS measurement, whether the Ultimate 2 gyro in DInput and Switch mode has a path, and whether the roughly 1 second USB watchdog and the dongle drop when nothing reads need a named keep-alive.
- **Requirement:** OJD sends no traffic to `2DC8:3208` and `2DC8:5750`.
- A tester check card for each identity (`docs/testing/8bitdo-tester-checks.md`): the exact commands, the files to send back, and the build to run.
- Docs: `docs/testing/8bitdo-ultimate-2c.md`, a test document for the Ultimate 2 family, `wiki/Supported-Controllers.md` and `wiki/Connecting-Controllers.md` list every 8BitDo model and mode with its VID:PID, protocol and verification state. `CHANGELOG.md` gets the entries.
- Licenses: OJD is licensed under PolyForm Noncommercial 1.0.0 with a commercial license. Code from GPL, AGPL or unlicensed repositories (for example 8bd-u2cw) is a source of facts only: a descriptor layout or byte value may be recorded, and the code is written independently. Sources under MIT, BSD, zlib, CC0 or Apache-2.0 may be used with their notice kept in `THIRD_PARTY_NOTICES.md`.

Out of scope: the vendor configuration protocol (output report `0x81`, input `0x02`, 64-byte and 1592-byte images, CRC-16 variants) unless a capture shows that a pad sends no input without it; submitting records upstream; firmware update paths. The work is part of alpha.2.

## Capabilities

### New Capabilities

- `eightbitdo-controllers`: which 8BitDo identities have a record, how a record moves from unverified to verified, which traffic OJD never sends to an 8BitDo device, and what the documents list.

### Modified Capabilities

None. The `controller-records`, `device-matching` and `control-vocabulary` requirements that these records use are added by `platform-neutral-redesign`; this change only supplies data and documents for them.

## Impact

- `Resources/Controllers/2dc8/` (authored records), `Resources/ControllerPatches/2dc8/` (patches for generated records), then `./Scripts/ojd catalog regenerate --write` for `Sources/OpenJoystickDriverKit/Resources/Controllers/`.
- `Tests/OpenJoystickDriverKitTests/Protocol/` (descriptor fixtures, record behavior, matching), `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections/` for any rejected record.
- `docs/testing/`, `docs/development/wire-protocols.md` (only if a keep-alive becomes data), `THIRD_PARTY_NOTICES.md` (only when a permissively licensed source is used), `wiki/Supported-Controllers.md`, `wiki/Connecting-Controllers.md`, `CHANGELOG.md`.
- Depends on `platform-neutral-redesign` for the record format; no work here changes that format.
