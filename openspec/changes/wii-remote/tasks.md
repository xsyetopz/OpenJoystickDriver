# Tasks: Wii Remote

Order follows dependencies: fixtures and tests first, then the description and the Swift driver, then records, then documentation, then the maintainer's hardware checks.

## Working agreements

- Do not edit generated records in `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`. Change authored inputs under `Resources/Controllers/`, then run `./Scripts/ojd catalog regenerate --write`.
- WiiBrew is the reference. wiiuse (GPL-3+) and wiimacmote (no license) give facts only: no code, structure, comments or wording are copied, because the project license (PolyForm Noncommercial 1.0.0 plus a commercial license) cannot include GPL code. The Swift code is written independently from WiiBrew facts and captures.
- Scope: part of alpha.2. Tasks in group 10 may be run by external testers with tester builds.
- Fixtures are recorded reports as hex, one file per case, with the source named in a header line (WiiBrew page or hardware capture). A fixture from WiiBrew is marked as such until Hardware Check 3 replaces it.
- Reuse `declarative-input-layouts` for fixed byte layouts. A primitive it does not provide stays in Swift and is listed in the "Coded Behavior" part of `docs/development/wire-protocols.md` (task 7.2).
- `wii-remote` and `steam-controller-fixes` both add control ids (`PointerX`, `PointerY`, `PointerTracking`; `LeftGripTouch`, `RightGripTouch`) to the same vocabulary files. The ids differ; the change that lands second rebases on the first and runs `./Scripts/ojd vocabulary regenerate --write` again.
- Every task states how to verify it. A task is done only after that check ran in the session that closes it.
- Check list for the closing task of a group: `swift test --filter` of the named suite, `swift-format lint --recursive --strict Package.swift Sources Tests Tools`, `swiftlint lint --no-cache --strict`; run `just check` once at task 9.1.

## 1. Report fixtures

Owns: `Tests/OpenJoystickDriverKitTests/Protocol/Drivers/Nintendo/Fixtures/Wii/`.
Depends: none.

- [x] 1.1 Record fixtures for input: status `0x20` (no extension, extension, battery full and low), read reply `0x21` (success, error nibble), acknowledgement `0x22` (success, error), and one report for each mode `0x30` to `0x37`, `0x3D`, and the pair `0x3E`/`0x3F`. Verify: `ls` of the fixture folder lists each id and a test `WiiFixtureIndexTests` fails when a mode id of the description has no fixture; `swift test --filter WiiFixtureIndexTests`. Done: 19 WiiBrew-derived `.hex` files in the fixture folder, named `<id>-<case>`; `WiiFixtureIndexTests` also checks the header, the leading report id and the length against the description's layout.
- [x] 1.2 Record extension fixtures: the six-byte ID replies for Nunchuk, Classic Controller, Classic Controller Pro, Motion Plus inactive, Motion Plus with Nunchuk passthrough, Motion Plus with Classic passthrough; 6-byte data samples (rest, extremes) for Nunchuk, Classic and Motion Plus (slow and fast). Verify: `WiiFixtureIndexTests` covers every extension kind of the description. Done: seven id replies (one per description extension kind; inactive Motion Plus read at A600FA) and data samples in Fixtures/Wii/Extensions (Nunchuk, Classic, Motion Plus slow and fast), each WiiBrew-derived with page revision; WiiFixtureIndexTests checks each kind and the 6-byte length.
- [x] 1.3 Record IR fixtures: basic (10 bytes), extended (12 bytes) with 0, 1, 2 and 4 visible points, and a full-mode pair. Verify: `WiiFixtureIndexTests` lists each IR format. Done: Fixtures/Wii/IR holds basic (4 points), extended (0, 1, 2, 4 points) and a full pair; byte 7 of a full-format point is left 0 because WiiBrew leaves it unstated.
- [x] 1.4 Record the output byte sequences expected for the handshake, Motion Plus activation, IR setup (all seven steps) and speaker setup, each with rumble off and on. Verify: `WiiFixtureIndexTests` finds both variants of each sequence. Done: Fixtures/Wii/Sequences holds handshake, Motion Plus (plain, Nunchuk, Classic), IR (level 3, extended mode) and speaker, each with rumble-off and rumble-on; WiiFixtureIndexTests rebuilds each from the description scripts and compares bytes.

