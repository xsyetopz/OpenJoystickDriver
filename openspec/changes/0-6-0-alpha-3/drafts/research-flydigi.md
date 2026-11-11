# Flydigi research notes (task 9.22, 8.11, issues #35 #37, PRs #36 #40 #30 #1)

Research only. No code was changed, built, pushed or posted. All behaviour below is paraphrased from the sources; no source code is copied. GPL and unlicensed sources were read in full for behaviour only.

Mark key: AGREES / EXTENDS / CONTRADICTS = relation to our records. "read" = from reading a source, "unverified" = no hardware check by us.

## 1. Sources and licenses

| Source | License | Pinned commit | Read? |
| --- | --- | --- | --- |
| <https://github.com/zsuzuki/Apex5Connect> | MIT | 21d1ce70c8cc | read: a Bluetooth re-pair menu-bar app (calls `blueutil`); no HID protocol content |
| <https://github.com/deuxdoom/APEXGIFMAKER> | custom LICENSE (SPDX NOASSERTION) | cf52cb4abca2 | listed only; README/screen tool not read in depth |
| <https://github.com/dracinn/ControlLab> | unknown | n/a | NOT READABLE: `gh api` returned 404 |
| <https://github.com/kitty-panics/Flydigi-Vader-5S> | none stated | a5944d7dd72e | read: udev rule + README only |
| <https://github.com/LH-03/flydigi-vader5-dualsense-haptics> | MIT | cb84e14bcdb5 | not read in depth (on-board profile code skipped) |
| <https://github.com/mkaliaha/openflydigi> | mixed (REUSE: CC0 / GPL-3.0-or-later / MIT); `PROTOCOL.md` CC0 per `docs/development/compatibility-sources.md:68-75` | 9ab15b4b8a75 (our doc pins 11653507bbe4) | `PROTOCOL.md` read; `docs/findings-*.md` and `flydigi/*.py` not read |
| <https://github.com/LeeeSe/controller> | none stated | 6cd112cbbb1b | read `src/hid.rs` |
| <https://github.com/LARo-developer/vader5-pro-android> | GPL-2.0 | e182c35c56d4 | `docs/PROTOCOL.md` read (behaviour only) |
| <https://github.com/uiltonlopes/flydigi-space-station-mac> | MIT | 649b9f36cbba | `docs/protocol.md` read; Swift sources listed, not read |
| <https://github.com/Jackwmtr/flydigi-apex4-linux> | MIT | afd2e431485e | `docs/PROTOCOL.md` read |
| <https://github.com/kristoferssolo/flydigi-tools> | Apache-2.0 / MIT | c99726e7f3 | `core/src/lib.rs` read: generic hidapi wrapper only, no protocol |
| <https://github.com/RezenDeveloper/xpad_flydigi> | none stated; xpad fork, GPL-2.0 by derivation | a715da71c69f | not read (C file and `reference/bytes-*.txt` skipped) |
| <https://github.com/BANANASJIM/flydigi-vader5> | GPL-2.0 | 5d8671db056f | `include/vader5/protocol.hpp` read |
| <https://github.com/ahungry/vader3> | GPL-3.0 | 360cc0942337 | `hid-vader3.c` and udev rule read |

Line numbers for external files were not captured; cite by file path plus the pinned commit.

## 2. Two protocol dialects

- Old dialect: VID not 0x37D7 (Apex 3/4, Vader 3/4, Direwolf). Vendor HID collection on usage page 0xFFA0; input report 4 (32 B), output report 5 (host commands are `05 <cmd> args`, padded; a too-short report is silently ignored). Source: space-station-mac `docs/protocol.md` sections 1-2 (MIT); Jackwmtr `docs/PROTOCOL.md` (MIT).
- New dialect: VID 0x37D7 (Apex 5/6, Vader 5). Frames `5A A5 <cmd> <len+2> payload sum8`, 32 B, report ID 3 out / 4 ack on usage page 0xFFA0. Checksum is an 8-bit sum over the command, length and payload bytes; commands 18, 81, 82 need none. Source: openflydigi `PROTOCOL.md` (CC0).
- Space Station's XInput channel (interface 0 of `045E:028E`, needs device capture/root) uses 15-byte `A5 <cmd> args crc`. Source: space-station-mac protocol section 2.

