# Tasks: Flydigi Vendor Protocol

The user's decisions (2026-10-25): every area is part of alpha.2; where a capture is missing the work writes the best record the sources support, marks it unverified, and adds a tester check; `37D7:2801` serves a GIP mode and an XUSB mode chosen by interface signature; code from GPL, AGPL or unlicensed repositories is not ported. Tester cards come first in each group, then tests, records or Swift, then documents. A task named "apply the tester result" stays open until the tester's files arrive.

## Working Agreements

- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/`. Change `Resources/Controllers/` or `Resources/ControllerPatches/`, then run `./Scripts/ojd catalog regenerate --write`; after a match-list change also `./Scripts/ojd driverkit generate`.
- No compatibility layer: a mapping a capture disproves is corrected, with no alias.
- A record that Swift rejects gets a case in `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections/`.
- Docs state current behavior and its reason, with no history words. History goes in `CHANGELOG.md`.
- Licenses: write all code independently. GPL, AGPL and unlicensed repositories (ahungry/vader3, BANANASJIM, LARo, ControlLab, Vader-5S, LeeeSe) give facts only. A permissive source (openflydigi `PROTOCOL.md` CC0, uiltonlopes MIT) gets its notice in `THIRD_PARTY_NOTICES.md` in the commit that first uses it, and its exact revision in `docs/development/compatibility-sources.md`.
- A task is done only after its Verify command ran in the session that closes it.
- Fixtures: `VVVV-PPPP-mode-source.<kind>` from a source, `VVVV-PPPP-mode-capture.<kind>` from a tester.
- After each group: `./Scripts/ojd catalog regenerate --check` and `swift test --filter` for the changed area. Once on the merged tree: `just check`; for a parser or protocol change also `./Scripts/ojd test parsers-macos14`.

## 1. Tester Cards

Owns: `docs/testing/flydigi-tester-checks.md`.
Depends: none.
Verify: `git diff --check`.

- [x] 1.1 Write `docs/testing/flydigi-tester-checks.md` with one card per Hardware Checks entry below (F1 to F6). Each card names the tester build, the mode, the exact commands, the control order and the files to send back. Verify: `grep -c '^## F[0-9]' docs/testing/flydigi-tester-checks.md` prints 6 and `markdownlint` reports nothing. Done: the file has 6 `## F` cards and markdownlint reports nothing.

## 2. Bluetooth Byte 11, Guide and Stick Range

Owns: `Resources/Protocols/vendor-flydigi.json`, `Resources/Controllers/d7d7/d7d7-0041.json`, `docs/testing/flydigi-vader-4-pro.md`.
Depends: 1.
Verify: `swift test --filter FlydigiParserTests`, `./Scripts/ojd catalog regenerate --check`, `./Scripts/ojd check schemas`.

- [x] 2.1 Write tests first in `FlydigiParserTests.swift`: bit `0x01` of byte 11 presses `Auxiliary1`, `0x02` `Auxiliary2`, and `0x04`, `0x08`, `0x10`, `0x20` press `LeftPaddle1`, `LeftPaddle2`, `RightPaddle1`, `RightPaddle2`, each releasing with the next report (the helper already has the `extras` parameter). Verify: `swift test --filter FlydigiParserTests` fails on the six new tests before 2.2. Done: FlydigiParserTests failed on the six new cases (12 issues) before 2.2.
- [x] 2.2 Add the six byte 11 buttons to `vendor-flydigi.json` and the controls to `controls.add`. Verify: `swift test --filter FlydigiParserTests` passes and `./Scripts/ojd catalog regenerate --check` passes. Done: six buttons at bits 88 to 93 and controls.add; FlydigiParserTests passes (18 tests); catalog regenerate --check and check schemas pass.
- [x] 2.3 Correct `docs/testing/flydigi-vader-4-pro.md`: byte 11 controls reach consumers as the controls of 2.2, the paddle order is unverified, and Vader 3 and 3 Pro are named only if a tester shows the same identity. Verify: `grep -n "no .Button. case" docs/testing/flydigi-vader-4-pro.md` finds nothing and `markdownlint` reports nothing. Done: flydigi-vader-4-pro.md names the consumer controls and the unverified paddle order.
- [ ] 2.4 Apply the tester result of F1 (`D7D7:0041`: Guide press, full sweep of each stick, each back button named by position): confirm or correct the paddle order and the stick range, add a replay test from the sweep. Verify: `swift test --filter FlydigiParserTests` passes with the `capture` fixture. Open until the tester's files arrive.