## 2. Protocol description tests

Owns: tests for `Resources/Protocols/nintendo-wii.json`.
Depends: 1.

- [x] 2.1 Add schema-rejection cases for the description in `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections/`: an `irWriteIntervalMs` below 50, a report mode id outside `0x30` to `0x3F`, an extension ID of the wrong length, a layout that overlaps two blocks. Verify: `swift test --filter SchemaRejectionTests` passes with 3.1. The cases landed in the same commit as 3.1, so no run shows them failing first.
- [x] 2.2 Add the family to the `ProtocolParserCoverageTests` list with the suite name `WiiDriverTests`. Verify: `swift test --filter ProtocolParserCoverageTests` fails until `WiiDriverTests` exists (task 4.1). Done: `WiiDriverTests` is listed and `ProtocolParserCoverageTests` passes; the catalog-binding test helpers pass the first mode of a record without a default mode and use a Bluetooth host for a Bluetooth-only family.

## 3. Description and vocabulary

Owns: `Resources/Protocols/nintendo-wii.json`, `Resources/Schemas/protocol-description.schema.json`, `vocabulary.schema.json`, `Scripts/Catalog/generate_crosswalk.py`.
Depends: 1, 2.
Verify: `./Scripts/ojd check schemas`, `./Scripts/ojd catalog regenerate --check`.

- [x] 3.1 Write the description: variant `BluetoothClassic`, report ids, the mode-to-layout table, core button bits, accelerometer bit positions, Nunchuk and Classic layouts (using the `declarative-input-layouts` primitives available), the extension ID table, the handshake, Motion Plus, IR and speaker scripts with their addresses and bytes, LED bits, rumble bit, tuning keys (`irWriteIntervalMs` default 50 minimum 50, `speakerMaxSeconds`, the reply timeouts). Verify: `swift test --filter SchemaRejectionTests` passes and `./Scripts/ojd check schemas` passes. Done: `nintendo-wii.json` (Resources and the bundled copy) holds the `wiiRemote` session field: rumble and LED bits, core buttons, accelerometer low bits, eleven report modes as block layouts, the extension id table, IR sensitivity levels, and the handshake, Motion Plus, IR, speaker and speaker-stop scripts. The schema and `ProtocolDescription.WiiRemote` validate it. `irWriteIntervalMs` (minimum 50), `speakerMaxSeconds` and `replyTimeoutMs` are record-overridable tuning keys (`tuningKeys`, `defaults.tuning`). The Nunchuk and Classic layouts are `extensions[].layout` (design D13). The 16 Wii rejection cases and the whole `SchemaRejectionTests` suite pass.
- [x] 3.2 Add the protocol id `NintendoWii` to the schema enums and to `PhysicalProtocolID`. Verify: `swift test --filter ProtocolDescriptionTests` loads the description; a test lists the family in the protocol-id enum. Done: `NintendoWii` is in `PhysicalProtocolID` (session field `wiiRemote`), the controller and report schema enums, the localization strings, the command-line name samples and the exhaustive switches; the registry returns no driver for it until 4.2. `ProtocolDescriptionTests` loads the description.
- [x] 3.3 Add `PointerX`, `PointerY`, `PointerTracking` to `vocabulary.schema.json` and the `Control` enum, with the crosswalk rows marked "none" for W3C, SDL3, evdev, HID and Apple. Verify: the existing test that keeps `Control` equal to `$defs/control` passes, and `./Scripts/ojd check schemas` passes. Done: the three ids are in `Control`, `vocabulary.schema.json` and `crosswalk.json` (all five columns empty); the wiki crosswalk table was regenerated; the exhaustive switches in the virtual report mapping and the presentation labels name them; the Control-list, persona and profile tests include them. `ControlVocabularyTests`, `ControllerDomainTests`, `VirtualHIDProfileTests`, `PersonaControlMappingTests` and `generate_crosswalk.py --check` pass. `./Scripts/ojd check schemas` validates all documents.
- [x] 3.4 Add the speaker output capability to `PhysicalControllerOutputCapabilities` and the capabilities schema. Verify: a unit test round-trips the capability through Codable, and `./Scripts/ojd check schemas` accepts the report and CLI-output schemas with it (records carry no output capabilities; the protocol gives them). Done: `PhysicalSpeakerFormat.yamahaADPCM4Bit` is the optional `speaker` on `PhysicalControllerOutputCapabilities`, in the report and CLI-output schemas and `ojd controller` output; profile intersection keeps it only when both sides match. `ControllerProfileCapabilitiesTests` round-trips it.

