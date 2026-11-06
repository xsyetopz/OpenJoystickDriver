## Context

Facts checked against the tree and git before planning:

- `D7D7:0041` is documented as the Vader 4 Pro over Bluetooth Low Energy, firmware 6.9.5.5, observed on macOS 26.5 (`docs/testing/flydigi-vader-4-pro.md`). The research notes call it the Vader 3 or 3 Pro; the tree's own capture names the 4 Pro, so this change keeps that name and adds "Vader 3 and 3 Pro" only if a tester shows the same identity.
- The report is ID `0x01`, 15 bytes, and every offset counts the ID as byte 0: `FlydigiParserTests` builds reports with `report[0] = 0x01` and sets `report[11]`, `report[12]`. The question of how bytes are numbered is answered by those tests. The document table places C at `0x01`, Z at `0x02` and M1 to M4 at `0x04` to `0x20` of byte 11, which matches the layout in the ahungry/vader3 notes (facts only; GPL source).
- `Resources/Protocols/vendor-flydigi.json` lists buttons at bytes 9, 10 and 12 only, adds only `Guide` to the Xbox controls, and has no byte 11 entry. No test sets `extras` (`FlydigiParserTests.swift` defines the parameter and never passes it). The document's sentence that byte 11 is "decoded" is wrong against the description.
- The document says input decoding "is verified against captured reports for every control in the table", which includes Guide (byte 12, mask `0x80`) and the stick offsets (neutral `FF`, `0x7F` right, `0x80` up). The record's stick range is -128 to 127, symmetric. The research claim that Guide is unverified and that the ahungry range (-115 to 115 with flat 25) conflicts is dropped: that range is another driver's dead zone choice, and the tree's capture shows the full byte. A tester sweep still confirms the extremes, because one firmware generation is not every generation.
- `Resources/Controllers/37d7/37d7-2801.json` has one `XboxGIP` mode with `usb.endpoints` in 129 and out 1, `configuration: SetConfiguration1BeforeClaim` and `session.settleMilliseconds: 200`. Commit `98b7b0eb6` (2026-07-12) added it with `provenance: {source: local-hardware, verified: true}`; commit `e216983a3` removed the provenance field from the schema. The evidence for GIP lives only in git history.
- The `XboxXUSB` description (`Resources/Protocols/xbox-xusb.json`) declares interface signatures `FF/5D/01` (Wired) and `FF/5D/81` (Receiver); `XboxGIP` binds `FF/47/D0`. A mode can match on `interfaceSignature`, and a raw-USB mode may name `endpoints`.
- `controller.schema.json` allows an input byte offset up to 63 and 8 or 16 bit axes, so a 32-byte report fits a declarative layout. It has no motion fields; gyro and accelerometer data need Swift.
- Checksum check of the research framing `5A A5 cmd len payload sum8` (len is the payload length plus 2, sum8 is the low byte of cmd + len + payload): `5A A5 01 02 03` gives 0x01+0x02 = 0x03; `5A A5 11 07 FF 01 FF FF FF 15` gives 0x11+0x07+0xFF+0x01+0xFF+0xFF+0xFF = 0x415, low byte 0x15. Both agree with the research bytes.
- `docs/development/wire-protocols.md` says the Flydigi family "takes no output" and decodes through `ReportLayoutDriver` with no code. `ojd controller capture CONTROLLER --json` and `ojd record test` exist.
- No `04B4` or `2401` record exists. `wiki/Supported-Controllers.md` has no Flydigi entry.

Research claims not confirmed by any source in the tree (each is a starting assumption and a tester check): the `37D7:2801` interface signature, the 2401 endpoint numbers (IN 20 bytes on EP1, OUT 8 on EP5, HID EP2 IN 32 and EP6 OUT 32), the init and test-mode packets of the 2401, the extended report offsets (sticks int16 LE at 3 to 10, buttons 11 to 14, triggers 15 and 16, gyro 17 to 22, accel 23 to 28, 4096 = 1 g), the Apex 4 report sizes (output 5, 63 bytes; input 4, 31 bytes), the Apex 5 output report `0x03` and input `0x04`, and the cmd 18, 81 and 82 payloads.

## Decisions

### D1: Best Available Record, Verified by a Tester Capture

Per the user's decision (2026-10-25), the plan writes the best record the sources support, marks it unverified (the Unverified tier in the wiki and the test documents; the record has no field for it), and a tester card per identity returns a capture. A test fixture built from a source carries `source` in its name; a tester capture carries `capture` and replaces it.

### D2: Licenses

OJD is licensed under PolyForm Noncommercial 1.0.0 with a commercial license (user, 2026-10-25). The GPL, AGPL and unlicensed repositories in the research (ahungry/vader3, BANANASJIM, LARo vader5-pro-android, ControlLab, Vader-5S, LeeeSe) are facts only: offsets, byte values and framing are recorded, and all code is written independently. The openflydigi `PROTOCOL.md` (CC0) and the uiltonlopes protocol notes (MIT) may be used; the MIT notice and the CC0 dedication go to `THIRD_PARTY_NOTICES.md` in the commit that first uses them.

### D3: Byte 11 of the Bluetooth Report

