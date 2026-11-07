## ADDED Requirements

### Requirement: No Traffic to 8BitDo Bootloader Identities

OpenJoystickDriver SHALL NOT send any write, output report, feature report, control transfer, probe, startup step, keep-alive or configuration packet to a device with VID:PID `2DC8:3208` or `2DC8:5750`. This holds for devices with a record and for devices bound without a record. Each refusal SHALL have a log line that names the VID:PID and the reason, and the controller detail SHALL say that the device is a bootloader and receives no traffic.

#### Scenario: Bootloader Device Attached

- **WHEN** a device with `2DC8:3208` or `2DC8:5750` attaches
- **THEN** the service sends it no transfer of any kind
- **AND** the log has one line naming the VID:PID and that it is a bootloader identity

#### Scenario: Generic Binding Reaches a Bootloader Device

- **WHEN** a bootloader identity exposes an interface whose signature would bind a protocol
- **THEN** the binding does not start the protocol and no startup step runs

#### Scenario: Test Covers Every Sending Path

- **WHEN** the test suite runs
- **THEN** a test attempts startup, probe, keep-alive, rumble and configuration for each bootloader identity and asserts that no transfer reaches the transport

### Requirement: Unverified Records Are Marked until a Capture Replays

A bundled 8BitDo record whose mapping rests on sources and not on a tester's capture SHALL have a test with a source-derived fixture, and the wiki and the test document SHALL list its controller in the Unverified tier. A capture from a controller SHALL replace the source-derived fixture, and only then SHALL the wiki list the controller as Community-Verified. A capture that disproves a mapping SHALL correct the record, with no alias for the earlier mapping.

#### Scenario: Record from Sources

- **WHEN** `2DC8:301D` has a record and no capture
- **THEN** the record's test uses a fixture whose name says it is source-derived
- **AND** the wiki lists the controller as Unverified

#### Scenario: Capture Arrives

- **WHEN** a tester's capture of `2DC8:301D` replays through the record's test with every control matching
- **THEN** the captured fixture replaces the source-derived one
- **AND** the wiki lists the mode as Community-Verified with the tester's firmware or `bcdDevice`

#### Scenario: Capture Disproves a Mapping

- **WHEN** a capture shows a button on a different control than the record maps
- **THEN** the record maps the button as the capture shows and no entry keeps the earlier mapping

### Requirement: A Record Maps Only What Its Source Declares

An 8BitDo record SHALL map each stick axis only to the usages that the controller's report descriptor, or the best source for that model, declares for that stick. A record SHALL NOT map a usage that no source declares, and SHALL NOT map two usages to one control unless a capture shows that both carry that control's value.

#### Scenario: 2DC8:301B Right Stick

- **WHEN** the record of `2DC8:301B` is written from the test document that places the right stick on `Z` and `Rz`
- **THEN** the record maps `Z` to `RightStickX` and `Rz` to `RightStickY` and maps `Rx` and `Ry` to nothing
- **AND** a test replays a right-stick sweep and expects both axes to move while both triggers stay at rest

#### Scenario: Descriptor Declares Another Stick

- **WHEN** a tester's descriptor dump of `2DC8:301B` declares the right stick on `Rx` and `Ry`
- **THEN** the record maps those usages and the entries for `Z` and `Rz` are removed

### Requirement: Idle and Configuration Identities Claim No Input

The records for `2DC8:301C`, `2DC8:3107` and `2DC8:6013` SHALL map no controls until a capture shows gamepad input on that identity. The record for `2DC8:3109` SHALL keep `XboxXUSB` only until a capture shows another interface. The supported-controllers page SHALL say what each mode is.

#### Scenario: 301C Is an Idle Receiver

- **WHEN** the record of `2DC8:301C` has no capture
- **THEN** it is an `idle` record: OJD sends it no data, creates no virtual gamepad and reports the reason `IdleIdentity`
- **AND** the document says the receiver re-enumerates as `2DC8:310A` and that this is unverified

#### Scenario: 301C Shows Gamepad Input

- **WHEN** a tester's capture of `2DC8:301C` shows gamepad input
- **THEN** the record carries a usage map from that descriptor

#### Scenario: 3109 Shows a Configuration Interface

- **WHEN** a tester's dump of `2DC8:3109` shows a HID configuration interface and no Xbox 360 class interface
- **THEN** the record does not claim `XboxXUSB`

### Requirement: One Identity per Descriptor Difference

When one VID:PID shows different report descriptors in different modes or connections, the record SHALL cover each with one usage map when the maps agree, and with separate modes selected by a match key that exists in the record format when they do not. If no existing key separates conflicting descriptors, the record SHALL serve the connection that a capture covers and the document SHALL state the conflict.

#### Scenario: 6012 Cable and Dongle Agree