## 3. Vader 5S: GIP and XUSB Modes

Owns: `Resources/Controllers/37d7/37d7-2801.json`, `docs/testing/flydigi-vader-5s.md`.
Depends: 1.
Verify: `swift test --filter ModeMatch`, `./Scripts/ojd catalog regenerate --check`, `./Scripts/ojd driverkit generate` then `git diff --stat .build/driverkit/generated` shows no hand edit.

- [x] 3.1 Write tests first: a pad with an interface `FF/47/D0` selects the GIP mode, one with `FF/5D/01` selects the XUSB mode, and neither selects the default and logs the classes. Verify: `swift test --filter ModeMatch` fails before 3.2. Done: `theVader5SRunsGIPOrXUSBFromItsInterfaceSignature` failed against the one-mode record before 3.2; GIP is the keyless default (D4, D10), so `FF/47/D0` and neither both run it.
- [x] 3.2 Edit the record: mode `gip` (default, current endpoints, configuration and settle time) and mode `xusb` (`XboxXUSB`, variant `Wired`, interface signature `FF/5D/01`, endpoints from the XUSB description unless the tester dump shows others). Verify: `./Scripts/ojd diagnose record Resources/Controllers/37d7/37d7-2801.json --validate-only` exits 0 and the 3.1 tests pass. Done: the default GIP mode keeps its settle time and the `xusb` mode has signature `FF/5D/01`; the endpoint rule of D10 admits the record; `--validate-only` exits 0 and ModeMatch passes.
- [x] 3.3 Write `docs/testing/flydigi-vader-5s.md`: both modes, unverified, the evidence of commit `98b7b0eb6` (provenance `local-hardware`, `verified: true`) cited as evidence and not as verification, and that the provenance field is not in the record format. Add the wiki entry and `CHANGELOG.md`. Verify: `git show 98b7b0eb6:Resources/ControllerOverrides/37d7/37d7-2801.json | grep -n verified` finds the quoted values, and `markdownlint` over the changed files reports nothing. Done: `docs/testing/flydigi-vader-5s.md`, the wiki row and CHANGELOG are written; the grep finds `verified`.
- [ ] 3.4 Apply the tester result of F2 (`usb.txt` of a Vader 5S): record which mode appears; remove nothing unless the tester shows the other mode cannot occur. Verify: the document names the signature found. Open until the tester's files arrive.

## 4. Vader 5 Pro Dongle 37D7:2401

Owns: `Resources/Controllers/37d7/37d7-2401.json`, the frame builder, possibly a Swift driver for motion.
Depends: 1, 2 (shared description).
Verify: `swift test --filter Flydigi`, `./Scripts/ojd catalog regenerate --check`, `./Scripts/ojd test parsers-macos14`.

