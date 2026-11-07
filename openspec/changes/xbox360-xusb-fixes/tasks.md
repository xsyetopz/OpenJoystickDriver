# Tasks: Xbox 360 USB fixes

Order: tests with recorded fixtures first, then data, then driver, then pipeline, then docs.

## Working agreements

- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`. Change authored inputs (`Resources/ControllerPatches/`, protocol descriptions), then run `./Scripts/ojd catalog regenerate --write`.
- `Resources/Protocols/` is authored. `./Scripts/ojd catalog regenerate --write` writes the copy under `Sources/OpenJoystickDriverKit/Resources/Protocols/` (`Scripts/Catalog/generate_controller_catalog.py:33`), and `--check` fails when the two differ (`ProtocolCopyTests` in `Tests/RepositoryScripts/test_catalog_generation.py`). Never edit the Kit copy.
- A fixture comes from a capture of a real device or from a byte table of the upstream source named in the task, never from the code under test. Where no capture exists yet, the fixture file lists its source and the test is marked pending on the hardware check named in the task.
- No history words in comments or docs; no compatibility paths; a removed datum fails like any invalid input.
- Hardware checks are run by the maintainer or by testers through tester builds. Each check records its result in the PR text, not in code comments.

## 1. Fixtures and loader groundwork

Owns: `Tests/ProtocolPacketFixtures`, the description loader.
Depends: none.
Verify: `swift test --filter ProtocolDescription`.

- [ ] 1.1 After each edit of `Resources/Protocols/xbox-xusb.json`, run `./Scripts/ojd catalog regenerate --write`. Verify: `./Scripts/ojd catalog regenerate --check` passes.
- [x] 1.2 Add fixtures to `Tests/ProtocolPacketFixtures` for the receiver: presence connected and disconnected envelopes, a pad report with no earlier presence report, a pad report with a short length, and a headset-bit presence report. Verify: `swift test --filter XUSBDriverTests` still passes with the fixtures unused.
- [x] 1.3 Add the byte table of the three control reads (D4 of `design.md`) as a fixture with its source (`paroj/xpad` `3470f9f`). Verify: a test compares the table with the record datum of task 4.2 once that exists (pending until then).
- [x] 1.4 Extend the protocol-description schema and loader with `defaults.receiverPowerOff` (one raw-USB packet with `bytes`, `endpoint`, `timeoutMilliseconds`, `variants`), separate from `session.shutdown`, add a case to `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections/protocol-description.json` for an unknown key, and a family other than `XboxXUSB` that sets it is rejected. Add a pipeline test: an input I/O error on a receiver slot with the datum present calls `invalidateUSBHandle` and writes no power-off packet. Verify: `./Scripts/ojd check schemas` and `swift test --filter ProtocolDescription`.

## 2. Presence (tests first)

Owns: `XUSBDriver.swift`, `xbox-xusb.json`.
Depends: 1.
Verify: `swift test --filter XUSBDriverTests`.

- [x] 2.1 Replace the tests `testWirelessReceiverPadDataBeforePresenceYieldsNothingAndAsksAgain` and `testWirelessReceiverPresenceInquiryResendIsBounded` (`XUSBDriverTests+Receiver.swift:28-53`) with tests that a valid pad report before any presence report connects the slot, reports `.connected` once, decodes the report, and queues no write; that a short or wrong-type report does not connect; that a later disconnect report resets state. Verify: the tests fail on the current driver.
- [x] 2.2 Implement D1: connect on a decodable pad report; delete `padReportsWithoutPresence`, `resendPresenceInquiry`, `inquiryResendInterval`, the `receiverInquiryResendLimit` datum and the XUSB entry of `presenceResendReports` in `rawUSBTuningKeys`. Find every reference first: `grep -rn "receiverInquiryResendLimit\|inquiryResendInterval\|presenceResendReports"` (GIP keeps its own use of `presenceResendReports`). Verify: the 2.1 tests pass; `./Scripts/ojd check schemas`; `swift test --filter ProtocolDescription`; the grep shows no XUSB reader left.
- [x] 2.3 Rewrite the type comment at `XUSBDriver.swift:57-60` to state the current behavior and its reason, without history words. Verify: `grep -n "can be lost" Sources/OpenJoystickDriverKit/Protocol/Drivers/Xbox/XUSBDriver.swift` prints nothing.
- [ ] 2.4 Only if H2 fails: add `presenceInquiryIntervalMilliseconds` (D1 fallback) with a keep-alive resend for a slot that is not connected, bounded by the datum, with a test using a fake clock. Verify: the test shows no resend while connected and a resend per interval while not.

## 3. Power-off (tests first)

Owns: `XUSBDriver.swift`, `PhysicalProtocolDriver.swift` (the hook), `DevicePipeline+Lifecycle.swift`, `xbox-xusb.json`.
Depends: 1.4; the datum ships only after H4 and H5.
Verify: `swift test --filter XUSBDriverTests` and `swift test --filter USBPipelineRecoveryTests`.

- [x] 3.1 Write tests: a connected receiver slot returns the 12-byte packet from `powerOffWrites()`; a slot that is not connected returns none; a wired pad returns none; the pipeline stop sends it once before the handle closes; `invalidateUSBHandle` after an I/O error does not send it. Verify: the tests fail before 3.2.
- [x] 3.2 Add the `powerOffWrites()` hook with an empty default, implement it for the receiver from the description's `defaults.receiverPowerOff` datum, and call it from the stop path only. Verify: the 3.1 tests pass.
- [ ] 3.3 Write the Guide-hold test (`GuideHoldPowerOff`, D3): Guide down for 5 s of fake time queues the packet once; release before 5 s does not; `guideHoldPowerOffSeconds` 0 disables it. Implement it in the form H5 selects (next-packet check or timer). Verify: the test passes; if H5 has not run, the task stays open.
- [x] 3.4 Read `SystemPowerNotificationObserver` and `ApplicationServiceRuntime` to see whether the sleep acknowledgement waits for `systemWillSleep` to return. Verify: a test in `SystemPowerNotificationObserverTests` shows the acknowledgement follows the teardown, or the task adds that wait and the test.
- [ ] 3.5 Add the `defaults.receiverPowerOff` datum to `xbox-xusb.json` and decide default per D2 after H4/H5. If it ships on, add the user-facing text (Controllers detail and `wiki/`), reviewed against `LOCALIZATION.md`. Verify: `./Scripts/ojd check schemas`, `python3 Scripts/Quality/check_localization_keys.py`, `swift test --filter XUSBDriverTests`.

## 4. Wired clone start sequence (tests first)

Owns: `Resources/ControllerPatches/045e/`, record tests.
Depends: 1.3; the patch ships after H8.
Verify: `./Scripts/ojd catalog regenerate --check` and `swift test --filter ControllerRecord`.

- [x] 4.1 Write tests: a device with manufacturer `SHANWAN` and `045e:028e` receives the three control reads in order before the first startup write; a device with manufacturer `Microsoft`, no manufacturer string, or `Logitech` receives none. Verify: the tests fail before 4.2.
- [x] 4.2 Add the controller patch for `045e:028e` with `session.control` entries from the 1.3 table, `match.manufacturer: "SHANWAN"`, `timeoutMilliseconds: 100`, `toleratesRejection: true`. Run `./Scripts/ojd catalog regenerate --write`. Verify: `./Scripts/ojd catalog regenerate --check` prints no diff; the 4.1 tests pass; `./Scripts/ojd check profiles`.
- [x] 4.3 Add a rejection case for a control entry with a `match` that has no keys (already refused by the loader) only if none exists under `SchemaRejections/`. Verify: `swift test --filter SchemaRejection`.
- [x] 4.4 Write every line of the driver and record work from the facts in `design.md`, not from `xpad` source text. If a line is taken from `zeromiyi/x360w` (MIT), add its notice to `THIRD_PARTY_NOTICES.md`. Verify: `git diff` contains no text copied from `xpad.c` (compare the added Swift and JSON against the fetched sources by eye and with `grep -n "kzalloc\|usb_control_msg"` on the diff, which prints nothing); `grep -n "x360w" THIRD_PARTY_NOTICES.md` shows the entry when x360w code is used; `git diff --check` passes on the file.

## 5. Ownership, slot mapping, docs

Owns: tests, comments, `docs/development/wire-protocols.md`.
Depends: 2.
Verify: `swift test --filter ReceiverRoleProfileTests`.

- [x] 5.1 Add a test that a receiver held by another client reports `ownedByAnotherClient` with the holder name, performs no write, and opens when the release arrives, without a timed retry. Verify: `swift test --filter USBPipelineRecoveryTests` passes and the test names the state.
- [x] 5.2 Add `ReceiverRoleProfileTests` cases for descriptor orders `0,2,4,6`, `0,1,2,3,4,5,6,7` with audio interfaces of another triple, and a descending list; the slot ordinal follows ascending interface number. Verify: `swift test --filter ReceiverRoleProfileTests`.
- [x] 5.3 Correct the doc comment at `ProtocolDriverRegistry+InterfaceContract.swift:4` (the manager, not `XUSBDriver`, assigns the ring LED). Verify: `grep -n "lights players" Sources/OpenJoystickDriverKit/Protocol/Catalog/ProtocolDriverRegistry+InterfaceContract.swift` prints nothing.
- [ ] 5.4 Update the `XboxXUSB` row of `docs/development/wire-protocols.md` (startup, shutdown, rumble templates; presence rule; clone control reads) and the Coded Behavior list. Verify: `git diff --check` on the file; `git diff` shows no history words.
- [ ] 5.5 Run the repository check list from the repository `CLAUDE.md` once on the final tree. Verify: `just check`.

## Hardware Checks (Maintainer)

Run with receivers `0291`, `0719`, `02a9`, two or more pads, a SHANWAN-class clone, a genuine wired pad, Steam. Testers run them through tester builds. Record the result of each in the PR text.

- [ ] H1 Presence order: start OJD with a pad already paired and idle, then press a button. Record whether the slot connects at the first report and whether any input is lost. Repeat with the pad removed (hold Guide until off) and powered on again.
- [ ] H2 Idle connected pad at startup: start OJD with a paired pad that stays untouched for 30 s. Record whether the slot connects without input. If not, task 2.4 is required.
- [ ] H3 Clone receiver `02a9` and original `0291`/`0719`: do they accept the inquiry, the LED packet, rumble and the power-off packet?
- [ ] H4 Power-off packet: send `00 00 08 C0` to a connected pad (CLI or test build). Record whether the pad turns off, and whether it reconnects with the Guide button.
- [ ] H5 Guide hold: hold Guide for 6 s with the packet disabled; record whether the pad sends reports while the button is held (decides timer or next-packet check in 3.3). Then decide D2 default after H4 and H5.
- [ ] H6 Slot mapping: dump the interface numbers of each receiver (`ojd` diagnose output). Connect pads in a known order and record which pad lands on which slot and whether its LED quadrant matches.
- [ ] H7 Sleep/wake: with a connected pad, sleep the Mac for 1 minute and wake it. Record the pad state during sleep (on or off), whether the slot reconnects without replug, and any kernel log lines. Repeat with the power-off datum on.
- [ ] H8 Wired clones: for each clone, record `lsusb`-equivalent strings (manufacturer exact bytes, product, `bcdDevice`) and whether it sends input before the control reads, after them, and after a genuine pad receives them (it must not be sent). Also test a Logitech F710-class pad if available.
- [ ] H9 Steam: with Steam holding the receiver, start OJD. Record the state shown in the CLI and GUI, and that OJD opens the receiver after Steam quits.