- **WHEN** the cable descriptor and the dongle descriptor of `2DC8:6012` give the same control for every shared usage
- **THEN** one default mode with one usage map serves both
- **AND** a test replays a capture from each connection

#### Scenario: 6012 Cable and Dongle Conflict

- **WHEN** a usage means a different control in the two descriptors and no match key separates them
- **THEN** the record serves the connection with a capture and the test document states the conflict

### Requirement: Paddle Mapping Only for Separate Inputs

A record SHALL map `L4`, `R4`, `P1` and `P2` to `LeftPaddle1`, `LeftPaddle2`, `RightPaddle1` and `RightPaddle2` only when a descriptor or capture shows each as an input that is separate from every other control. A paddle that repeats another control SHALL NOT be mapped. The test document SHALL record which physical button each paddle control is.

#### Scenario: Separate Paddle Bits

- **WHEN** the descriptor of an Ultimate 2 in DInput mode declares four rear buttons as four distinct button usages
- **THEN** the record maps them to the four paddle controls
- **AND** a test replays each and expects the matching paddle control

#### Scenario: Paddles Repeat L3 and R3

- **WHEN** a pad sends the rear buttons as the stick-click bits
- **THEN** the record maps no paddle and the document says the rear buttons repeat L3 and R3

### Requirement: Motion Data Only with a Decoder

A record SHALL declare motion for an 8BitDo model only when a capture shows motion fields and OpenJoystickDriver can decode them. A model with a gyro and no decoder SHALL declare no motion, and the document SHALL name the report that carries it when a capture shows it.

#### Scenario: Gyro without a Decoder

- **WHEN** a capture of an Ultimate 2 in Switch mode shows motion samples that no bundled protocol decodes
- **THEN** the record declares no motion
- **AND** the test document records the report and field offsets

### Requirement: Idle and Watchdog Behavior Is Measured and Named

For each 8BitDo pad that the research reports as dropping its USB link without host transfers, a tester's macOS measurement SHALL show whether the device leaves the bus while served and while not read. A keep-alive SHALL be added only for a drop while OpenJoystickDriver serves the pad. Any keep-alive SHALL be a field of the record (or protocol description) with a test and user-facing text, and no periodic write SHALL be sent that a document does not name.

#### Scenario: No Drop While Served

- **WHEN** a served pad stays listed in `ioreg -p IOUSB -w0` for the measured time with no input
- **THEN** no keep-alive is added
- **AND** the test document records the measurement

#### Scenario: Drop While Served

- **WHEN** a served raw-USB pad leaves the bus without host transfers
- **THEN** the record carries a `session.keepAlive` with the interval the measurement supports
- **AND** a test asserts the packet and interval

#### Scenario: Drop While Served on a HID Mode

- **WHEN** a served HID pad leaves the bus and the record format has no field for a HID keep-alive
- **THEN** no write is added
- **AND** the test document records the finding for a change to the HID session fields

### Requirement: Vendor Configuration Traffic Is Not Sent

OpenJoystickDriver SHALL NOT send the 8BitDo configuration protocol (identify, profile read or write, firmware) to an 8BitDo device. A record MAY list one startup write only when a capture shows that the pad sends no input until it is written, and the record's document SHALL cite that capture.

#### Scenario: Pad Sends Input without Configuration

- **WHEN** a pad sends input after attach with no host write
- **THEN** the record has no vendor write

### Requirement: Tester Check Cards Name the Commands and the Returns

`docs/testing/8bitdo-tester-checks.md` SHALL hold one card per identity in scope. Each card SHALL name the tester build to run, the mode to put the pad in, the exact commands to run, the order in which to press controls, and the files to send back (the tester build text file, the `ioreg` dumps, the packet capture and the support report).

#### Scenario: Tester Runs a Card

- **WHEN** a tester follows the card for `2DC8:301B`
- **THEN** every command on the card runs as written in the tester build
- **AND** the card lists the files to attach

### Requirement: Documents List Every 8BitDo Model and Mode

`wiki/Supported-Controllers.md`, `wiki/Connecting-Controllers.md` and the files under `docs/testing/` SHALL list every 8BitDo model that has a record, with each mode's VID:PID, protocol, tier and the capture or tester check that supports it. A mode that has no record SHALL appear as not covered. A model that shares a VID:PID with another model SHALL be named together with it.

#### Scenario: Reader Looks Up a Mode

- **WHEN** a reader looks for `2DC8:6012`
- **THEN** the wiki lists the model, the mode, the protocol and the tier

#### Scenario: Shared Identity

- **WHEN** the Pro 3 and the Ultimate 2 present `2DC8:310B`
- **THEN** the wiki names both models in one row and says how the host tells them apart or that it cannot