C and Z map to `Auxiliary1` and `Auxiliary2`; M1 to M4 map to the four paddle controls in the starting order `LeftPaddle1`, `LeftPaddle2`, `RightPaddle1`, `RightPaddle2`, chosen as a proposal. The tester card asks the tester to name the physical button for each bit, and the record follows. The description adds the controls it uses to `controls.add`.

### D4: 37D7:2801 Serves Both Interfaces

The record has two modes: `gip` (interface signature `FF/47/D0`, `XboxGIP`, the current endpoints and session) and `xusb` (interface signature `FF/5D/01`, `XboxXUSB`/`Wired`). The mode that matches the connected pad runs; the other never does, and `ojd controller show` reports the mode. One of the two is `default` as the schema requires; the plan makes `gip` the default because it is the mode with a hardware record, and the tester check settles whether `xusb` is the one that appears. Both modes are unverified until a tester sends `usb.txt`. `docs/testing/flydigi-vader-5s.md` cites commit `98b7b0eb6` as evidence about the pad at that commit and states that it is not verification.

### D5: 37D7:2401 Needs Two Interfaces

The dongle exposes interface 0 (`FF/5D`, XUSB) and a HID interface 1 with 32-byte endpoints. A mode runs one protocol on one claim. The plan keeps two options and settles them in task 4.1 by reading the claim and mode-selection code:

- Option 1: a `default` mode on `XboxXUSB`/`Wired` for interface 0 (basic input and rumble through existing code) and a second mode, `extended`, keyed on the HID interface (class 3), that runs the init and test-mode writes and decodes the `5A A5 EF` report. If both modes' keys hold at once, the first listed runs; the order is `extended`, then `default`, and the controller detail shows which mode runs. Because OJD never switches modes and does not fall back silently, an `extended` mode whose init write fails reports the failure and does not start the XUSB mode in its place.
- Option 2: one mode on the HID interface only, if the code cannot run a mode that is selected over the other for the same device without hiding XUSB rumble.

Declarative first: the init writes are fixed HID output reports (`session.startup`), the 32-byte input report fits `input.layout` (16-bit axes, button bits, 8 or 16-bit triggers), so the controls need no Swift. A Swift driver is added only for the gyro and accelerometer (no motion fields in the record format); it decodes int16 samples at the offsets above with 4096 = 1 g, and its description has the startup data. Whether it is a variant of `VendorFlydigi` or a second family follows task 4.1: a variant if the description can hold the startup writes and the report ID, otherwise a family.

### D6: Apex 4

`04B4:2412` is a HID record on usage page `0xFFA0`: input report 4 (31 bytes), output report 5 (63 bytes), per the MIT protocol notes. The starting layout is written from those notes (a task reads them at an exact revision first, as `docs/development/compatibility-sources.md` requires) and is unverified. Its XInput mode appears as Microsoft `045E:028E` with the product string "Flydigi VADER3"; that Microsoft record is not changed here, and the document says so.

### D7: Vendor Output

Output uses the `5A A5 cmd len payload sum8` frame with sum8 over cmd, len and payload. The records name every command they send; the plan names three: grip rumble (18, with the trigger motors in payload bytes 7 and 8), trigger force mode (81) and the trigger force sync (82). The payloads are written from the CC0 `PROTOCOL.md` at an exact revision. Commands for screen upload (31), UID (4), device info (1, other than the init packet of the 2401) and anything else are not sent. A pure function builds the frame, so a test asserts bytes and checksum without a device. User-facing rumble uses the existing `ojd controller rumble` fields (`--left`, `--right`, `--left-trigger`, `--right-trigger`); trigger force modes need a name and a setting before the GUI or CLI exposes them, which is a task of its own after a tester confirms the grip rumble works. `wire-protocols.md` loses "takes no output" in the same commit that adds output.

### D8: Vader 3 Versus 4 Pro

The model name stays "Vader 4 Pro" in `D7D7:0041` documents. If a tester with a Vader 3 or Vader 3 Pro shows the same VID:PID and the same report, the wiki row names all three models; if their report differs, a mode keyed on `product` is added.

### D9: Documents

New: `docs/testing/flydigi-vader-5s.md`, `docs/testing/flydigi-vader-5-pro.md`, `docs/testing/flydigi-apex-4.md`, `docs/testing/flydigi-tester-checks.md`. Changed: `docs/testing/flydigi-vader-4-pro.md` (byte 11 controls reach consumers; the sentence that they do not is removed), `docs/development/wire-protocols.md`, `wiki/Supported-Controllers.md` (a Flydigi entry for every record, tier Unverified unless a tester verifies it). History goes in `CHANGELOG.md`.

## Risks

- Option 1 of D5 may be impossible with the current mode selection. Task 4.1 reads the code before any record is written.
- The 2401 init and test-mode writes are fixed by a GPL source's facts and one claim of the notes. A wrong write could leave the dongle in a mode that sends no input. The tester card sends no write by hand; only the startup of the record writes, and the record is unverified.
- Paddle order is a proposal until a tester names the buttons.
- A frame builder with a payload limit wrong for cmd 18 could overrun a 32-byte report. The frame test bounds length.

## Open Questions

- Which interface `37D7:2801` shows on the maintainer's pad and on a tester's (tester card F2).
- Whether the Vader 5 Pro dongle needs both modes selectable (task 4.1).
- Whether `04B4:2412` input uses the report ID in byte 0 of the 31-byte read (task 5.1 reads the descriptor).
