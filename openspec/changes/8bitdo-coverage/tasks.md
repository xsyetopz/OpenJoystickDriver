# Tasks: 8BitDo Coverage

The user's decision (2026-10-25): every area is part of alpha.2, the work makes do with what is available and moves toward better. Where a capture is missing, the group writes the best record the sources support, marks it unverified, and a tester check returns the capture. Each group lists its tester card first, then the tests, the records and the documents; a task named "apply the tester result" stays open until the tester's files arrive.

## Working Agreements

- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/`. Change `Resources/Controllers/2dc8/` (an identity with no generated record) or `Resources/ControllerPatches/2dc8/` (a patch for a generated record), then run `./Scripts/ojd catalog regenerate --write`.
- No compatibility layer: a record that a capture disproves is corrected in the same change, with no alias.
- A record that Swift rejects gets a case in `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections/`.
- Docs state current behavior and its reason, with no history words. History goes in `CHANGELOG.md`.
- A task is done only after its Verify command ran in the session that closes it.
- Fixtures go in the folder that the nearest existing HID descriptor test uses and are named `VVVV-PPPP-mode-source.<kind>` (from sources) or `VVVV-PPPP-mode-capture.<kind>` (from a tester).
- Code from GPL, AGPL or unlicensed repositories is not ported; write it independently and record only its facts. A source under MIT, BSD, zlib, CC0 or Apache-2.0 that a task uses gets its notice in `THIRD_PARTY_NOTICES.md` in the same commit.
- After each group: `./Scripts/ojd catalog regenerate --check` and `swift test --filter` for the changed area. Once on the merged tree: `just check`.

## 1. Tester Cards and Bootloader Guard

Owns: `docs/testing/8bitdo-tester-checks.md` and the rule that `2DC8:3208` and `2DC8:5750` get no traffic.
Depends: none.
Verify: `swift test --filter BootloaderGuard`, `git diff --check`.

- [x] 1.1 Write `docs/testing/8bitdo-tester-checks.md` with one card per Hardware Checks entry below (T1 to T9). Each card names the tester build, the mode, the exact commands, the control order and the files to send back. Verify: `grep -c '^## T[0-9]' docs/testing/8bitdo-tester-checks.md` prints 9, and `git diff --check` over the file reports nothing.
- [x] 1.2 Write the bootloader test first: for each bootloader identity, drive startup, probe, keep-alive, rumble, light, configuration and the generic interface-signature binding against a fake transport, and assert that the transport records zero writes. Verify: `swift test --filter BootloaderGuard` fails before 1.3 and the failure names the path that sent.
- [x] 1.3 Read the binding, startup and probe code to list every path that writes to a device with no record, then place the refusal where one decision covers them (record data if the format can express it, otherwise one named check in the binding code). Verify: the list is in the commit message and `swift test --filter BootloaderGuard` passes.
- [x] 1.4 Add the controller-detail sentence (`ui.controllers.bootloaderIdentity`) with localization keys per `LOCALIZATION.md`; the log line is the existing `left unbound` line, which names the VID:PID and `reason=BootloaderIdentity`. A test covers the reason and the sentence. Verify: `swift test --filter BootloaderGuard`, `python3 Scripts/Quality/check_localization_keys.py`.
- [x] 1.5 Document the rule in `docs/testing/8bitdo-ultimate-2c.md` (section "Bootloader Identities") and `wiki/Supported-Controllers.md`. Verify: `grep -n "3208" wiki/Supported-Controllers.md docs/testing/8bitdo-ultimate-2c.md` finds the rule and `git diff --check` over both reports nothing.

## 2. Ultimate 2C Family: 301B, 301C, 301D, 3109

Owns: the `301B` stick mapping, the `301C` and `3109` starting records, the `301D` record, paddles on the 2C.
Depends: 1.
Verify: `swift test --filter EightBitDo`, `./Scripts/ojd catalog regenerate --check`, `./Scripts/ojd check schemas`.

- [x] 2.1 Write tests from sources: a descriptor-fixture test for `301B` (right stick on `Z` and `Rz`; a sweep moves both axes and leaves both triggers at rest), a test that `301C` maps no controls, a test that `3109` stays `XboxXUSB`/`Wired`, and a replay test for `301D` built from the usages the 2C Bluetooth record uses. Verify: `swift test --filter EightBitDo` fails on the current `301B` and `301C` records and the failing names are listed. The tests landed with or after the 2.2 to 2.4 records (`EightBitDoUltimate2CTests`), so no run shows them failing first.
- [x] 2.2 Correct `Resources/Controllers/2dc8/2dc8-301b.json` so that `Rx` and `Ry` (usages 51 and 52) map to nothing (D3, D5). Verify: `swift test --filter EightBitDo` passes the `301B` tests.
- [x] 2.3 Reduce `2dc8-301c.json` to an `idle` record (D4) and keep `3109` as it is, with the document saying both are unverified. Verify: `./Scripts/ojd catalog regenerate --write` then `--check` pass and the 2.1 tests pass.
- [x] 2.4 Add `Resources/Controllers/2dc8/2dc8-301d.json` from the sources, with no paddle mapping (the 2C rear buttons default to L3 and R3). Verify: `./Scripts/ojd diagnose record Resources/Controllers/2dc8/2dc8-301d.json --validate-only` exits 0 and the replay test passes.
- [x] 2.5 Update `docs/testing/8bitdo-ultimate-2c.md` (modes table with `301D`, the stick description, the unverified tier of `301B`, `301C`, `301D` and `3109`) and the 8BitDo rows of `wiki/Supported-Controllers.md` and `wiki/Connecting-Controllers.md`; add `CHANGELOG.md` entries under Unreleased. Verify: `grep -n "301D" docs/testing/8bitdo-ultimate-2c.md wiki/Supported-Controllers.md` finds the rows and `git diff --check` over the changed files reports nothing.
- [ ] 2.6 Apply the tester result of T1 to T4 (`301B` over Bluetooth LE, `301C`, `3109`, `301D`): replace each source-derived fixture with the captured one, correct any mapping the capture disproves, and move the rows to Community-Verified. Verify: `swift test --filter EightBitDo` passes with the `capture` fixtures and `grep -rn "source" Tests/.../8bitdo` lists no `301B` source fixture. Open until the tester's files arrive.

## 3. Ultimate 2 Family: 6012, 6013, 3107, 310B, Gyro

Owns: the Ultimate 2 records, the `310B` starting record, the gyro finding.
Depends: 1.
Verify: `swift test --filter EightBitDo`, `./Scripts/ojd catalog regenerate --check`.

- [x] 3.1 Write tests from sources: a replay per `6012` connection from one usage map (button usages 1 to 15 in the 2C order with no rear usage: no source gives the Ultimate 2 rear-button usages, so the four paddle mappings wait for T5, D5), a test that `6013` and `3107` map no controls, and a mode-selection test for `310B` (one name for both models). Verify: `swift test --filter EightBitDo` shows them failing before 3.2 and 3.3 (the `6012` map and the `6013`/`3107` tests landed with 3.2; the paddle test and the `310B` test landed after the records, so no run shows them failing first; the paddle mappings wait for T5).
- [x] 3.2 Add `2dc8-6012.json`, `2dc8-6013.json` and `2dc8-3107.json` to `Resources/Controllers/2dc8/`; `6013` and `3107` are `idle` records (D1, D4). Verify: `./Scripts/ojd catalog regenerate --write` then `--check` pass and `./Scripts/ojd diagnose record FILE --validate-only` exits 0 for each file.
- [x] 3.3 Keep one `310B` record for both models and name both in the `310B` row of `wiki/Supported-Controllers.md` (D4). A patch cannot name them: the record format has no name field and a patch only sets `modes`, `usb`, `bluetoothLE`, `route`, `output`, `input`, `tuning` and `server`. Verify: `swift test --filter EightBitDo` passes the `310B` test and `./Scripts/ojd catalog regenerate --check` passes.
- [x] 3.4 Write `docs/testing/8bitdo-ultimate-2.md` (identities, the starting usage map, paddle order, gyro status, the unverified tier) and update the wiki rows and `CHANGELOG.md`. Verify: `grep -n "6012" wiki/Supported-Controllers.md docs/testing/8bitdo-ultimate-2.md` finds the rows and `git diff --check` reports nothing.
- [ ] 3.5 Apply the tester result of T5 to T7 (`6012` cable and dongle, `6013` and `3107`, `310B` with an Ultimate 2 and a Pro 3): replace fixtures, apply D3 and D4 outcomes, record the gyro report offsets if a capture shows motion (D6). Verify: `swift test --filter EightBitDo` passes with the `capture` fixtures. Open until the tester's files arrive.

## 4. Ultimate 3-mode: 901B

Owns: the `901B` record.
Depends: 1.
Verify: `swift test --filter EightBitDo`, `./Scripts/ojd catalog regenerate --check`.

- [x] 4.1 Write the replay test from sources (a Bluetooth gamepad that follows the Xbox button order). Verify: `swift test --filter EightBitDo` passes with 4.2. The test landed in the same commit as the 4.2 record, so no run shows it failing first.
- [x] 4.2 Add `2dc8-901b.json` with the protocol the sources give (`HIDDescriptor`, Xbox mode over Bluetooth). Verify: the test passes and `./Scripts/ojd catalog regenerate --check` passes.
- [x] 4.3 Document the model and mode in `docs/testing/8bitdo-ultimate-2.md`, the wiki rows and `CHANGELOG.md`, as unverified. Verify: `grep -n "901B" wiki/Supported-Controllers.md` finds the row and `git diff --check` reports nothing.
- [ ] 4.4 Apply the tester result of T8 (`901B`). Verify: `swift test --filter EightBitDo` passes with the `capture` fixture. Open until the tester's files arrive.

## 5. Watchdog and Idle Dongle on macOS

Owns: the macOS measurement and, only if it shows a drop while served, one named keep-alive.
Depends: 2 and 3.
Verify: `swift test --filter EightBitDo`, `./Scripts/ojd catalog regenerate --check`.

- [x] 5.1 Write the document section that states the question and the three outcomes of D7, and the test for the outcome "no keep-alive" (the record has no `session.keepAlive`). Verify: `swift test --filter EightBitDo` passes and `git diff --check` reports nothing.
- [ ] 5.2 Apply the tester result of T9 (`310A` and `6012` served, then suspended). If the measurement shows a drop while served on a raw-USB pad, add `session.keepAlive` to the record with the measured interval and a packet test; for a HID pad, write the finding. Verify: `swift test --filter EightBitDo` passes and `./Scripts/ojd catalog regenerate --check` passes. Open until the tester's files arrive.
- [ ] 5.3 Document the result in `docs/testing/8bitdo-ultimate-2.md`; when a keep-alive is added, also in `docs/development/wire-protocols.md` and `CHANGELOG.md`. Verify: `git diff --check` over the changed files reports nothing.

## 6. Coverage of the Documents

Owns: completeness of the model and mode listings.
Depends: 2 to 5.
Verify: the loop below, `just check`.

- [x] 6.1 Confirm every 8BitDo PID with a bundled record appears in the wiki tables and every PID without a record appears as not covered. Verify: `for p in 2000 2002 200f 301b 301c 301d 3106 3107 3109 310a 310b 6001 6012 6013 901b; do grep -qi "2DC8:$p" wiki/Supported-Controllers.md || echo "missing $p"; done` prints nothing.
- [ ] 6.2 Run the repository checks on the merged tree. Verify: `just check` passes; rerun only the failed step.

## Hardware Checks (Testers)

The user has Discord testers who own the Ultimate 2C. These checks run through a tester build (`docs/testing/tester-builds.md`): the maintainer sends the DMG; the tester installs it, opens the app, approves the permissions, and runs the commands in Terminal. The tester sends back, for every check: `OpenJoystickDriver-TESTER-BUILD.txt`, `hid.txt`, `usb.txt`, `capture.jsonl` where the card asks, and a line that lists the controls pressed in order. A check for a pad no tester owns stays open; its record stays unverified.

Commands common to every card (`VVVV:PPPP` is the identity under test):

```shell
ioreg -r -c IOHIDDevice -l -w0 > hid.txt
ioreg -p IOUSB -l -w0 > usb.txt
ojd controller list
ojd controller show VVVV:PPPP
ojd controller capture VVVV:PPPP --duration 20 --json > capture.jsonl
```

- [ ] T1 `2DC8:301B`, Ultimate 2C over Bluetooth LE (also settles H5 of `platform-neutral-redesign`). Pair the pad, run the common commands, and during the capture sweep the right stick, press each trigger, then each button including L4 and R4. Send `hid.txt` (the `ReportDescriptor` is in it), `capture.jsonl`, and which of the right-stick directions moved.
- [ ] T2 `2DC8:301C`, receiver. Plug the receiver with the pad off; run `ioreg -p IOUSB -l -w0 > usb-0s.txt` at once, again as `usb-3s.txt`, `usb-8s.txt` and `usb-15s.txt` (timings proposed), then the common commands for whichever PID the receiver shows. Send all files and say whether the PID changed to `310A`.
- [ ] T3 `2DC8:3109`, adapter in standby and with the pad on. Run the common commands in each state. Send both sets. Send no configuration report; the commands only read.
- [ ] T4 `2DC8:301D`, Ultimate 2C wired in DInput (hold B while powering on). Run the common commands and press each control and each rear button in the card's order.
- [ ] T5 `2DC8:6012`, Ultimate 2 over the cable and again over the dongle. Run the common commands for each connection (name the files `cable-` and `dongle-`), press every control and each rear button, and say which button each rear button. In DInput and Switch mode, rotate the pad on each axis during a second capture.
- [ ] T6 `2DC8:6013` receiver and `2DC8:3107` dongle, with the pad off and on. Run the common commands for each.
- [ ] T7 `2DC8:310B` with an Ultimate 2 and, if the tester owns one, a Pro 3. Run `hid.txt` and `usb.txt` for each and send them; the strings and `bcdDevice` decide the mode.
- [ ] T8 `2DC8:901B`, Ultimate 3-mode over Bluetooth in Xbox mode. Run the common commands and press each control.
- [ ] T9 Watchdog, with `310A` and `6012` served: run `ioreg -p IOUSB -w0 | grep -i 2dc8` at the start and after 5 minutes (proposed) with no input; run `ojd controller suspend CONTROLLER`, repeat after 10 and 60 seconds, then `ojd controller resume CONTROLLER` and say whether the pad returned. Send the output of each run with the time.

## Workflow Follow-Up

- Archive this change after `platform-neutral-redesign` is archived; the records need its format.
- Push, tag, notarize and publish are the maintainer's actions and need confirmation.
