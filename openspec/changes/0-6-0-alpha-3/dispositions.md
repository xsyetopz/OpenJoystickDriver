# Dispositions of open issues and pull requests (task 8.15)

State as listed by `gh issue list --state open` (21 issues) and `gh pr list --state open` (7 pull requests) on 2026-11-11; #64 was added after. Task numbers come from `tasks.md`. Every row starts with `| #`; the done-check is `grep -c '^| #' dispositions.md`, which must print 29.

"Waiting on reporter" means the maintainer asked the reporter to try 0.6.0-alpha.2 and report back (comment of 2026-11-07), and no answer has come.

## Issues

| Item | Device or topic | Task | State | Maintainer's remaining action |
| --- | --- | --- | --- | --- |
| #8 | Steam Controller 28DE:1102 (reporter julesbravo) | 8.14 | Bundled record `28de-1102.json` exists; an earlier test gave 0 reports. Waiting on reporter. | Post the 8.14 capture request below. |
| #9 | Xbox 360 wireless (reporter jonasw8) | 8.7 | Waiting on reporter. | Do 8.7; ask for a retest on the current build. |
| #11 | Logitech F310 in XInput mode, wrong button mapping (reporter qwertychouskie) | 8.14 | No VID:PID in the report. Bundled `046d-c21d.json` is the F310 XInput ID. | Post the 8.14 request; ask the reporter to confirm the ID from `ojd controller list`. |
| #14 | Razer Wolverine V3 TE 1532:0A43 (reporter cbandras) | 8.10 | Waiting on reporter. | Do 8.10 (PR #39 is linked there). |
| #18 | Xbox One pad 045E:02D1 (reporter cooltune) | 4.8, 9.17 | Covered by 9.17. | Do 9.17; close with the fix. |
| #19 | Razer Wolverine V2 1532:0A29 (reporter zunium) | 8.14, 17.1 | Covered by 17.1. Bundled record `1532-0a29.json` exists. A commenter sees "Input active" with all controls at zero and "USB device unavailable; retrying". | Do 17.1; post the 8.14 request. |
| #21 | Nacon Revolution X Pro 3285:0634 (reporter TanelLaas) | 8.14 | Bundled record `3285-0634.json` exists. USB drops after the handshake; the reporter suspects the 4 s keep-alive. | Post the 8.14 request. |
| #22 | ZD Ultimate Legend 413D:2104 | 8.13 | The report of a 15% default dead zone does not hold: the default is 0 (`VirtualGamepadReportMapping.swift:16-21`, verified). The only 0.15 is `SleepGate.swift:4`, an idle-sleep gate, not a stick transfer. A later claim of a dead zone on the output path is not reconciled. | Do 8.13; answer the reporter with the line reference and ask for the capture that shows the dead zone. |
| #31 | WR-007 receiver 11C1:5600 (reporter arthurknowles34-a11y) | 8.14 | Bundled record `11c1-5600.plist` already holds the issue body's usages (buttons 1, 2, 4, 5, 7, 8, 11, 12, 14, 15; Z/Rz right stick; Accelerator/Brake triggers; hat) and a 0.02 `stickDeadzone`, so no new record or patch. The posted diff targets the old JSON and Swift parser layout. Byte offsets of the 9-byte report are not posted (only the neutral report), no capture exists, Guide sends no report, rumble is unverified, and the Apple GameController path has no hardware result. | Post the 8.14 request. |
| #34 | 8BitDo 2C wireless (reporter fmilioni) | 2.10 | Last comment 2026-11-09. | Do 2.10. |
| #35 | Flydigi Vader 4 Pro (reporter scraton) | 8.11 | Waiting on reporter. PR #36 is linked. | Do 8.11. |
| #37 | Flydigi Vader 4 Pro (reporter scraton) | 8.11 | Waiting on reporter. | Do 8.11. |
| #38 | PS3/PC pad 2563:0575 (reporter kartinul) | 8.14 | Bundled record `2563-0575.plist` already matches the reporter's `pad_config.json` (issuecomment-5748821075) for every control: face and shoulder pressure bytes 11 to 16, triggers 17 and 18, D-pad pressure bytes 7 to 10, byte 1 bits 0 to 3, sticks bytes 3 to 6. `ReportLayoutDriverTests` now covers each of them; no new record. Not in the data: Guide (record bit 12 is unverified), stick Y direction (the file's `inverted` is relative to Xbox up-positive), the report on the 0.6.0 build. | Post the 8.14 request. |
| #41 | 8BitDo Ultimate 2C Bluetooth LE 2DC8:301B (reporter ductrsan-sys) | 2.9, 2.10 | Last comment 2026-11-10. | Do 2.9 and 2.10. |
| #48 | Logitech F710 046D:C21F (reporter S3c012) | 8.6 | AliAnam71 on alpha.2: every input and rumble work; Guide does not open the macOS Game Overlay. OJD sends Guide as System Main Menu in report 2 (`XboxSeriesBluetoothReport.swift:15-16`) and lists it in the GameControllerCompatible controls (`VirtualHIDProfile.swift:52`). Apple: the Home button's response while an app is frontmost follows `GCControllerHomeButtonSettingInAppAction` (macOS 27), and `preferredSystemGestureState` is not guaranteed. | Ask on alpha.3: does Home light in Input Test, and does Guide open the overlay with Finder frontmost? Do 8.6 for the replug failure. |
| #53 | PowerA 20D6:2028 (reporter Simopich) | 8.5 | Waiting on reporter. | Do 8.5. |
| #55 | Xbox Elite Series 1 045E:02E3 (reporter konnsim) | 8.1, 8.2, 8.3 | Reporter commented 2026-11-09. PR #56 is the fix. | Do 8.1 to 8.3. |
| #58 | Ferrari 458 Spider 044F:B671 (reporter deniskabana) | 5.1, 8.4 | Waiting on reporter. | Do 5.1 and 8.4. |
| #59 | 8BitDo Ultimate C Wired 2DC8:2027 (reporter nightmare2122) | 3.1, 3.4, 5.1 (3.2 and 3.3 relate) | Linux usbmon capture fetched and compared in `evidence/gip-2dc8-2027/usbmon-compare.md` (3.1 evidence). No bundled record. The reporter's alpha.2 test failed; no frames reach OJD. | Do 3.2 to 3.4 and 5.1; the compare file lists the differences to test. |
| #62 | PowerA Spectra 20D6:4002 (reporter ElAscendido) | 8.9 | Last comment 2026-11-09. PR #50 is linked. | Do 8.9. |
| #63 | GameSir G7 Pro WUCHANG dongle 3537:1022 (reporter dnfanjos) | 8.16, 9.15, 9.16, 9.18 (17.2, 17.3 relate) | Opened 2026-11-10, no comments. Covered by 8.16, 9.15, 9.16 and 9.18. | Do those tasks; 8.16 drafts the capture request for 3537:1022 and 3537:10A8. |

