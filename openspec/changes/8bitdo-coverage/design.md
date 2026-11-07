## Context

Facts checked against the tree before planning:

- Authored records `2dc8-301b.json` and `2dc8-301c.json` sit in `Resources/Controllers/2dc8/`. The other eight bundled `2DC8` records (`2000`, `2002`, `200f`, `3106`, `3109`, `310a`, `310b`, `6001`) exist only as generated files in `Sources/OpenJoystickDriverKit/Resources/Controllers/2dc8/`, so a change to them is a `ControllerPatch` in `Resources/ControllerPatches/2dc8/`. `3106`, `3109`, `310a` and `310b` each hold one `default` mode on `XboxXUSB`/`Wired`.
- `2dc8-301c.json` has the same usage list as `2dc8-301b.json`; `docs/testing/8bitdo-ultimate-2c.md:9` says the layout is assumed.
- `2dc8-301b.json:95-118` maps usage page 1 usages 50 and 51 to `RightStickX` and 52 and 53 to `RightStickY`; the test document (lines 13-15) says the right stick is on `Z` and `Rz`. Usage 50 is `Z`, 51 is `Rx`, 52 is `Ry`, 53 is `Rz`.
- The control vocabulary has `LeftPaddle1`, `LeftPaddle2`, `RightPaddle1` and `RightPaddle2` (`Resources/Vocabulary/crosswalk.json`). The test document (line 35) leaves usages 3, 6, 9 and 10 unmapped.
- `session.keepAlive` applies to raw-USB modes only (`controller.schema.json`, description of the mode session). A `HIDDescriptor` mode has no keep-alive field, so a watchdog fix for a HID mode is not expressible in a record today.
- `ojd controller capture CONTROLLER [--duration SECONDS] [--json]` prints raw packets; `ojd record test VVVV:PPPP --packets CAPTURE --expect STATE` replays them but exits `E2011` for a record whose parser needs a device.
- `docs/testing/tester-builds.md` says what a tester attaches to a report: `OpenJoystickDriver-TESTER-BUILD.txt`, the support report, and `ojd controller capture <controller> --duration 10 --json > capture.jsonl`.
- The documentation tiers of `wiki/Supported-Controllers.md` (Official, Community-Verified, Unverified) are documentation only. The record has no field for them, so "unverified" lives in the wiki and the test documents.
- No bundled record names `2DC8:3208` or `2DC8:5750`.

Claims from the research notes that no source in the tree confirms: the descriptor sizes of `6012` (145 and 113 bytes), the idle-to-`310A` swap of `301C` after about 6 seconds, the `3109` standby meaning, the Pro 3 presenting as `310B`, the roughly 1 second watchdog, and the L4/R4/P1/P2 defaults on the 2C. Each is a starting assumption of an unverified record and a tester check, never a premise.

## Decisions

### D1: Best Available Record, Verified by a Tester Capture

