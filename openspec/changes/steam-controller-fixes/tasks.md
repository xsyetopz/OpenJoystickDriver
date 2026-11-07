# Tasks: Steam Controller fixes

Order: tests with recorded fixtures first, then vocabulary, then data, then driver, then output, then docs.

## Working agreements

- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`. Change authored inputs, then run `./Scripts/ojd catalog regenerate --write`.
- `wii-remote` and `steam-controller-fixes` both add control ids (`PointerX`, `PointerY`, `PointerTracking`; `LeftGripTouch`, `RightGripTouch`) to the same vocabulary files. The ids differ; the change that lands second rebases on the first and runs `./Scripts/ojd vocabulary regenerate --write` again.
- `Resources/Protocols/` is authored. `./Scripts/ojd catalog regenerate --write` writes the copy under `Sources/OpenJoystickDriverKit/Resources/Protocols/` (`Scripts/Catalog/generate_controller_catalog.py:33`), and `--check` fails when the two differ (`ProtocolCopyTests` in `Tests/RepositoryScripts/test_catalog_generation.py`). Never edit the Kit copy.
- A fixture comes from a hardware capture or from the byte table of SDL `release-3.4.16` named in the task, never from the code under test. A fixture without a capture names its source and marks the dependent test pending on the hardware check.
- Linux `hid-steam.c` gives facts only; write code independently. If SDL code is used, add its zlib notice to `THIRD_PARTY_NOTICES.md`.
- No history words in comments or docs; no compatibility paths.
- Hardware checks are run by the maintainer or by testers through tester builds; record each result in the PR text.

## 1. Fixtures

Owns: `Tests/ProtocolPacketFixtures`.
Depends: none.
Verify: `swift test --filter SteamTritonDriverTests`.

- [ ] 1.1 After each edit of `Resources/Protocols/valve-steam-*.json`, run `./Scripts/ojd catalog regenerate --write`. Verify: `./Scripts/ojd catalog regenerate --check` passes.
- [x] 1.2 Add Triton state-report fixtures for report `0x42`: grip bit 28 only, bit 29 only, both, and neither, with the other button bits at zero and with all lower bits set. Source: SDL `TritonButtons`. Verify: the existing Triton tests still pass with the fixtures unused.
- [x] 1.3 Add the SDL rumble report bytes (id `80`, type 0, intensity 0, speeds, gains 0) as a fixture, and the 8-byte pulse report layout (`81`, side, on, off, repeat). Verify: `swift test --filter SteamTritonDriverTests`.

## 2. Grip touch and vocabulary (tests first)

Owns: `Control` type, vocabulary files, mappings, names, localization.
Depends: 1.2.
Verify: `./Scripts/ojd vocabulary regenerate --check`, `./Scripts/ojd check schemas`, `swift test --filter ControlVocabularyTests`.

- [ ] 2.1 Run `grep -rn "RightTrackpadTouch\|rightTrackpadTouch" Sources Resources Scripts Tests wiki docs` and list every hit in the PR text. Verify: the list is complete; each hit is changed or marked "no entry needed" with a reason.
- [ ] 2.2 Write tests: the Triton driver decodes grip bits into `RightGripTouch` (bit 28) and `LeftGripTouch` (bit 29) press and release events and leaves other controls unchanged; `ControlVocabularyTests` and `test_control_vocabulary.py` list both ids; the crosswalk entries exist. Verify: the tests fail before 2.3.
- [ ] 2.3 Add `LeftGripTouch` and `RightGripTouch` to the `Control` type, `vocabulary.schema.json`, `crosswalk.json` (null mappings), the capability and mapping tables, and the Triton description's `controls.add`; add the names to the presentation table and all 22 localization bundles. Run `./Scripts/ojd vocabulary regenerate --write` and `./Scripts/ojd catalog regenerate --write`. Verify: `./Scripts/ojd vocabulary regenerate --check`, `./Scripts/ojd catalog regenerate --check`, `python3 Scripts/Quality/check_localization_keys.py`, and the 2.2 tests pass.
- [ ] 2.4 Review each translation added in 2.3 against `LOCALIZATION.md` (Meaning, Punctuation). Verify: the review notes are in the PR text; `swift test --filter LocalizationTests` passes.
- [ ] 2.5 Add the table entries to `Buttons` of `SteamTritonDriver+Reports.swift` (`0x1000_0000` right grip, `0x2000_0000` left grip) and update the equivalence snapshots with the helper of the redesign change. Verify: the snapshot helper prints only the grip additions.

## 3. 2015 activation (tests first)

Owns: `valve-steam-controller.json`, `SteamControllerDriver+Session.swift`.
Depends: 1.1; the datum ships after H5.
Verify: `swift test --filter SteamSessionWritesTests` and `swift test --filter SteamControllerBluetoothTests`.

- [x] 3.1 Read `controller_constants.h` at the pinned SDL commit and confirm the indexes `SMOOTH_ABSOLUTE_MOUSE` (24 expected), `LEFT_TRACKPAD_MODE` (7), `RIGHT_TRACKPAD_MODE` (8), `IMU_MODE` (48) and `TRACKPAD_NONE` (7). Verify: design.md "Source checks" quotes the enumerator counts.
- [ ] 3.2 Write tests of the USB and Bluetooth LE activation sequences: `81`, then `8E 00`, then one settings write with settings 7 = 7, 8 = 7, 24 = 0, 48 = `0x18` (and the Bluetooth LE framing of the existing sequence). Verify: the tests fail before the datum changes.
- [ ] 3.3 Compare the deactivation with SDL `CloseSteamController` (`85`, `8E 00`, setting 8 = `TRACKPAD_ABSOLUTE_MOUSE`). Verify: a test pins whichever sequence H5 shows restores lizard mouse; if H5 shows `85` and `8E` suffice, the PR text says so.
- [ ] 3.4 Edit the description with the sequences from 3.2, within the 20-byte Bluetooth LE report and the 64-byte USB report. Verify: the 3.2 tests pass; `./Scripts/ojd check schemas`; `swift test --filter ProtocolDescription`.

## 4. Triton lizard handling (gated)

Owns: `valve-steam-triton.json`, `SteamTritonDriver.swift`.
Depends: H6.
Verify: `swift test --filter SteamTritonDriverTests`.

- [x] 4.1 Read the numeric IDs of the `IBEX`, `IBEX_BLE`, `PROTEUS` and `NEREID` devices in `hid-steam.c` and compare them with records `28de-1302` to `1305`. Verify: design.md "Source checks" lists the mapping; a mismatch ends this group.
- [ ] 4.2 If H6 shows a benefit, write tests of the extended activation (`CLEAR_DIGITAL_MAPPINGS`, settings 9 = 0 and 71 = 0) and of a deactivation that adds default mappings and `LOAD_DEFAULT_SETTINGS`; then edit the description. Verify: the tests pass; the crash check of H6 passes. If H6 shows no benefit, close the task with the result in the PR text.

## 5. Pad haptic pulse and rumble (tests first)

Owns: `SteamTritonDriver.swift`, output command and capability types, CLI output commands.
Depends: 1.3; the side encoding after H3.
Verify: `swift test --filter SteamTritonDriverTests`, `swift test --filter PhysicalRumbleOutputTests`.

- [ ] 5.1 Write tests of the pulse report encoding from the H3 capture: side values, little-endian times and count, 8-byte length, HID output report id `0x81`. Verify: the tests fail before 5.2; they stay pending until H3 supplies the capture.
- [ ] 5.2 Add `setPadHapticPulse` and the `padHaptic(side)` capability to the output types, encode it in the Triton driver, reject it on other families with `unsupportedCapability`, and add a CLI diagnostic under the controller output commands (with user-facing text reviewed against `LOCALIZATION.md`). Verify: the 5.1 tests pass; `swift test --filter OpenJoystickDriverCLITests`; `python3 Scripts/Quality/check_localization_keys.py`.
- [x] 5.3 Add a test that pins the rumble report: id `80`, bytes 1 to 3 zero, left speed at 4 to 5, left gain 6 zero, right speed at 7 to 8, right gain 9 zero, length 10. Verify: `swift test --filter SteamTritonDriverTests`.

## 6. Dongle interfaces and docs

Owns: tests, `docs/development/wire-protocols.md`.
Depends: 2, 3.
Verify: `swift test --filter SteamHIDRoleTests`.

- [x] 6.1 Extend `tritonDongleSlotsAreInterfacesTwoToFiveAndBluetoothIsItsLocation` (`SteamHIDRoleTests.swift:192-205`) to run for `0x1305` as well. Verify: the test passes for both IDs.
- [ ] 6.2 Update the `ValveSteamController` and `ValveSteamTriton` rows and the Coded Behavior list of `docs/development/wire-protocols.md` (grip touch, pulse report, activation sequence). Verify: `git diff --check` on the file; `git diff` has no history words.
- [ ] 6.3 If SDL code was used, add its zlib notice to `THIRD_PARTY_NOTICES.md`. Verify: `grep -n "SDL" THIRD_PARTY_NOTICES.md` shows the entry, or the PR text states that only facts were used.
- [ ] 6.4 Run the repository check list from the repository `CLAUDE.md` once on the final tree. Verify: `just check`.

## Hardware Checks (Maintainer)

Run with a 2026 Steam Controller (USB, Bluetooth LE, dongle) and a 2015 Steam Controller (USB, dongle, Bluetooth LE). Testers run them through tester builds. Record each result in the PR text.

- [ ] H1 Grip touch: touch each grip and log the button word (CLI report dump). Confirm bit 28 for the right grip and bit 29 for the left.
- [ ] H2 Bluetooth LE `1303` (2026) and `1106` (2015): does macOS expose feature report 1 (2026) and the `C0` framed reports (2015) through the HID path? Record any failing write.
- [ ] H3 Pad haptic pulse: send `81` with each side value, a 1000 us on, 1000 us off and 100 repeats, to each pad. Record which pad buzzes for which side value, the feel for different times, and whether the report is accepted over Bluetooth LE and the dongle.
- [ ] H4 Rumble fields: compare rumble with left gain 0 (SDL) and 2 (Linux), type 0, intensity 0 and non-zero values. Record any audible or felt difference.
- [ ] H5 2015 activation: with `8E 00` and `SMOOTH_ABSOLUTE_MOUSE = 0` added, on USB, dongle `1142` and Bluetooth LE, record that the pad enters gamepad mode, that no mouse or key emulation remains, that IMU still reports, and that deactivation returns lizard mode to the OS (mouse, Esc, Enter).
- [ ] H6 Triton lizard: with `CLEAR_DIGITAL_MAPPINGS` and watchdog off, record whether lizard mode stays off with no 3 s resend. Then kill OJD with `kill -9` and record whether the pad recovers lizard mode; replug and note the result.
- [ ] H7 Dongle interfaces: dump the HID interface numbers of dongles `1304` and `1305` with pads connected on each slot, and confirm slots 2 to 5.
- [ ] H8 Watchdog timeout: measure how long after the last resend the firmware restores lizard mode (SDL resends every 3 s; another project uses 800 ms).