## 3. Identity table (VID:PID per mode)

| Model / mode | VID:PID | Source | License | Relation to our records |
| --- | --- | --- | --- | --- |
| Vader 4 Pro, Bluetooth DInput | D7D7:0041 | issue #35; ahungry (Vader 3 BT, same id) | repo / GPL-3.0 | AGREES `Resources/Controllers/d7d7/d7d7-0041.plist` |
| Vader 4 Pro, Switch mode | 057E:2009 | issue #35 | repo | no record (patches only exist for 2066/2067/2069 under `Resources/ControllerPatches`); works via generic path per reporter |
| Vader 4 Pro / Apex 4, dongle or wired DInput | 04B4:2412 | #35; space-station-mac; Jackwmtr | repo / MIT / MIT | AGREES `Resources/Controllers/04b4/04b4-2412.plist` identity; CONTRADICTS its docs claim of Apex-4-only and "no rumble" (`docs/testing/flydigi-apex-4.md`) |
| Vader 4 Pro, Bluetooth XInput | 045E:02E0 | #35; LeeeSe lists 02E0 as a generic Xbox BT pad | repo / unlicensed | no record under `Resources/Controllers/045e` for it (gap) |
| Vader 4 Pro dongle XInput, Apex 4 XInput | 045E:028E, product string "Flydigi VADER3" (dongle) / "Flydigi APEX 4" (wired) | #37; space-station-mac sections 7-8 | repo / MIT | PARTLY: `Resources/ControllerPatches/045e/045e-028e.patch.plist` is XUSB-only; see section 9 |
| Vader 5 Pro dongle | 37D7:2401 | LARo; openflydigi | GPL-2.0 / CC0 | AGREES `Resources/Controllers/37d7/37d7-2401.plist` |
| Apex 5 wired and dongle | 37D7:2501 | openflydigi | CC0 | no record in this branch checked by me; no 37d7-2501 read |
| Vader 5S | 37D7:2801 (GIP default, XUSB interface on Linux via `xpad` `new_id`) | kitty-panics rule; our record | none stated | AGREES `37d7-2801.plist` mode `xusb` |
| Apex 4 DInput over Bluetooth | 04B4:2412 on BT (`0005:04b4:2412`), 21-byte report, no vendor collection | Jackwmtr | MIT | extends: our `04b4-2412.plist` assumes the USB vendor report; BT has none |
| Xbox-class pads LeeeSe watches | 045E:028E, 02E0, 02FD, 02EA, 0719 | LeeeSe `src/hid.rs` | unlicensed | no Flydigi-specific content (an unrelated Xbox-pad gyro tool) |

## 4. Input report layouts

### 4.1 Old dialect, vendor report 4 (32 B), USB DInput

