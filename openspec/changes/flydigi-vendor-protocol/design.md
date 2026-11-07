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
- No `2401` record exists. `04B4:2412` has a record; `37D7:2501` has only a generated `XboxXUSB` record imported from xpad and no hand-written record or test document. The wiki lists `D7D7:0041`, `37D7:2801` and `04B4:2412`.

Research claims not confirmed by any source in the tree (each is a starting assumption and a tester check): the `37D7:2801` interface signature, the 2401 endpoint numbers (IN 20 bytes on EP1, OUT 8 on EP5, HID EP2 IN 32 and EP6 OUT 32), the init and test-mode packets of the 2401, the extended report offsets (sticks int16 LE at 3 to 10, buttons 11 to 14, triggers 15 and 16, gyro 17 to 22, accel 23 to 28, 4096 = 1 g), the Apex 4 report sizes (output 5, 63 bytes; input 4, 31 bytes), the Apex 5 output report `0x03` and input `0x04`, and the cmd 18, 81 and 82 payloads.

## Decisions

### D1: Best Available Record, Verified by a Tester Capture

Per the user's decision (2026-10-25), the plan writes the best record the sources support, marks it unverified (the Unverified tier in the wiki and the test documents; the record has no field for it), and a tester card per identity returns a capture. A test fixture built from a source carries `source` in its name; a tester capture carries `capture` and replaces it.

### D2: Licenses

OJD is licensed under PolyForm Noncommercial 1.0.0 with a commercial license (user, 2026-10-25). The GPL, AGPL and unlicensed repositories in the research (ahungry/vader3, BANANASJIM, LARo vader5-pro-android, ControlLab, Vader-5S, LeeeSe) are facts only: offsets, byte values and framing are recorded, and all code is written independently. The openflydigi `PROTOCOL.md` (CC0) and the uiltonlopes protocol notes (MIT) may be used; the MIT notice and the CC0 dedication go to `THIRD_PARTY_NOTICES.md` in the commit that first uses them.

### D3: Byte 11 of the Bluetooth Report

C and Z map to `Auxiliary1` and `Auxiliary2`; M1 to M4 map to the four paddle controls in the starting order `LeftPaddle1`, `LeftPaddle2`, `RightPaddle1`, `RightPaddle2`, chosen as a proposal. The tester card asks the tester to name the physical button for each bit, and the record follows. The description adds the controls it uses to `controls.add`.

### D4: 37D7:2801 Serves Both Interfaces

The record has two modes: `default` (`XboxGIP`, the current endpoints and session) and `xusb` (interface signature `FF/5D/01`, `XboxXUSB`/`Wired`). The record format gives the default mode no keys, so GIP is the mode that runs for an interface `FF/47/D0` and for a pad that shows neither signature; the `xusb` mode runs only when its signature holds. `ojd controller show` reports the mode. The plan makes `gip` the default because it is the mode with a hardware record, and the tester check settles whether `xusb` is the one that appears. When no mode matches, the selector log names the interface classes seen, which is how a neither-signature pad shows what it exposed. Both modes are unverified until a tester sends `usb.txt`. `docs/testing/flydigi-vader-5s.md` cites commit `98b7b0eb6` as evidence about the pad at that commit and states that it is not verification.

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

### D10: A Record-Level Endpoint Override Must Change One Mode

`usb` is a record-level section, so its `endpoints` apply to every mode. The validator rejects an override equal to the default endpoints of the family, because it states nothing the family does not already say. With several modes the rule is: the override is rejected when it equals the default of every mode (it would change no mode) and accepted when it differs from the default of at least one mode. `37D7:2801` needs this: the endpoints recorded from hardware in GIP mode (in 129, out 1) are the `XboxXUSB` defaults and differ from the `XboxGIP` defaults (in 130, out 2), so the override moves the GIP mode and leaves the XUSB mode on its defaults. The schema has no per-mode endpoints, and adding them is a larger format change than this rule. `ControllerRecordDocument+Transport.swift` implements the rule with `allSatisfy`; `ControllerModeConditionalTests` and a `SchemaRejections` case (two `XboxXUSB` modes with the XUSB defaults) cover both sides.