## Pull requests

| Item | Device or topic | Task | State | Maintainer's remaining action |
| --- | --- | --- | --- | --- |
| #36 | scraton, Flydigi Vader 4 Pro | 5.6, 8.11 | Conflicting with `main`; checks failing. | Do 8.11; decide on 5.6 (what to take from the branch). |
| #39 | multision, Wolverine V3 TE | 5.6, 8.10 | Conflicting with `main`. | Do 8.10; decide on 5.6. |
| #47 | mattallty, GameSir K1 through Generic HID | 8.12 | Conflicting with `main`; no checks. `3537:1082` is shared with the G7 SE (`docs/testing/gamesir-family.md:16`), so no record is added. The body describes the K1 layout in prose (input report 5, 10 bytes) and holds no descriptor bytes or raw reports, so no descriptor-decoding test is added. | Do 8.12; ask for the K1's `ojd controller capture` output and descriptor if a decoding test is wanted. |
| #50 | Anonim0Venezian0, PowerA Spectra | 5.6, 8.9 | Conflicting with `main`. | Do 8.9; decide on 5.6. |
| #54 | bdidier | 8.7 | Conflicting with `main`. | Do 8.7. |
| #56 | konnsim, Elite Series 1 | 8.3 (with 8.1) | Mergeable; checks mixed (failure and success). Covered by 8.1 and 8.3. | Do 8.1 and 8.3 and merge or replace. |
| #57 | phil-bbs | 8.8 | Conflicting with `main`; check neutral. | Do 8.8. |
| #64 | bdidier, XUSB receiver boundaries and reconnection | 8.7 | Targets a non-default branch; review skipped. Ported onto the branch: the 02A9 state-bytes decode test, the XboxXUSB presence-resend tuning rejection (in-range value, Receiver variant), and the receiver doc text. The truncated-report and reconnect cases already exist on the branch. Not ported: the PR's 02A9 evidence section (the branch already holds the PR #54 section). | Do 8.7. |