## 4. Driver: input, status, extensions

Owns: `Sources/OpenJoystickDriverKit/Protocol/Drivers/Nintendo/WiiDriver*.swift`, `ProtocolDriverRegistry.swift`.
Depends: 3.

- [x] 4.1 Create `WiiDriverTests` with failing cases from the spec scenarios: core buttons to controls (A to `South`), accelerometer 10-bit reassembly (`0x84` with low bits `0b10` is `0x212`), battery `0x64` to 50 percent, each mode fixture decoded. Verify: `swift test --filter WiiDriverTests` fails for the right reason (missing driver). Done: `WiiDriverTests` conforms to the `ParserSuite` shape (family, model `057E:0306`).
- [x] 4.2 Implement `WiiDriver` for core buttons, accelerometer, status and battery, with the layout from the description; register `.nintendoWii` in `ProtocolDriverRegistry.makeDriver`. Verify: the 4.1 cases pass and `swift test --filter ProtocolDriverRegistryTests` constructs the driver for a `NintendoWii` record.
- [ ] 4.3 Implement the report-mode choice (`ReportModeSelect`) and the restore after each `0x20` (`ReportModeRestore`), with the continuous bit rule. Verify: tests for all 16 modes, and a test where a status fixture yields exactly one `0x12` with the chosen mode.
- [ ] 4.4 Implement accelerometer calibration from the EEPROM read (`0x17`, flags 0, address `0x0016`) and memory-reply reassembly (`0x21`, size and error nibble) with one outstanding read. Verify: fixture tests for success, error nibble and a mismatched address (the reply is refused, named).
- [ ] 4.5 Implement the extension handshake, hot-plug and `Unknown` kinds (`ExtensionHandshake`, `ExtensionRemoved`, `UnknownExtension`, `ExtensionHandshakeFailed`), without retry. Verify: tests with fixture replies for each kind; an unplug test where `LeftStickX` returns to 0; a timeout test with an injected clock that asserts no further write.
- [ ] 4.6 Implement the Nunchuk and Classic decode, and extension calibration read from `0xA40020`. Verify: extremes and rest fixtures give 1.0, -1.0 and 0; Classic `a` gives `East`.
- [ ] 4.7 Implement Motion Plus activation, 14-bit decode with slow/fast flags, passthrough demultiplexing, and `GyroRestOffset`. Verify: fast flag scale test; an alternating-frame test where each frame changes only its own controls.
- [ ] 4.8 Declare capabilities and expose motion through the existing `motion` capability. Verify: `swift test --filter WiiDriverTests` checks the capability set for a bare remote and with each extension.

## 5. Driver: outputs, IR and speaker

Owns: `WiiDriver+Output.swift`, `WiiDriver+IR.swift`, `WiiSpeaker*.swift`, `ControllerSpeakerCommand.swift`.
Depends: 4.