## Risks

- Option 1 of D5 may be impossible with the current mode selection. Task 4.1 reads the code before any record is written.
- The 2401 init and test-mode writes are fixed by a GPL source's facts and one claim of the notes. A wrong write could leave the dongle in a mode that sends no input. The tester card sends no write by hand; only the startup of the record writes, and the record is unverified.
- Paddle order is a proposal until a tester names the buttons.
- A frame builder with a payload limit wrong for cmd 18 could overrun a 32-byte report. The frame test bounds length.

## Open Questions

- Which interface `37D7:2801` shows on the maintainer's pad and on a tester's (tester card F2).
- Whether the Vader 5 Pro dongle needs both modes selectable (task 4.1).
- Whether `04B4:2412` input uses the report ID in byte 0 of the 31-byte read (task 5.1 reads the descriptor).

## Open

### O1: Where the Vendor Frame Builder Lives and How Output Reaches It (tasks 6.2 to 6.4)

Facts from the pinned openflydigi `PROTOCOL.md` (commit `11653507bbe4dc77f3c479c2a7aaebf25bbda995`, sections 2, 3a and 7), which differ from D7 and the spec:

- Commands 18, 81 and 82 are the three commands whose vendor builders set no checksum byte, and the notes report that a pad accepted them with the checksum field left zero. The other commands end with the sum8 over the bytes from the command. D7 and the "Vendor Output" requirement apply sum8 to every frame.
- The frame on the `0xFFA0` node is report ID `0x03` followed by `5A A5 cmd len payload`, written as 32 bytes. The length byte counts the payload plus 2 for the SDK's checksummed commands; for 18 the notes give `[4]=6` with grip levels at frame bytes 5 and 6 and trigger motors at 7 and 8, and say the pad accepts a length byte that matches the real payload for 81.
- A Vader 5 declares no force trigger, so Space Station sends it command 18 and never 81 or 82. Command 82 has no mode byte (`side, bindType, filter, scale, stroke, pressureLevel, strength, frequency`); 81 has an apply flag and a mode byte with the effects `Normal` 0, `Race` 1, `Sniper` 2, `Recoil` 3, `Lock` 4, `Vibration` 5 (never sent by the vendor software), with `Sniper` and `Recoil` labelled the other way round in Space Station's UI.

Proposed decision for the coordinator:

1. The frame builder is one pure function, `FlydigiFrame.build(command:payload:checksum:)`, in `Sources/OpenJoystickDriverKit/Protocol/Drivers/Vendor/` beside the Flydigi driver. `checksum` is a two-case enum, `.sum8` and `.none`, and each command in a record names which it uses. The spec then says: the length byte is the payload length plus 2, and the last byte is sum8 for the commands that list `sum8`; commands 18, 81 and 82 list `none` per the notes until a tester confirms a pad that needs the byte. Hardware evidence: none; both forms are source-derived.
2. `ojd controller rumble` reaches it through the existing output path for the record: the Flydigi driver's rumble method calls the builder with command 18 and the four levels (`--left`, `--right`, `--left-trigger`, `--right-trigger`), writes the 32-byte frame with report ID `0x03`, and the test uses the fake transport that records writes. No new CLI flag.
3. The record names the allowed commands in a new `output.vendorCommands` list of `{ "command": 18, "checksum": "None" }` entries on a mode whose family reads it. A command that is not listed sends nothing and fails with a named error. Adding a record field needs the controller schema, `protocol-description` and `Resources/ErrorCodes.json` changes in one commit.
4. Trigger force modes (6.4) are a profile setting named after the effect enum (`Normal`, `Race`, `Sniper`, `Recoil`, `Lock`), applied through command 81 and offered only for a record whose pad has force triggers. The Vader 5 Pro has none, so 81 and 82 are not listed for it.