## Closed issue noted, not a row

- #33 (SCUF Envision Pro 2E95:434D) is closed. Its reporter said vertical stick movement is reversed in Input Test. The stick Y direction is not traced.

## Task 8.14 evidence requests (drafts, not posted)

Flags come from `Sources/OpenJoystickDriverCLI/Commands/Controller/ControllerWatchCommand.swift:333` (`ojd controller capture CONTROLLER [--duration SECONDS]`; CONTROLLER is an ID from `ojd controller list` or `VVVV:PPPP`; the global `--json` prints one raw report per line with `direction`, `hex`, `length`, `captureTime`). The packet log covers USB IN, OUT and control transfers and HID input reports. Packets go to stdout; the warning "Packet contents vary by controller. Check them before sharing." goes to stderr.

Common text for each draft:

> Please run `ojd controller list` and paste its output. Then run the command below, and follow the press sequence while it runs. Attach `capture.ndjson`, and `support-report.json` from `ojd diagnose --output support-report.json`. Look through both before you attach them; the capture holds every packet the controller sent.

### #8 Steam Controller 28DE:1102

```
ojd controller capture 28de:1102 --duration 40 --json > capture.ndjson
```

Press sequence: leave the pad untouched for 5 s, then press A, B, X, Y one at a time, then move each stick to each edge, then press each trigger fully. Attach: the capture, the `ojd controller list` output (does the pad appear as 28DE:1102, wired?), and the `ojd diagnose` report. Say whether the earlier "0 reports" still happens.

### #11 Logitech F310, XInput mode

```
ojd controller capture VVVV:PPPP --duration 40 --json > capture.ndjson
```

Replace `VVVV:PPPP` with the ID that `ojd controller list` shows for the F310 (the report names none; the bundled XInput record is `046D:C21D`). Press sequence: each face button in turn, then D-pad up, down, left, right, then bumpers, triggers, stick clicks, Start, Back. Attach: the capture, the list output, and a note of the switch position on the back of the pad (X or D).

### #19 Razer Wolverine V2 1532:0A29

```
ojd controller capture 1532:0a29 --duration 40 --json > capture.ndjson
```

Press sequence: leave the pad untouched for 10 s, then each button, stick and trigger in turn. Attach: the capture, the list output, the diagnose report, and whether the Xbox button light still flashes during the run. The capture shows whether input packets arrive while OJD reports "USB device unavailable; retrying".

### #21 Nacon Revolution X Pro 3285:0634

```
ojd controller capture 3285:0634 --duration 60 --json > capture.ndjson
```

Do not press anything for the first 15 s (the drop after the handshake shows in that window), then press each button in turn. Attach: the capture, the list output, and the diagnose report. The reporter's own log suggests the pad needs no host keep-alive `03 20 ..`; the capture shows whether the drop comes after OJD's first keep-alive (4 s).

### #31 WR-007 receiver 11C1:5600

```
ojd controller capture 11c1:5600 --duration 40 --json > capture.ndjson
```

Press sequence: leave the pad untouched for 5 s (neutral is `00 00 0f 80 80 80 80 00 00` in the report), then each button, then each stick to each edge. Attach: the capture, the list output, and a note of which pad is paired to the receiver.

### #38 PS3/PC pad 2563:0575

```
ojd controller capture 2563:0575 --duration 40 --json > capture.ndjson
```

Press sequence: each button in turn in the order printed on the pad, then each stick to each edge. Say which mode the pad is in (PS3/PC). Attach: the capture, the list output, the diagnose report, and the mapping file and Python script from the report if they changed.