- [ ] 5.1 Implement LEDs (`PlayerIndicator`) and the rumble bit carried by every output builder (`RumbleBitCarry`); the rumble motor is binary. Verify: a test iterates every output report builder with rumble on and off and asserts bit 0; `ojd controller rumble` fixture test passes.
- [ ] 5.2 Implement IR setup with the 50 ms spacing (`IRSetupSpacing`) using an injected clock. Verify: a test asserts consecutive write timestamps differ by at least 50 ms for all seven steps and that a tuning value of 20 is refused (2.1).
- [ ] 5.3 Implement IR decode (basic, extended, full), touch contacts, pointer math (`IRPointerLost` rule: hold values, `PointerTracking` false). Verify: fixture tests for 0, 1, 2 and 4 points, centered pointer is 0, a roll-compensation case with a recorded accelerometer sample.
- [ ] 5.4 Implement the ADPCM encoder and the speaker script. Verify: an encoder test against a reference vector from WiiBrew's published step table; a packetization test that 20-byte packets carry the length field in the first byte's high bits; `SpeakerStream` test with an injected clock for pacing.
- [ ] 5.5 Implement `ojd controller speaker play|stop` with PCM WAV input, mix-down, resampling, `--volume`, `speakerMaxSeconds` and the errors `SpeakerUnavailable` and unsupported file. Verify: CLI tests for success, a non-WAV file, a record without the capability, and stop during playback.
- [ ] 5.6 Implement the session end on disconnect (neutral input, state dropped, startup again on reconnect). Verify: a test disconnects with IR on and asserts the setup script runs again before any IR point appears.

## 6. Layout reuse check

Depends: 3, 4.

- [ ] 6.1 List which parts of the description use `declarative-input-layouts` primitives and which parts stay Swift (split fields of the Classic, interleaved modes, calibration, Motion Plus). Verify: the list is in `docs/development/wire-protocols.md` "Coded Behavior" and a grep of the driver for each listed function finds it.
- [ ] 6.2 Confirm no byte value of the handshake, IR or speaker scripts is in Swift. Verify: `grep -n "0xA400\|0xA600\|0xB000\|0xA200" Sources/OpenJoystickDriverKit/Protocol/Drivers/Nintendo/WiiDriver*.swift` finds no literal, other than in a doc comment that names the description key.

## 7. Records and catalog

Owns: `Resources/Controllers/057e/057e-0306.json`, `057e-0330.json`, `Resources/ErrorCodes.json`, `Resources/Localization`.
Depends: 3, 4, 5.

- [x] 7.1 Author the two records (authored input only) with the product-string match key. Verify: `./Scripts/ojd catalog regenerate --write` then `./Scripts/ojd catalog regenerate --check` give no diff; `git status` shows the generated `Controllers` change only through the generator.
- [x] 7.2 Add a record-set test that `057E:0306` with product string `Nintendo RVL-WBC-01` and `057E:0330` with `Nintendo RVL-CNT-01-UC` match no mode. Verify: `swift test --filter ControllerModeMatchTests`.
- [ ] 7.3 Add the error codes (`ExtensionHandshakeFailed`, `SpeakerUnavailable`, unsupported audio file) and run `./Scripts/ojd errors regenerate --write`. Verify: `./Scripts/ojd errors regenerate --check` shows no diff and the error-code tests pass.
- [ ] 7.4 Add the localization keys for every user-facing text of the behavior table in design D9 in all 22 bundles, and review each translation against `LOCALIZATION.md` (Meaning, Punctuation). Verify: `python3 Scripts/Quality/check_localization_keys.py` and `swift test --filter LocalizationTests` pass, and the review is recorded in the task note.

## 8. Documentation

Depends: 7.