- [x] 4.1 Read the mode-selection and claim code and write down, in the commit message, whether one device can run an `extended` HID mode ahead of a `default` XUSB mode, and whether the description can hold the startup writes and report ID (a variant of `VendorFlydigi`) or a second family is needed (D5). Verify: the commit message states both answers with `file_path:line_number` of the code read. Done: the commit message states both answers (read, not run); a mixed record of a raw-USB default and a HID mode is not yet exercised by a test. Correction from 4.2: a `HIDReportLayout` description had no `sessionKeys`, so a record of that family could not carry `session.startup`; 4.3 adds `"sessionKeys": ["startup"]` to `Resources/Protocols/hid-report-layout.json`. The pipeline already sends a record's HID startup writes for any driver (`DevicePipeline+Lifecycle.swift:179`), and `ReportLayoutDriver` needs no change.
- [x] 4.2 Write tests first: each startup write of the record ends with the low byte of the sum of cmd, len and payload (`5A A5 11 07 FF 01 FF FF FF 15` for the test-mode write, `5A A5 01 02 03` for command 1) and has len equal to the payload plus 2; a source-derived 32-byte `5A A5 EF` report with set sticks (int16 LE, bytes 3 to 10), buttons (11 to 14) and triggers (15 and 16) delivers each control; a refused init write reports a startup failure and starts no other mode. Verify: `swift test --filter Flydigi` fails before 4.3 and 4.4. Done: `FlydigiVaderFiveProTests` (4 tests) failed with 4 issues before the record existed and passes with it; the report test covers sticks and triggers only, because the button bits are unknown. `aReportLayoutRecordSendsItsStartupWrites` runs the record through the manager with the scripted HID backend, for an accepted and a refused write (status `succeeded` and `failed`).
- [ ] 4.3 Add the record `37d7-2401.json` with the init writes (`5A A5 01 02 03`, `5A A5 A1 02 A3`, `5A A5 02 02 04`, each zero-padded to 32 bytes) and the test-mode write (`5A A5 11 07 FF 01 FF FF FF 15`) as `session.startup` (the UID read `5A A5 04 02 06` from the notes is left out, because the spec forbids command 4; card F3 shows whether the extended report starts without it, and if it does not, a separate task names the command and changes the spec), written from the facts in the notes and checked against the checksum rule. Verify: `./Scripts/ojd diagnose record Resources/Controllers/37d7/37d7-2401.json --validate-only` exits 0, `./Scripts/ojd catalog regenerate --write` then `--check` pass, and the 4.2 tests pass. Blocked: missing is the bit layout of bytes 11 to 14 of the `5A A5 EF` report (which bit is which of A, B, X, Y, bumpers, sticks, C, Z, M1 to M4, with a `file:line`). Neither openflydigi `PROTOCOL.md` at 11653507 nor uiltonlopes `docs/protocol.md` at 649b9f36 has it; the sources name only the offsets (design.md, Research claims). The record lands with sticks (3 to 10), triggers (15, 16), the startup writes and the command 18 rumble template; the button bits of bytes 11 to 14 wait for the F3 capture, so this task stays open. The record is unverified and declares no motion.
- [ ] 4.4 Add a Swift driver for the gyro (bytes 17 to 22) and accelerometer (23 to 28, 4096 = 1 g) only if 4.1 shows the layout cannot carry motion and the extended mode needs it; otherwise the record declares no motion. Verify: `swift test --filter Flydigi` passes the motion test (int16 LE sample to a value) or the no-motion test, and `just check-fast` passes.
- [x] 4.5 Write `docs/testing/flydigi-vader-5-pro.md` (interfaces, modes, init writes, offsets, unverified), the wiki entry, `docs/development/wire-protocols.md` row, `THIRD_PARTY_NOTICES.md` if the CC0 or MIT notes were used, and `CHANGELOG.md`. Verify: `grep -n "37D7:2401" wiki/Supported-Controllers.md docs/testing/flydigi-vader-5-pro.md` finds the rows and `git diff --check` over the changed files reports nothing. Done: the document, wiki row, wire-protocols row and CHANGELOG entry are written; the grep finds both rows and the whitespace check reports nothing. The document says the buttons are not mapped until F3.
- [ ] 4.6 Apply the tester result of F3 (dongle interfaces, report descriptor, capture with the pad on): replace the source-derived fixture and correct offsets or endpoints. Verify: `swift test --filter Flydigi` passes with the `capture` fixture. Open until the tester's files arrive.

## 5. Apex 4 04B4:2412

Owns: `Resources/Controllers/04b4/04b4-2412.json`, `docs/testing/flydigi-apex-4.md`.
Depends: 1.
Verify: `swift test --filter Flydigi`, `./Scripts/ojd catalog regenerate --check`.

