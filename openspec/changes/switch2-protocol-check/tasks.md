# Tasks: Switch 2 protocol check

Order: capture tooling, hardware captures, fixtures and tests from the captures, then code. No decoder or description change lands before its capture exists.

## Working agreements

- A fixture comes from a hardware capture. A test written before its capture is marked pending on the hardware check named in the task and does not pass by assumption.
- `Resources/Protocols/` is authored. `./Scripts/ojd catalog regenerate --write` writes the copy under `Sources/OpenJoystickDriverKit/Resources/Protocols/` (`Scripts/Catalog/generate_controller_catalog.py:33`), and `--check` fails when the two differ (`ProtocolCopyTests` in `Tests/RepositoryScripts/test_catalog_generation.py`). Never edit the Kit copy.
- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/`; change `Resources/ControllerPatches/057e/`, then run `./Scripts/ojd catalog regenerate --write`.
- GPL sources give facts only; SDL (zlib) and `procon2-mac` (MIT) code may be used with its notice in `THIRD_PARTY_NOTICES.md`.
- No history words in comments or docs; no compatibility paths.
- Captures are made by the maintainer or by testers through tester builds; each capture file names controller, firmware if known, transport and the action.

## 1. Capture tooling

Owns: packet capture, fixture folder.
Depends: none.
Verify: `swift test --filter PacketCapture` and a capture of a Switch 1 controller that shows every report ID.

- [x] 1.1 Read `ControllerPacketCapture.swift` and the USB and HID receive paths and check that a capture keeps reports whose ID the driver ignores (a `0x09` report on a Switch 2 interface). If it drops them, add the report to the capture before the driver filter, with a test. Verify: a test feeds a report with an ignored ID and finds it in the capture.
- [ ] 1.2 After each edit of `Resources/Protocols/nintendo-switch2.json`, run `./Scripts/ojd catalog regenerate --write`. Verify: `./Scripts/ojd catalog regenerate --check` passes.
- [x] 1.3 Add a fixture folder `Tests/ProtocolPacketFixtures` section `Switch2` with a loader for capture text files (controller, transport, action, reports as hex). Verify: `swift test --filter Switch2DriverTests` passes with a sample file that holds a report built from the SDL offsets of `HandleSwitchProState`, marked as synthetic in its header.

## 2. Captures and reconciliation (hardware, before code)

Owns: capture files, `design.md` table.
Depends: 1.
Verify: each capture file exists in the PR and the matching check below is ticked.

- [ ] 2.1 USB capture of the Pro Controller 2 (`2069`): idle 5 s, each button alone, each stick to every edge, both triggers, then a slow move of the controller for the IMU. Verify: the file holds report IDs `0x05` and/or `0x09` with counts per ID in its header.
- [ ] 2.2 Bluetooth LE capture of the same actions. Verify: the file lists the notification bytes before the hub prepends `0x05`.
- [ ] 2.3 Captures of the GameCube controller (`2073`) and of the left (`2067`) and right (`2066`) Joy-Con, USB and Bluetooth LE. Verify: one file per controller and transport.
- [ ] 2.4 Fill the outcome table of `design.md` D2 from the captures and record which row applies per controller. Verify: a script-free comparison list (button, byte, bit on USB, on Bluetooth LE, in OJD's table) is in the PR text with no unexplained difference.
- [ ] 2.5 Dump the HID report descriptor of `2069` over USB and record whether it declares report ID `0x09`, its size and its usages. Verify: the descriptor bytes are in the PR text and the README's "21 buttons, 12-bit axes, D-pad as buttons" is confirmed or contradicted.

## 3. Report identification and Bluetooth LE layout (tests first)

Owns: `Switch2Driver.swift`, `nintendo-switch2.json`.
Depends: 2.4.
Verify: `swift test --filter Switch2DriverTests`.

- [ ] 3.1 Write tests from the 2.1 to 2.3 captures: every button and both sticks per controller and transport decode to the controls the capture action names; the other report ID (if present) changes no state. Verify: the tests fail wherever the current driver disagrees with a capture, or pass if it agrees; the PR text says which.
- [ ] 3.2 Apply the D2 row: keep `0x05`, ignore `0x09` explicitly, or add a `0x09` table to the description (data) with the decoder reading it. Verify: the 3.1 tests pass; `./Scripts/ojd check schemas`; `swift test --filter ProtocolDescription`.
- [ ] 3.3 If a Bluetooth LE bit differs from the USB table, add a per-transport button table to the description and select it by link. Verify: the 3.1 Bluetooth LE tests pass; `swift test --filter Switch2DriverTests`.
- [ ] 3.4 Update the type comment of `Switch2Driver` (`Switch2Driver.swift:86-96`) and the `NintendoSwitch2` rows of `docs/development/wire-protocols.md` to state the settled report IDs, tables and sources. Verify: `git diff --check` on the doc; `git diff` has no history words.

## 4. IMU (tests first)

Owns: `Switch2Driver.swift`, `nintendo-switch2.json`.
Depends: 3.
Verify: `swift test --filter Switch2DriverTests`.

- [x] 4.1 Read the pinned SDL `SDL_hidapi_switch2.c` for the sensor-bias flash addresses and read lengths, and the gyro coefficient rule; list them in `design.md` "Source checks". Verify: each value in the list quotes its source line.
- [ ] 4.2 Write tests from the 2.1 slow-move capture: a still controller gives accelerometer near 1 g on one axis and gyro near zero after bias; a zero sensor timestamp yields no sample; the sample time follows the timestamp. Verify: the tests fail before 4.3.
- [ ] 4.3 Add the bias reads to the startup sequence (data when fixed bytes, code for the reply parse), decode accelerometer and gyroscope into the motion path used by the Triton driver, and set the capability so the controller advertises motion. Verify: the 4.2 tests pass; `swift test --filter ControllerCapabilitiesTests`; `swift test --filter Switch2DriverTests`.
- [ ] 4.4 Check Joy-Con orientation: compare the left and right Joy-Con motion axes with the capture and set the per-layout signs from the capture. Verify: tests per layout pass.
- [ ] 4.5 Remove the "The IMU is not decoded" sentence from `Switch2Driver.swift:92` and the doc rows that say so. Verify: `grep -n "IMU is not decoded" -r Sources docs wiki` prints nothing.

## 5. Rumble cadence

Owns: `nintendo-switch2.json`, `Switch2DriverTests.swift`.
Depends: H5.
Verify: `swift test --filter Switch2DriverTests`.

- [ ] 5.1 Record the H5 result (feel and traffic at 4, 8 and 12 ms) in the PR text. Verify: the PR text has one line per interval.
- [ ] 5.2 If H5 favors another interval, change `keepAlive.intervalMilliseconds` and the pinned test (`Switch2DriverTests.swift:206`) together; otherwise leave both and say so in the PR text. Verify: `swift test --filter Switch2DriverTests`.

## 6. Records

Owns: `Resources/ControllerPatches/057e/`.
Depends: 2.
Verify: `./Scripts/ojd catalog regenerate --check`.

- [x] 6.1 Write a test that each record binds `NintendoSwitch2` with the layout of the table in `design.md` (`2066` JoyConRight, `2067` JoyConLeft, `2069` the family default Pro, `2073` GameCube). Verify: `swift test --filter Switch2DriverTests`.
- [ ] 6.2 Compare each record's patch (`057e-2066`, `2067`, `2069` patch files) with the captures (interface numbers, endpoints, Bluetooth LE vibration characteristic) and fix differences in the patch, then run `./Scripts/ojd catalog regenerate --write`. Verify: `./Scripts/ojd catalog regenerate --check` prints no diff.
- [ ] 6.3 If a Joy-Con pair device (`057E:2068`) appears in any capture, add a record from that capture; otherwise record in the PR text that no capture exists. Verify: the PR text states which.
- [ ] 6.4 If SDL or `procon2-mac` code is used, add its notice to `THIRD_PARTY_NOTICES.md`. Verify: `grep -n "SDL\|procon2" THIRD_PARTY_NOTICES.md` shows the entry, or the PR text states that only facts were used.
- [ ] 6.5 Run the repository check list from the repository `CLAUDE.md` once on the final tree. Verify: `just check`.

## Hardware Checks (Maintainer)

Run with `2069`, `2073`, `2066` and `2067` over USB-C and Bluetooth LE. Testers run them through tester builds. Record each result in the PR text.

- [ ] H1 Report IDs: capture USB reports of `2069` and count reports per ID (`0x05`, `0x09`, others) over 30 s, idle and moving.
- [ ] H2 Descriptor: dump the HID report descriptor of each USB controller and compare with the README's claim.
- [ ] H3 Bluetooth LE bits: press every button on `2069` over Bluetooth LE and note byte and bit; same for `2067` and `2066`.
- [ ] H4 IMU: lay each controller flat and still for 5 s, then rotate it about each axis; capture the sensor timestamp, accelerometer and gyroscope words.
- [ ] H5 Rumble cadence: with a fixed test pattern, feel and log traffic at 4, 8 and 12 ms on USB and Bluetooth LE; note dropped or doubled pulses.
- [ ] H6 Identity: for each PID, record the product string, interface list and whether macOS shows a second HID device for the same controller.
- [ ] H7 Firmware: record the firmware version of each controller used (console settings or the tool of the tester's choice).
