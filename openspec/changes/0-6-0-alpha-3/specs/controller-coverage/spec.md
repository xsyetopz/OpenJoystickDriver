## ADDED Requirements

### Requirement: Xbox Elite Series 1 Completes Its Handshake

OJD SHALL complete the GIP handshake with the Xbox Elite Series 1 (`045E:02E3`) on input endpoint `0x81` and output endpoint `0x01`, and MUST publish its input.

#### Scenario: Elite Series 1 by cable

- **WHEN** an Xbox Elite Series 1 connects by cable
- **THEN** the first write to the output endpoint succeeds and OJD publishes input

### Requirement: Interrupt Transfers in the Driver Extension Use No Timeout

The driver extension SHALL pass a timeout of 0 for every transfer on an interrupt endpoint.

#### Scenario: Record with a transfer timeout

- **WHEN** a record sets `usbTransferTimeoutMs` to 2000 and the controller's endpoint is an interrupt endpoint served by the extension
- **THEN** the extension's transfer passes 0 and does not fail with a bad-argument error

### Requirement: A Failing Handshake Does Not Loop

OJD SHALL retry a failed session start with a growing delay, and MUST stop after a fixed number of attempts and report the failure on the controller.

#### Scenario: Handshake fails every time

- **WHEN** a controller fails its handshake on every attempt
- **THEN** the attempts stop, the controller detail shows the last error, and the driver extension stays running

### Requirement: A GIP Wheel Publishes Steering and Pedals

OJD SHALL publish the steering axis and the pedals of the ThrustMaster wheel `044F:B671` from the fields its GIP input report carries.

#### Scenario: Steering

- **WHEN** the user turns the wheel from lock to lock
- **THEN** OJD publishes the steering axis across its full range

#### Scenario: Brake

- **WHEN** the user presses the brake pedal
- **THEN** OJD publishes the brake and the steering axis does not move

### Requirement: The Guide Button Is Published on Third-Party GIP Pads

OJD SHALL publish the Guide button of a GIP pad that sends it in the virtual-key packet, including the PowerA `20D6:2028`.

#### Scenario: Guide press

- **WHEN** the user presses Guide on a PowerA `20D6:2028`
- **THEN** OJD publishes the Guide control as pressed, and as released when the user lets go

### Requirement: A Reconnected XUSB Controller Is Served Again

OJD SHALL serve an XUSB controller again after the user unplugs it and plugs it back, without a restart of the service.

#### Scenario: Logitech F710 receiver replugged

- **WHEN** the user unplugs and replugs the Logitech F710 receiver `046D:C21F`
- **THEN** `ojd controller show` reports an active session and OJD publishes input

### Requirement: Xbox 360 Wireless Receiver Slots

OJD SHALL decode input from a pad linked to the Xbox 360 wireless receiver `045E:02A9`, and MUST list only the slots that hold a linked pad.

#### Scenario: One pad linked

- **WHEN** one pad is linked to the receiver
- **THEN** `ojd controller list` shows one controller for the receiver and OJD publishes that pad's input

### Requirement: Contributed Controllers Ship in the Current Format

Each controller a pull request or issue contributes with evidence SHALL ship as a `v1alpha3` record or patch: Turtle Beach Rematch Advanced Wired (`10F5:711E`), PowerA Spectra Enhanced Wired (`20D6:4002`), and Razer Wolverine V3 Tournament Edition (`1532:0A43`).

#### Scenario: PowerA Spectra connects

- **WHEN** a PowerA Spectra Enhanced Wired `20D6:4002` connects
- **THEN** OJD binds the record and lists the controller under its product name

#### Scenario: Contributed record passes the checks

- **WHEN** the repository check runs
- **THEN** each contributed record and patch validates against its schema

### Requirement: Flydigi Vader 4 Pro Modes

OJD SHALL serve the Flydigi Vader 4 Pro through its dongle and in its Bluetooth XInput mode from record data.

#### Scenario: Dongle mode

- **WHEN** the Vader 4 Pro is linked through its dongle
- **THEN** OJD publishes its buttons, sticks, and triggers

### Requirement: One Identity Has One Record

OJD SHALL hold at most one record for a vendor and product identifier, and the repository check MUST fail when a contributed record repeats an identity.

#### Scenario: GameSir K1 identity

- **WHEN** a contributed record for `3537:1082` meets a bundled record for that identity
- **THEN** the check fails and names both files

### Requirement: A Support Claim Rests on a Capture

OJD's documentation SHALL describe a controller or mode as verified only when a capture from that hardware exists, and MUST name what is missing for each controller it lists as unverified.

#### Scenario: Controller with a report and no capture

- **WHEN** an issue reports a controller and holds no capture
- **THEN** the documentation lists it as unverified and the issue holds a request that names the capture command

### Requirement: GameSir G7 Pro Works Through Its Dongle

OJD SHALL serve the GameSir G7 Pro through its 2.4 GHz dongle (`3537:1022`), where the device exposes HID gamepad interfaces, from a mode of its record, and MUST keep the record's `XboxGIP` mode for the interface that mode names.

#### Scenario: Dongle

- **WHEN** the pad is linked through its dongle and the dongle exposes HID gamepad interfaces
- **THEN** OJD binds the record's `HIDDescriptor` mode and publishes the pad's buttons, sticks, and triggers

#### Scenario: GIP interface

- **WHEN** the device exposes the interface the `XboxGIP` mode names
- **THEN** OJD binds that mode

### Requirement: The Documentation States the Count of Bundled Records Once

OJD's documentation SHALL take the count of bundled controller records from the generated record set.

#### Scenario: Count in the wiki

- **WHEN** a wiki page states how many controller records OJD bundles
- **THEN** the repository check compares the number with the generated record set and fails when they differ