For an identity in scope, the plan writes the record the sources support (the HID usage tables, the layouts of the project's own `2DC8` records, the research notes). The record is unverified until a tester capture replays through its test. Two kinds of test fixture exist:

- source-derived: bytes built from the usages the record maps. The file name has `source` in it and the test document lists it as unverified.
- captured: bytes from a tester's `ojd controller capture --json`. The file name has `capture` in it.

A captured fixture replaces the source-derived one for the same identity when it arrives, and the wiki row moves to Community-Verified only then. A capture that disproves a mapping corrects the record in the same change, with no alias for the earlier mapping. A record for an identity whose protocol cannot be guessed from a source (`3107`, `6013` idle devices) maps no controls and says so in its document, rather than inventing a layout.

### D2: Tester Capture Unit

Each tester check card in `docs/testing/8bitdo-tester-checks.md` names the build to install (a tester build, per `docs/testing/tester-builds.md`), the mode to put the pad in, and the commands below. The tester sends back the files named in the card and a line saying which controls they pressed in which order.

1. `ioreg -r -c IOHIDDevice -l -w0 > hid.txt`, then keep the entry whose `VendorID` is 11720: `ReportDescriptor`, `VersionNumber`, `Product`, `Manufacturer`, `Transport`.
2. `ioreg -p IOUSB -l -w0 > usb.txt`: device and interface classes, endpoints, `bcdDevice`.
3. `ojd controller list` and `ojd controller show VVVV:PPPP`, copied into the report.
4. `ojd controller capture VVVV:PPPP --duration 20 --json > capture.jsonl` while each control is pressed one at a time in the order the card lists.
5. `OpenJoystickDriver-TESTER-BUILD.txt`.

The card lists a control order that matches the record: face buttons, bumpers, stick clicks, View, Menu, Home, Capture, each rear button, each stick direction, each trigger. The descriptor decides usages; the packet capture decides what the descriptor does not state.

### D3: One Record per VID:PID, Modes by Match Key

A model reached through several PIDs gets one record per PID. When one PID shows two different descriptors (`6012` cable and dongle), the starting record uses one usage map. A second mode is added only if the tester captures show conflicting maps, and only with a `match` key that exists today (`interfaceSignature`, `manufacturer`, `product`, `bcdDevice`, `probes`). No key selects by descriptor length. If the descriptors conflict and no existing key separates them, the change documents the conflict and keeps the record that serves the cable (the capture the tester sends first); it does not add a match key (that is a change to `device-matching`).

### D4: 301C, 3109, 310B Starting Choices

| Identity | Starting record | Changed by a capture that shows |
| --- | --- | --- |
| `301C` | An `idle` record (below): no controls, no traffic, no virtual gamepad; the document says the pad swaps to `310A`. The copy of the `301B` layout comes out. | A DInput mode with gamepad input: the record carries the usage map from the descriptor. |
| `3109` | Stays `XboxXUSB`/`Wired`, unverified. | A configuration or standby HID interface: the patch changes the protocol to the one the descriptor shows, or maps nothing. |
| `310B` | One record, one name that says Ultimate 2 and Pro 3, unverified. | Strings or descriptor that tell them apart: two modes keyed on `product`. |

An identity OJD recognizes and serves nothing uses `"idle": true`, a record key that exists for this case. A record cannot map no controls otherwise: `hidUsageMap.usages` needs one entry, a `HIDDescriptor` record without `input.hidUsageMap` uses the family's standard map and serves a gamepad, and a record without a `default` mode reports `NoModeMatched`, which says the ID is shared with other models. An `idle` record has one `default` mode and no `usb`, `bluetoothLE`, `capabilities`, `server`, `route`, `input` or `tuning`. `ProtocolClassifier` returns `IdleIdentity` before it binds, so no driver runs, the virtual device is never created, and the Controllers page and `ojd status` say the device serves no controls (`ui.controllers.idleIdentity`). `6013` and `3107` use the same form. The mode's family is the one the identity's descriptor would use (`HIDDescriptor` for a HID receiver) and is inert while `idle` is set.

### D5: Paddles

`L4`, `R4`, `P1` and `P2` map to the four paddle controls for a model whose descriptor or capture shows each as a bit that is separate from L3, R3 and the other buttons. For the 2C they default to L3 and R3 on the pad, so the 2C records map no paddle until a capture shows a separate bit. The order of the four (which of `P1`, `P2`, `L4`, `R4` is `LeftPaddle1`) follows the physical position on the pad: left pair to `LeftPaddle1` and `LeftPaddle2`, right pair to `RightPaddle1` and `RightPaddle2`, upper button first. The tester card asks which button each usage so the order is confirmed.

### D6: Gyro

The Ultimate 2 gyro in DInput and Switch mode gets a path only if a capture shows motion fields in a report OJD can decode with an existing layout or protocol family. If it needs a decoder that does not exist, this change records the report layout in the test document and leaves the decoder to a later change. The record then declares no motion, and the controller detail shows none.

### D7: Watchdog and Idle Dongle on macOS

The research reports that some firmware resets USB after about 1 second without a host transfer and that a dongle drops when nothing reads. Neither is measured on macOS. The tester check measures:

- With the pad served: it stays listed in `ioreg -p IOUSB -w0` for 5 minutes (proposed) with no input.
- With the controller suspended (`ojd controller suspend`): note whether the device leaves the bus within 10 seconds (proposed) and whether it returns on `ojd controller resume`.

Outcomes: no drop (record nothing; the document states the result), a drop only when no reader runs (document it; no OJD behavior hides it), or a drop while OJD serves the pad (a named, tested keep-alive). A keep-alive for a raw-USB mode uses `session.keepAlive`. For a HID mode the record cannot express one, so a drop while serving a HID pad is a finding that opens a change to the HID session fields; this change adds no hidden periodic write.

### D8: Bootloader Identities

`2DC8:3208` and `2DC8:5750` are bootloader identities. A write to a pad in bootloader state risks a bad firmware image. The plan guarantees no traffic to them by test, not by omission: the generic HID binding (a device with no record that matches a protocol by interface signature) can still reach a device that has no record. The test enumerates the paths that send to a device (startup writes, probes, keep-alive, output, configuration, generic binding) and asserts that each refuses these two IDs. Where the refusal lives (record data or a named check in the binding code) is decided in task 1.2 after reading the binding code; whichever is chosen has a name, a user-facing sentence and a test.

### D9: Vendor Configuration Protocol

Output report `0x81` identify and configuration traffic is not sent. The exception is an input fault proven by a capture: a pad that sends no input until a vendor report is written. That case becomes a record `session.startup` entry with the capture as evidence. Without such a capture there is no vendor write.

### D10: Licenses of Sources

OJD is licensed under PolyForm Noncommercial 1.0.0 with a commercial license, so code from GPL, AGPL or unlicensed repositories (for example the 8bd-u2cw GPL-3.0 source named in the research) is not ported. Its facts (descriptor layouts, report offsets, byte values) may be recorded, and the code is written independently. MIT, BSD, zlib, CC0 and Apache-2.0 sources (s8n and TheJayMann, when their license is one of these) may be used with their notice kept in `THIRD_PARTY_NOTICES.md`. The plan expects data and no port.

### D11: Documents

`docs/testing/8bitdo-ultimate-2c.md` stays the 2C record. The Ultimate 2 family gets `docs/testing/8bitdo-ultimate-2.md`, and `901B` is documented in the same file or a third file named by its model once a capture shows what it is. `docs/testing/8bitdo-tester-checks.md` holds the tester cards. The wiki tables list every model and mode with VID:PID, protocol, state and source. The text states current behavior only. History goes in `CHANGELOG.md`.

## Risks

- Testers own the Ultimate 2C; the Ultimate 2, Pro 3, 3-mode and receivers may have no tester. Their records stay unverified, and the wiki says so.
- A usage map that fits one descriptor can mis-read another firmware. Each verified record names the firmware or `bcdDevice` of its capture.
- A source-derived record can send a button to the wrong control. The Unverified tier says so, and the tester card exists to find it.

## Open Questions

- Whether `6012` cable and dongle descriptors conflict (settled by the tester check T5).
- Which testers hold an Ultimate 2, a Pro 3, an Ultimate 3-mode and a receiver (settled when the cards go out).