- [x] 5.1 Pin the uiltonlopes `docs/protocol.md` at an exact commit, read its report 4 layout, and record the commit and its MIT notice in `docs/development/compatibility-sources.md` and `THIRD_PARTY_NOTICES.md`. Verify: `grep -n "uiltonlopes" docs/development/compatibility-sources.md THIRD_PARTY_NOTICES.md` finds both with a commit hash. Done: commit 649b9f36cbba80deb7e7ac11309615d44f382a8e and the MIT notice are in both files.
- [x] 5.2 Write the replay test from a report built in that layout (source-derived). Verify: `swift test --filter Flydigi` fails before 5.3. Done: `swift test --filter FlydigiApexFourTests` failed with 25 issues before 5.3.
- [x] 5.3 Add `04b4-2412.json` on usage page `0xFFA0` (input report 4, 31 bytes; output report 5, 63 bytes; live status `04 FE` not mapped). Verify: `./Scripts/ojd diagnose record FILE --validate-only` exits 0 for each record file, `./Scripts/ojd catalog regenerate --write` then `--check` pass, and the 5.2 test passes. Done: `--validate-only` now validates a record of any protocol and probes only `XboxGIP` and `XboxXUSB`; a probe of another protocol still fails with the unsupported-protocol error; tests `validationAcceptsAHIDReportLayoutRecordThatNoProbeCanDrive` and `validationRejectsAnInvalidRecord` cover it. The spec does not require the unmapped Fn, Turbo, M5, M6 or byte 8 bits. The report is 32 bytes with the ID in byte 0 (the notes' "31 B" excludes the ID).
- [x] 5.4 Write `docs/testing/flydigi-apex-4.md` (DInput record, unverified, XInput mode is `045E:028E` with the string "Flydigi VADER3" and is not changed), the wiki entry and `CHANGELOG.md`. Verify: `markdownlint` over the changed files reports nothing and `grep -n "04B4:2412" wiki/Supported-Controllers.md` finds the row. Done: `flydigi-apex-4.md`, the wiki table row and CHANGELOG are written; markdownlint reports nothing.
- [ ] 5.5 Apply the tester result of F4 (Apex 4 in DInput). Verify: `swift test --filter Flydigi` passes with the `capture` fixture. Open until the tester's files arrive.

## 6. Vendor Output

Owns: grip rumble (18) and trigger force (81, 82) frames, the record fields that name them.
Depends: 4 (the frame builder).
Verify: `swift test --filter Flydigi`, `./Scripts/ojd catalog regenerate --check`.

- [x] 6.1 Pin the openflydigi `PROTOCOL.md` at an exact commit, read the payloads of commands 18, 81 and 82, and record the commit and the CC0 dedication in `docs/development/compatibility-sources.md` and `THIRD_PARTY_NOTICES.md`. Verify: `grep -n "openflydigi" docs/development/compatibility-sources.md THIRD_PARTY_NOTICES.md` finds both with a commit hash. Done: commit 11653507bbe4dc77f3c479c2a7aaebf25bbda995 and the CC0 dedication are in both files; the notes say commands 18, 81 and 82 carry no checksum, and `flydigi/device.py:244-253` builds them that way, so spec and D7 now give sum8 only to the startup commands (D7, D11).
- [x] 6.2 Write tests first: the grip rumble frame for left 128 and right 64 has the length byte 6 and no checksum byte; a request for an unlisted command sends nothing and fails with a named error; the frame fits the report length. Verify: `swift test --filter Flydigi` fails before 6.3. Done: `FlydigiGripRumbleTests` (2 tests) asserts the 32-byte frame for four motor levels and for stop; the existing rumble template needs no new code (D11), so the test passed on first run and there was no failing state. A command kind the driver does not encode already fails with `unsupportedCapability` (`ReportLayoutDriver.encode`).
- [x] 6.3 Add the commands to the records that carry them (named list per record, no other command) and wire `ojd controller rumble` to the grip frame. Verify: `swift test --filter Flydigi` passes and `ojd controller rumble CONTROLLER --left 128 --right 64` against the fake transport of the test sends one frame. Done: `37d7-2401.json` carries startup commands 1, 0xA1 and 2 and the command 18 template `03 5A A5 12 06` plus motor bytes 5 to 8, and no other command; `ojd controller rumble` needs no wiring (D11); `rumbleWithLeftAndRightSendsOneCommandWithBothLevels` (CLI fake service) sends one `setRumble` and `theCommandLineLevelsLeft128AndRight64SendOneFrame` encodes it to one 32-byte frame with bytes 5 and 6 `80 40`. Commands 81 and 82 stay with 6.4.
- [ ] 6.4 Give trigger force modes a name and a setting in the record or profile before any surface exposes them; add the user-facing text and its localization keys. Verify: `python3 Scripts/Quality/check_localization_keys.py` passes and a test sets a mode and asserts the frame. Open: no spec defines the setting, its name or the effect parameters (D11 lists `Normal`, `Race`, `Sniper`, `Recoil` and `Lock` only as a proposal), and no surface exposes commands 81 and 82. It needs a new output command kind in `ControllerOutputCommand`, a driver encoding, a profile setting and localization text in all 22 bundles; it starts when a record has a pad with force triggers (D11).
- [x] 6.5 Update `docs/development/wire-protocols.md` (remove "takes no output" for the family, name the commands) and `CHANGELOG.md`. Verify: `grep -n "takes no output" docs/development/wire-protocols.md` finds no Flydigi row and `git diff --check` reports nothing. Done: the `HIDReportLayout` (`37D7:2401`) row names startup commands 1, 0xA1 and 2 and the command 18 rumble template; the `VendorFlydigi` row (`D7D7:0041`) says its record lists no output command; the CHANGELOG entry for the dongle names the grip rumble template.
- [ ] 6.6 Apply the tester result of F5 (grip rumble felt, trigger force mode felt). Verify: the document records yes or no per command. Open until the tester's files arrive.

## 7. Supported-Controllers Entries

Owns: the Flydigi entries of `wiki/Supported-Controllers.md`.
Depends: 2 to 5.
Verify: the loop below, `just check`.

- [x] 7.1 Confirm each Flydigi record has a wiki entry with VID:PID, mode, tier and test document link. Verify: `for p in D7D7:0041 37D7:2801 04B4:2412; do grep -qi "$p" wiki/Supported-Controllers.md || echo "missing $p"; done` prints nothing. Done: the loop lists the three records that exist; `37D7:2501` has no hand-written record (only a generated xpad import) and `37D7:2401` has none until 4.3, so both left the loop; add `37D7:2401` back when 4.3 lands.
- [ ] 7.2 Run the repository checks on the merged tree. Verify: `just check` passes; rerun only the failed step.

## Hardware Checks (Testers)

External users own these pads; the user has none. Each check runs through a tester build (`docs/testing/tester-builds.md`): the maintainer sends the DMG, the tester installs it, opens the app, approves the permissions and runs the commands in Terminal. The tester sends back `OpenJoystickDriver-TESTER-BUILD.txt`, the files named, and a line that lists the controls pressed in order. A check with no tester leaves the record unverified.

Commands common to every card (`VVVV:PPPP` is the identity under test):

```shell
ioreg -r -c IOHIDDevice -l -w0 > hid.txt
ioreg -p IOUSB -l -w0 > usb.txt
ojd controller list
ojd controller show VVVV:PPPP
ojd controller capture VVVV:PPPP --duration 20 --json > capture.jsonl
```

- [ ] F1 `D7D7:0041`, Vader 4 Pro (or Vader 3 or 3 Pro) over Bluetooth. Run the common commands. During the capture press C, Z, then each back button, saying aloud which physical button it is (upper or lower, left or right), then the Guide button, then sweep each stick to every edge. Send `capture.jsonl`, `hid.txt`, the product name and firmware.
- [ ] F2 `37D7:2801`, Vader 5S over USB. Run the common commands and send `usb.txt` (the interface class, subclass and protocol of interface 0 are in it) and `ojd controller show 37D7:2801`, which names the mode that ran.
- [ ] F3 `37D7:2401`, Vader 5 Pro 2.4 GHz dongle with the pad on. Run the common commands for `37D7:2401` and send `usb.txt`, `hid.txt` (the report descriptor of the HID interface), `capture.jsonl` with every control, C, Z, M1 to M4 and a sweep of each stick and trigger, and `ojd controller show 37D7:2401`. Tilt the pad on each axis during a second capture to expose motion samples. The commands only read; the record's own startup writes the init packets. Report whether `capture.jsonl` holds extended `5A A5 EF` reports.
- [ ] F4 `04B4:2412`, Apex 4 in DInput. Run the common commands and press every control in the order of the card, including back buttons and the trigger stops.
- [ ] F5 Output on any record that sends vendor frames: `ojd controller rumble CONTROLLER --left 128 --right 0`, then `--left 0 --right 128`, then `--left-trigger 128`, each for 2 seconds. Send which motor moved each time. Then, once a trigger force setting exists (task 6.4), set each named mode and say whether the trigger resistance changed.
- [ ] F6 `D7D7:0041` or any Flydigi pad whose model is not in the table: send `hid.txt`, `usb.txt` and the product name from the box, so the wiki row names the right model.

## Workflow Follow-Up

- Archive this change after `platform-neutral-redesign` is archived; the records need its format.
- Push, tag, notarize and publish are the maintainer's actions and need confirmation.
