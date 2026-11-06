## ADDED Requirements

### Requirement: Bluetooth Extra Buttons Reach Consumers

The record for `D7D7:0041` SHALL decode byte 11 of the 15-byte report, counting the report ID as byte 0: C as `Auxiliary1`, Z as `Auxiliary2`, and the four back buttons as `LeftPaddle1`, `LeftPaddle2`, `RightPaddle1` and `RightPaddle2`. Each decoded control SHALL reach the virtual device and the Input Test.

#### Scenario: C and Z Pressed

- **WHEN** a report arrives with bit `0x01` of byte 11 set
- **THEN** `Auxiliary1` is pressed, and it is released by the next report with the bit clear

#### Scenario: Back Buttons Pressed

- **WHEN** a report arrives with bits `0x04`, `0x08`, `0x10` and `0x20` of byte 11 set one at a time
- **THEN** each of the four paddle controls is pressed in turn and no other control changes

#### Scenario: Offsets Count the Report ID

- **WHEN** the test builds a report with `0x01` at index 0 and sets index 11
- **THEN** the decoded control is the one in byte 11 of this requirement

### Requirement: Stick Range and Guide Are Confirmed by a Sweep

The documents SHALL record, from a tester capture of a full sweep of each stick, the minimum and maximum byte of each stick axis, and the capture of Guide at byte 12. The record's stick range SHALL equal the captured extremes.

#### Scenario: Sweep Matches the Record

- **WHEN** a sweep capture of `D7D7:0041` replays and the extremes equal the record's range
- **THEN** the document lists the range as confirmed

#### Scenario: Sweep Differs

- **WHEN** the sweep shows an extreme outside the record's range
- **THEN** the record's range changes to the captured extremes and a test replays the sweep

### Requirement: Vader 5S Serves Each Interface It May Show

The record for `37D7:2801` SHALL hold one `XboxGIP` mode selected by interface signature `FF/47/D0` and one `XboxXUSB` mode selected by `FF/5D/01`. `ojd controller show` SHALL report which mode runs. `docs/testing/flydigi-vader-5s.md` SHALL state that neither mode is verified until a tester sends the USB interface dump.

#### Scenario: GIP Interface

- **WHEN** the pad shows an interface `FF/47/D0`
- **THEN** the `XboxGIP` mode runs

#### Scenario: XUSB Interface

- **WHEN** the pad shows an interface `FF/5D/01`
- **THEN** the `XboxXUSB` mode runs

#### Scenario: Neither Interface

- **WHEN** the pad shows neither signature
- **THEN** the default mode runs, the log names the interface classes seen, and the document explains the state

### Requirement: Vader 5 Pro Dongle Delivers the Extended Report

The record for `37D7:2401` SHALL deliver sticks, buttons including C, Z and M1 to M4, and triggers from the extended 32-byte report (`5A A5 EF`) on its HID interface, after the init writes and the test-mode write that the record lists. It SHALL deliver gyro and accelerometer samples only when a driver decodes them. The mode that runs SHALL be shown by `ojd controller show`. A failed init or test-mode write SHALL be reported as a startup failure and SHALL NOT start another mode in its place.

#### Scenario: Extended Report Decoded

- **WHEN** an extended report arrives with sticks, buttons and triggers set
- **THEN** each control is delivered at the offsets the record lists

#### Scenario: Init Write Fails

- **WHEN** an init write is refused by the dongle
- **THEN** the controller shows a startup failure with the write that failed
- **AND** no XUSB mode starts as a replacement

#### Scenario: Motion without a Decoder

- **WHEN** the dongle sends gyro samples and no driver decodes them
- **THEN** the record declares no motion and the document names the report and offsets

### Requirement: Vendor Output Is Limited to Named Commands