Facts (space-station-mac section 9, verified on Apex 4; issue #35 capture on a Vader 4 Pro dongle; Jackwmtr):

- Byte 7: extra buttons C, Z, M1..M4 (Apex 4 also M5/M6) in bits 0-5. Byte 8: Home is bit 3 (Fn/Menu and Turbo in other bits, Back bit 4 per space-station-mac).
- Byte 9: low nibble up/right/down/left bits, high nibble A, B, Select, X. Byte 10: Y, Start, LB, RB, LT, RT, L3, R3.
- Bytes 17, 19 left stick X/Y; 21, 22 right stick; 23, 24 triggers; stick centre 0x7F.
- Motion bytes 4-6, 18, 20, 26-30; bytes 11-15 behave like a counter.

Comparison with `Resources/Controllers/04b4/04b4-2412.plist` (report ID 4, 32 B, sticks at bit offsets 136/152/168/176, buttons byte 9/10, paddles byte 7 bits 0-5, Guide byte 8 bit 3, triggers at bits 184/192): AGREES with space-station-mac and #35.

CONTRADICTION: Jackwmtr puts the RIGHT stick at bytes 17/19 and LEFT at 21/22, the reverse of the others and of our plist. Two sources plus the reporter's capture side with us; resolve by a capture (task 8.11) before changing anything. Jackwmtr also reads Home from the gamepad interface's Consumer page and gives paddle order 3,5,4,2 (mask 0x3C) physically, so our M1-M4 assignment (bits 2-5) is unverified.

### 4.2 Old dialect, BT DInput 15-byte report (`D7D7:0041`)

Our `Resources/Protocols/vendor-flydigi.plist` (report ID 1, exactly 15 B; sticks at bytes 1-4 signed-symmetric; hat nibble at bit 72; buttons from bit 76; aux/paddles bits 88-93; Guide bit 103; triggers at bits 104/112) matches our captured test (`Tests/OpenJoystickDriverKitTests/Protocol/Drivers/Vendor/FlydigiParserTests.swift`, firmware 6.9.5.5). ahungry's Vader 3 driver agrees on the byte-11 paddle/C/Z area and uses an 8-way hat encoding (our record uses a 4-bit table: consistent in kind). EXTENDS: Vader 3 shares `D7D7:0041`.

### 4.3 Bluetooth XInput `045E:02E0` (issue #35, PR #36)

Report ID 1, 16 B: sticks at bytes 1/3/5/7 as unsigned 16-bit LE centred 0x7FFF; triggers at 9/11 (10-bit, max 1023); hat byte 13; face and shoulder bits in byte 14 (A 01, B 02, X 04, Y 08, LB 10, RB 20, Back 40, Start 80); stick clicks byte 15 (L 01, R 02); Home arrives on a separate report ID 2 (byte 1 bit 0). No record exists in this branch: GAP.

### 4.4 New dialect extended report (`5A A5 EF`, 32 B, Vader 5 Pro dongle `37D7:2401`)

- Header `5A A5 EF`; signed 16-bit LE sticks at bytes 3-10; triggers bytes 15/16; gyro 17-22; accel 23-28 (4096 = 1 g). Sources: LARo (GPL-2.0), BANANASJIM `protocol.hpp` (GPL-2.0).
- Buttons: byte 11 face/dpad, byte 12 Y/Start/LB/RB/L3/R3, byte 13 C/Z/M1-M4/LM/RM, byte 14 O and Home (bit 3).
- CONTRADICTION between sources on byte 11 low nibble: LARo reads it as one bit per direction; BANANASJIM reads it as a 4-bit value through a 16-entry table. Resolve by capture. BANANASJIM also negates Y axes (needed for our axis sign convention).
- Our `37d7-2401.plist` maps 32 B, no report ID, signed 16-bit sticks at bits 24/40/56/72, triggers at bits 120/128 (AGREES with byte 3-10 and 15/16) and maps NO buttons: EXTENDS needed.

## 5. Init / handshake for extended input

- Old dialect: no init. The vendor report streams, including IMU, on both the USB vendor interface and in XInput mode (Jackwmtr: unconditional, about 1000 Hz dongle / 500 Hz wired). Space-station-mac says motion streams only when the active profile's motion map is not Off; this CONTRADICTS Jackwmtr (probably firmware/profile difference). Source: both MIT.
- New dialect: LARo needs `01`, `A1`, `02`, `04` commands after connect, then test-mode `11 07 FF 01 FF FF FF` (+ checksum) to enable the extended report and IMU. Our `37d7-2401.plist` sends `01`, `A1`, `02` and `11` but omits `04` (UID read): AGREES partially, EXTENDS (add cmd 04, unverified whether needed).
- Space Station's first command is `06`, which a Vader 5 Pro ignores (space-station-mac sections 7-8).
- Vader 5S GIP: named packets (see PR #40 section).

## 6. Rumble / haptics output

- Old dialect: output report 5, frame `05 0F <left> <right>` (issue #35; space-station-mac "motor test"; Jackwmtr). It latches until a zero-magnitude frame; ~10 Hz resend needed to sustain; a lone frame decays; killing the writer leaves the motors running. `04b4-2412.plist` declares no rumble: CONTRADICTS #35 (the pad rumbles).
- XInput mode via vendor channel: `A5 12 L R` (space-station-mac). Standard Xbox 360 rumble on interface 0 `00 08 00 L R 00 00 00` (LARo).
- New dialect: command 18 (`5A A5 12 06 ...`), grip motors, trigger motors at payload positions 3/4 on Vader (openflydigi, LARo). AGREES with `37d7-2401.plist` rumble template (report 3, low-frequency byte 5, high byte 6, triggers 7/8).
- Trigger force-feedback: commands 81/82, per side, persists in the pad (openflydigi).

## 7. LED / screen / config commands (Space Station config protocol)

- Device info: `A5 10` / `05 EC` (battery level byte 11: 0..5, 6 charging, per Jackwmtr).
- Config read (790 B): `A5 21` / `05 EB`, 79 parcels of 10 B. Config write `A5 25` + `A5 24` / `05 EA` + `05 22`. LED read (500 B) `A5 26` / `05 E5`; LED write `A5 2A` + `A5 29` / `05 E7` + `05 33`. Save to flash `... 50 03 hi lo`; switch slot `50 05 slot`. Module versions `30 01`; ForceAdapt `30 06`/`A0`; ADC calibration `14` / `E2`.
- Config blob: key table (32 entries), sticks, triggers, motion, vibration, ForceAdapt (185..224), data version (225..226), macros (230..767), title UTF-16LE (770..789). LED blob: header plus 16 groups of 10 RGB units, 0-100; modes flow 1, breath 2, gradient 3, feedback 4, on 5, off 6, default 7.
- Ordering quirk (stateful): in XInput an LED write alone is acknowledged but ignored; write the full config, wait about 500 ms, then the LED config.
- Mode switch: DInput to XInput `05 ED`; XInput to DInput `A5 17 ... crc`. Both re-enumerate.
- Screen: 160x80 LCD, RGB565 big-endian, 25604 B per frame; upload via XInput channel only (`A5 D0..D3`); the DInput path starts then NAKs and needs a power cycle. The dongle does not forward uploads. New dialect: report-ID-3 families 208-211 do nothing visible; flooding colour 242 needs a power cycle; command 31 enters a serial OTA mode (CDC, VID FFAA PID 5555, own CRC) (openflydigi).
- New dialect mapping/lighting blobs: commands 161-169, 840 B in 42 packets of 20 B; macros 172-174; v3.1 macros at 230, v3.2 (Vader 5) separate 1620 B store; default 3 retries at 500 ms, flash writes 10 s (openflydigi).
- A bad checksum on mapping/lighting is answered with silence (openflydigi).

None of section 7 is in our records. Our scope is input and rumble.

## 8. Other source notes

- ahungry `hid-vader3.c` (GPL-3.0): kernel driver for Vader 3 BT `D7D7:0041` that fixes up a paddle bit and Consumer-page Home; stick range about +/-115. Behaviour consistent with `d7d7-0041.plist`.
- kitty-panics (no license): Vader 5S `37D7:2801` is bound to Linux `xpad` through `new_id`: AGREES with the `xusb` mode of `37d7-2801.plist`.
- LeeeSe `src/hid.rs` (unlicensed): Xbox-pad gyro mapping tool, offsets valid for Xbox BT reports, not Flydigi-specific; contains no Flydigi init.
- flydigi-tools: device listing only.
- Apex5Connect: Bluetooth re-pair helper; not protocol.
- Not read: ControlLab (404), APEXGIFMAKER, LH-03, xpad_flydigi, BANANASJIM `hid-flydigi.c`, openflydigi `docs/findings-*`.

## 9. Repo issues and PRs

### Issue #35 (open): Vader 4 Pro dongle DInput and BT XInput fall to generic fallback

- Reporter scraton; Vader 4 Pro firmware 6.9.5.5; macOS 26.5.2; OJD 0.5.0-beta.4. Identities: see section 3. Dongle DInput is composite: `1:5` gamepad (9 B), `0xFFA0:1` vendor (32 B in/out), `0xFFEE:0` (64 B, unused), `1:2` mouse (gyro drives the pointer). Enumeration order is unstable, so match by usage page. BT XInput report layout: section 4.3. Vibration: section 6. Capture note: use per-device input-report callback with an explicit buffer; `OpenJoystickDriverHIDTool --monitor` uses the manager-level callback and delivers short reports under load (a separate bug).
- Our records today: `Resources/Controllers/04b4/04b4-2412.plist` already exists (report 4, 32 B, no rumble); no `045e-02e0` record.
- Resolving change (proposal): (a) add `Resources/Controllers/045e/045e-02e0.plist` with `HIDReportLayout` and two layouts (report ID 1: unsigned 16-bit axes centred 0x7FFF with 10-bit triggers; report ID 2: Guide bit); the schema must express unsigned 16-bit axes with a centre (check `min/max/centre` in the axis schema before relying on it; unverified); (b) in `04b4-2412.plist` add a `rumbleTemplate` for output report 5 `05 0F L R` with a stop template and `minimumHIDOutputIntervalMs` near 100; (c) match the vendor interface by `interfaceSignature.usagePage` 0xFFA0; (d) rename the docs from "Apex 4" to "Apex 4 / Vader 4 Pro dongle". Maps to task 8.11.

### Issue #37 (open, priority low): dongle XInput `045E:028E` on the HID path

- Reporter's device: dongle XInput identity `045E:028E`, product "Flydigi VADER3", 20-byte standard xpad reports. macOS surfaces it through HID while a real 360 pad on the same identity is raw USB. A record's `transport` holds one value; the old `ParserRegistry` compared it exactly, so the HID path missed and fell to `GenericHIDParser`. Patching to `hid` worked; the reporter's prototype third transport value broke `RawUSBAdmissionPolicyTests.specializedParsersRequireTheirCatalogedTransport` and `HIDProfileDiscoveryTests.hidAndRawUSBCatalogPartitionsAreDisjoint`.
- Our records: `Resources/ControllerPatches/045e/045e-028e.patch.plist` (XboxXUSB wired, SHANWAN control transfers). The mode `match` keys (`Resources/Schemas/controller.schema.json:167`) are link, interfaceSignature, manufacturer, product, bcdDevice, probes: no access-backend key.
- Resolving change (proposal, not verified): add a mode with `match.product` equal to "Flydigi VADER3" on the HID path so one identity splits by product string, after a probe confirms the product string is readable on the HID path; or add a `backend` match key (hid | usb) to `modeMatch`. The second is cleaner and keeps one catalog partition rule. Needs a design.md decision (task 8.11).

### PR #36 (open, CONFLICTING, base main): Vader 4 Pro dongle and BT XInput

- Head `fix/controllers-flydigi-vader-4-pro-dongle`, "Fixes #35"; 17 files: JSON overrides `045e-02e0.json` and `04b4-2412.json` (old `driver` architecture, `transport: "hid"`), schema, new Swift parsers `FlydigiVendorParser.swift` (268 lines) and `XboxBluetoothHIDParser.swift` (221 lines), `ParserRegistry`, `TransportProfiles`, `USBProtocolClassification`, UI strings, `FlydigiVader4ProModeTests.swift` (460 lines), `docs/testing/flydigi-vader-4-pro.md`.
- Still needed? The information is needed; the diff is not. It targets the removed JSON/Swift-parser architecture, so it conflicts with this branch. Both layouts are expressible as record data, so the two Swift parsers should not be re-created. Reuse its test captures and the offsets in section 4.3 as fixtures. Task 8.11 already says "re-create ... as record data". Resolution: close #36 with a comment pointing to the record-data change once 8.11 lands (the maintainer decides; we post nothing).

### PR #40 (merged to main, Vader 5S USB GIP init)

- Changes `37d7-2801.json`: adds startup packets `horiAck, ledOn, authDone, powerOn` and removes `postHandshakeSettleMs: 200`.
- Our branch: `Resources/Controllers/37d7/37d7-2801.plist` has no `initialization` and still has `settleMilliseconds` 200 for the default `XboxGIP` mode. The plist conversion (`af9cc004f`) predates #40, so the change was lost in the merge. Resolution (proposal): add `protocol.initialization` with the four named packets (`controller.schema.json:349`, carried as `gipStartupPackets` in `ControllerMode.swift:157`) and drop the 200 ms settle if the packets supersede it. Hardware check needed (not done).
- Does it affect 9.22? No. It is a GIP named-packet init, not a Flydigi vendor protocol, and it is already data. `VendorFlydigi` (the family 9.22 moves) is the 15-byte report; the 5S uses the GIP/XUSB drivers.

### PR #30 (closed): Vader 4 Pro Bluetooth, `FlydigiParser.swift` (226 lines)

Superseded by the `VendorFlydigi` layout record (`Resources/Protocols/vendor-flydigi.plist`, `d7d7-0041.plist`). Nothing to resolve.

### PR #1 (merged 2026-05-05): Vader 5S support with per-device endpoint config

Background for `37d7-2801`; no open work beyond the PR #40 re-port.

## 10. Answer to the 9.22 question

Question: can every Flydigi model and mode we support be described by a layout document alone, or does any need a handshake, stateful init or checksum?

Answer: YES for input and rumble, with limits.

Evidence:

1. `VendorFlydigi` already runs through the generic layout path: `ProtocolDriverRegistry.swift:249` returns `describedLayoutDriver()`; it has no session, startup or output (`docs/development/wire-protocols.md:47`, `Resources/Protocols/vendor-flydigi.plist`). Moving it into a document is therefore sound.
2. The handshake and checksum modes are already data: `37d7-2401.plist` bakes the `5A A5` frames with sum8 as literal bytes (`docs/development/wire-protocols.md:48`); schema startup writes accept raw bytes, `crc32Seed` and transport (`controller.schema.json:603`). Commands 18, 81, 82 need no checksum.
3. `04b4-2412` is stateless (streaming vendor report 4, no enable command; Jackwmtr).
4. `045E:02E0` is stateless: two layouts selected by report ID through `ReportLayoutDriver` (`indexOfLayout(selecting:)`).
5. The 5S GIP init (#40) is `protocol.initialization` data.

Limits, so the yes is not over-claimed:

- Not describable by a layout: Space Station config/LED/screen/OTA transfers (parcel acknowledgement loops, read-modify-write, "config then ~500 ms then LED" ordering, serial OTA with its own CRC). These are a config protocol, outside 9.22.
- Latching rumble (`05 0F`) needs a resend cadence and a stop frame: expressible with `minimumHIDOutputIntervalMs` plus a second template, but not shown to work on hardware.
- Issue #37 needs a new match key (backend) or a product-string split; this is a schema issue, not a layout limit.
- Byte-11 hat conflict (4.4) and the left/right stick conflict (4.1) are capture questions, not expressibility problems.
- No hardware verification for several records ("Unverified" in `wiki/Supported-Controllers.md:82-91`), so the yes concerns expressibility, not correctness. The maintainer hardware step of 9.22 stays open.

## 11. Facts mapped to open tasks and proposals

| Task | Facts | Proposal |
| --- | --- | --- |
| 9.22 (`tasks.md:138`) | section 10 | Install `VendorFlydigi` as a user layout document; compare layout offsets with `Resources/Protocols/vendor-flydigi.plist`; evidence under `evidence/document-family/`. |
| 8.11 (`tasks.md:107`) | sections 3, 4.1, 4.3, 6, 9 | Add `045e-02e0.plist`; add rumble to `04b4-2412.plist`; decide #37 with a `backend` match key in `design.md`; fixtures from the #35/#36 captures. |
| 8.11 follow-up | PR #40 | Port the four GIP startup packets to `37d7-2801.plist`; hardware check. |
| none yet (new) | 4.4 | Map `37d7-2401` buttons from the extended report after a capture settles byte 11 (LARo vs BANANASJIM); consider adding cmd 04. |
| none yet (new) | 4.1 | Capture to settle stick order and paddle bit order for `04b4-2412`. |

Tests proposed (not written): a catalog test that `04b4:2412` declares a rumble template; a layout test that `045E:02E0` neutral capture (`01 00 7F FF 7F 00 7F FF 7F 00 00 00 00 00 00 00`) decodes to centred sticks; a catalog test that `37d7:2801` carries four startup packets; a transport/match test for #37 once the key exists.