- [ ] 8.1 Update `docs/development/wire-protocols.md`: the `NintendoWii` row of the Protocol Coverage table (described, stays coded, suite `WiiDriverTests`) and the Coded Behavior entries from 6.1. Verify: `swift test --filter ProtocolParserCoverageTests` passes; `git diff --check` of the file passes.
- [ ] 8.2 Add the wiki page `wiki/Wii-Remote.md`: pairing through macOS Bluetooth, reconnecting, LEDs, extensions, IR pointer to mouse with a profile example, speaker commands, disconnecting, and the lack of a power-off command. Link it from `wiki/_Sidebar.md`, `Supported-Controllers.md` and `Connecting-Controllers.md`. Verify: `git diff --check` over the new and changed pages passes, and `python3 Scripts/Quality/check_localization_keys.py` still passes.
- [ ] 8.3 Add the Known Issues entries to `wiki/Known-Issues.md` for macOS pairing and for the personas that carry no pointer. Verify: `git diff --check` passes.
- [ ] 8.4 Add a `CHANGELOG.md` entry under Unreleased: the family, the two records, the pointer ids, the speaker command. Verify: `git diff --check` passes.
- [ ] 8.5 Review sources: the driver, description and tests are independent implementations from WiiBrew facts and captures, with no code or wording from wiiuse or wiimacmote. Verify: `grep -rniE "wiiuse|wiimacmote" Sources Resources Tests` finds no copied code, only fact references in doc comments, and `grep -rn "GPL" Sources/OpenJoystickDriverKit/Protocol/Drivers/Nintendo` finds nothing.
- [ ] 8.6 Review that no doc uses history words. Verify: `grep -rniE "renamed|legacy|previously|formerly" wiki/Wii-Remote.md` finds nothing.

## 9. Integration

Depends: 1 to 8.

- [ ] 9.1 Run the full check list once: `just check`; `./Scripts/ojd check driverkit`; `./Scripts/ojd test parsers-macos14`. Verify: each command exits 0; rerun only failures.
- [ ] 9.2 Run `openspec validate wii-remote --strict` from the repository root. Verify: it reports the change as valid.

## 10. Hardware Checks (Maintainer)

These checks may go to external testers through tester builds: each task names the files a tester returns (captures and the support report), and the maintainer replaces the fixtures and edits the description from them. Needs a Wii Remote (both revisions if available), a Nunchuk, a Classic Controller (and Pro), a Motion Plus (and a Wii Remote Plus), a sensor bar or two IR sources, and a Mac with Bluetooth. Capture with `ojd controller watch`, the support report and `ojd diagnose`, and attach the files named below.

- [ ] 10.1 Hardware Check 1, identity. Capture the HID VID:PID, Product string, manufacturer string and transport of each remote revision (`ioreg -r -c IOBluetoothHIDDriver` and `ojd controller list --json`). If a Balance Board or Wii U Pro is available, capture the same and confirm no Wii Remote mode matches. Verify: the product strings in the records equal the captures.
- [ ] 10.2 Hardware Check 2, pairing. For each macOS version available, record whether pairing works with 1+2 (discoverable) and with the red SYNC button, whether macOS asks for a PIN, and whether pressing a button reconnects after sleep. Verify: the wiki page states the tested versions and paths.
- [ ] 10.3 Hardware Check 3, core reports. Record raw hex for each report mode `0x30` to `0x3F` with every button pressed once, the remote at rest on each face (accelerometer), and a status report at full and low battery. Replace the WiiBrew-sourced fixtures. Verify: the fixture index test passes with hardware captures.
- [ ] 10.4 Hardware Check 4, extensions. For each extension, record the six-byte ID, the calibration data at `0xA40020`, rest and extreme samples, and the status and handshake sequence on plug and unplug, also during an IR setup. Record whether the Classic Controller Pro ID differs from the Classic Controller. Verify: fixtures of 1.2 are hardware captures and the unplug test passes against them.
- [ ] 10.5 Hardware Check 5, IR. Record raw IR bytes in each format with the sensor bar at 1 m and 3 m, which sensitivity level gives stable points, and whether 50 ms spacing is enough on each remote. Verify: the pointer fixture tests pass with the captures and the description's default level is the one that worked.
- [ ] 10.6 Hardware Check 6, speaker. Play a clip with `ojd controller speaker play`; record whether sound is clear, the rate and volume values that work, and the sequence the remote acknowledges. Verify: the setup bytes of the description equal the working capture.
- [ ] 10.7 Hardware Check 7, other devices. If a Wii U Pro Controller or Balance Board is available, capture its ID and report layout for the follow-up change; do not edit these records.
- [ ] 10.8 Hardware Check 8, sleep and idle. Record when the remote disconnects after idle, on Mac sleep and on low battery, what `ojd controller list` shows, and that reconnect restores IR and report mode (`Session end on disconnect`). Verify: the wiki states the idle behavior.