A Flydigi record SHALL send a frame `5A A5 cmd len payload sum8` only for a command it lists: the `37D7:2401` startup commands (1, 0xA1 and 2), grip rumble (18), trigger force mode (81) and trigger force sync (82). The frame length byte SHALL be the payload length plus 2, and the last byte SHALL be the low byte of the sum of cmd, len and payload. OpenJoystickDriver SHALL NOT send the screen upload (31), UID (4) or any other command.

#### Scenario: Frame Checksum

- **WHEN** the frame builder is given command `0x11` and payload `FF 01 FF FF FF`
- **THEN** it returns `5A A5 11 07 FF 01 FF FF FF 15`

#### Scenario: Unlisted Command

- **WHEN** code asks to send a command that no record lists
- **THEN** nothing is sent and the request fails with a named error

#### Scenario: Rumble Request

- **WHEN** the user runs `ojd controller rumble CONTROLLER --left 128 --right 64`
- **THEN** the pad receives one grip rumble frame with those intensities and a valid checksum

### Requirement: Apex 4 Has a DInput Record

The catalog SHALL hold a record for `04B4:2412` on usage page `0xFFA0` with input report 4 and output report 5. The documents SHALL say that the record is unverified until a tester capture replays, and that the XInput mode appears as `045E:028E`.

#### Scenario: DInput Report Replayed

- **WHEN** a test replays a report in the record's layout
- **THEN** each mapped control is delivered

#### Scenario: XInput Mode

- **WHEN** the Apex 4 is in XInput mode
- **THEN** it is the Microsoft `045E:028E` record and the Flydigi record does not apply

### Requirement: Each Flydigi Record Has a Test Document and a Wiki Entry

`docs/testing/` SHALL hold a document per Flydigi model with a record, giving the VID:PID, the modes, the protocol, the source of each mapping and the tier. `wiki/Supported-Controllers.md` SHALL have an entry for every Flydigi record. `docs/development/wire-protocols.md` SHALL describe the Flydigi output that the records send.

#### Scenario: Reader Looks Up a Flydigi Pad

- **WHEN** a reader looks for `37D7:2401`
- **THEN** the wiki lists the model, the modes, the protocol and the tier

### Requirement: Vader 5S Hardware Evidence Is Cited

`docs/testing/flydigi-vader-5s.md` SHALL cite commit `98b7b0eb6` as the evidence of `37D7:2801` as GIP, with its recorded provenance `local-hardware` and `verified: true`, and SHALL say that the provenance field is not in the record format and that the evidence is not verification.

#### Scenario: Evidence Cited

- **WHEN** a reader opens the Vader 5S document
- **THEN** it cites commit `98b7b0eb6` and its provenance values and states that they are not verification

### Requirement: Source Licenses Are Respected

OpenJoystickDriver is licensed under PolyForm Noncommercial 1.0.0 with a commercial license. Code from GPL, AGPL or unlicensed repositories SHALL NOT be copied or ported; only facts (offsets, byte values, framing) MAY be recorded, and code SHALL be written independently. A source under MIT, BSD, zlib, CC0 or Apache-2.0 MAY be used, and its notice SHALL be in `THIRD_PARTY_NOTICES.md` in the commit that first uses it.

#### Scenario: Permissive Source Used

- **WHEN** a commit uses the openflydigi `PROTOCOL.md` or the uiltonlopes protocol notes
- **THEN** `THIRD_PARTY_NOTICES.md` holds the notice in the same commit

#### Scenario: Copyleft Source

- **WHEN** a fact comes from a GPL or AGPL repository
- **THEN** only the fact is used and no code from that repository is in the tree

### Requirement: Tester Check Cards

`docs/testing/flydigi-tester-checks.md` SHALL hold one card per Flydigi identity in scope. Each card SHALL name the tester build, the mode, the exact commands, the order to press controls, and the files to send back.

#### Scenario: Tester Runs a Card

- **WHEN** a tester follows the card for `37D7:2801`
- **THEN** every command runs as written in the tester build and the card lists the files to attach
