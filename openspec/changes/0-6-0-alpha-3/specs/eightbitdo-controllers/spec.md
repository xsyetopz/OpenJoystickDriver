## ADDED Requirements

### Requirement: Ultimate 2C Wireless Works by Cable

OJD SHALL serve the 8BitDo Ultimate 2C Wireless connected by cable (`2DC8:310A`) with every button, both sticks, both triggers, the D-pad, and rumble.

#### Scenario: Cable input and rumble

- **WHEN** the pad is connected by cable and the user presses each control
- **THEN** `ojd controller watch 2DC8:310A` names each control as the pad labels it
- **AND** `ojd controller show 2DC8:310A` lists rumble with the low-frequency and high-frequency motors

### Requirement: Ultimate 2C Wireless Works Through Its Receiver

OJD SHALL serve the Ultimate 2C Wireless linked to its 2.4 GHz receiver in each mode the pad offers, under the identity the receiver enumerates with in that mode.

#### Scenario: Linked receiver delivers input

- **WHEN** the pad is linked to the receiver and the user moves the right stick
- **THEN** OJD publishes the movement on the right stick
- **AND** both triggers read 0 while at rest

#### Scenario: Receiver identity carries a controller record

- **WHEN** the receiver enumerates with a controller product string
- **THEN** `ojd controller list` shows one controller for it
- **AND** `ojd controller show` reports publication as published after the first input

### Requirement: Receiver Is Idle Only While No Controller Is Linked

OJD SHALL treat the receiver identity `2DC8:301C` as idle while its product string is `IDLE`, and MUST serve it as a controller when the product string names a controller.

#### Scenario: Receiver with no pad

- **WHEN** the receiver is plugged in and no pad is linked
- **THEN** OJD lists no controller for it and sends it no output

#### Scenario: Pad links after the receiver is plugged in

- **WHEN** a pad links to a receiver that OJD holds as idle
- **THEN** OJD starts serving the controller without the user unplugging the receiver

### Requirement: Ultimate 2C Wireless Works Over Bluetooth LE

OJD SHALL serve the Ultimate 2C Wireless over Bluetooth LE (`2DC8:301B`) with the right stick on `Z`/`Rz`, the right trigger on Accelerator, the left trigger on Brake, and each button under the name the pad labels it with. OJD MUST publish its virtual gamepad for the pad with no claim, patch, or setting from the user.

#### Scenario: Bluetooth pad with no user document

- **WHEN** the pad connects over Bluetooth LE and the user's `Controllers/` folder holds no document for it
- **THEN** `ojd controller show 2DC8:301B` reports `Handled by` `OJD` and, after the first input, publication as published

#### Scenario: Bluetooth pad in a GameController game

- **WHEN** OJD serves the pad over Bluetooth LE and the user runs `ojd virtual set game-controller-compatible 2DC8:301B`
- **THEN** a GameController probe lists one controller, and each control the user presses, other than Guide, changes that controller's state
- **AND** Guide reaches the GameController app in front

#### Scenario: Right stick over Bluetooth

- **WHEN** the pad is connected over Bluetooth LE and the user moves the right stick
- **THEN** OJD publishes the movement on the right stick and both triggers stay at 0

#### Scenario: Triggers over Bluetooth

- **WHEN** the user presses the right trigger fully
- **THEN** OJD publishes the right trigger at its maximum and the left trigger at 0

#### Scenario: Rear buttons over Bluetooth

- **WHEN** the pad is connected over Bluetooth LE and the user presses L4 and then R4
- **THEN** `ojd controller watch 2DC8:301B` names the left rear control and then the right rear control

### Requirement: Rumble in the Wireless Modes

OJD SHALL drive the rumble motors of the Ultimate 2C Wireless through the receiver as `2DC8:310A`. A `HIDDescriptor` mode MUST be able to declare the output report and motor fields that rumble uses. The records for the receiver as `2DC8:301C` and for Bluetooth LE (`2DC8:301B`) MUST declare rumble only for an output write shown on hardware to run a motor.

#### Scenario: Rumble through the receiver in XInput mode

- **WHEN** the user runs `ojd controller rumble 2DC8:310A --left 200` with the pad linked to the receiver
- **THEN** the pad's left motor runs

#### Scenario: Rumble over Bluetooth with a declared write

- **WHEN** the `2DC8:301B` record declares a rumble output and a game sends rumble to the virtual controller
- **THEN** the pad's motors run

#### Scenario: Record with no output section

- **WHEN** a `HIDDescriptor` mode declares no rumble output
- **THEN** `ojd controller show` lists no rumble for that controller

### Requirement: Rear Buttons Follow the Report

OJD SHALL publish a rear button of the Ultimate 2C Wireless as its own control in each mode where the pad sends it on its own bit. In a mode where the pad repeats another button's bit, the record MUST declare no rear control.

#### Scenario: Mode with a separate bit

- **WHEN** a capture of a mode shows the left rear button on its own bit
- **THEN** the record for that mode maps that bit to the left rear control

#### Scenario: Mode that repeats a button

- **WHEN** a capture of a mode shows the rear button changing only another button's bit
- **THEN** the record for that mode maps no rear control

### Requirement: Battery Level Comes From the Pad

OJD SHALL report a battery level for a mode only when the pad sends a level that changes with its charge.

#### Scenario: Constant battery byte

- **WHEN** a mode's battery field reads the same value at every charge level
- **THEN** `ojd controller show` reports no battery level for that mode

### Requirement: Each Mode's Status Rests on a Capture

`docs/testing/8bitdo-ultimate-2c.md` SHALL state for each identity of the Ultimate 2C Wireless whether it is verified, and MUST name the capture behind each verified row.

#### Scenario: Mode with no capture

- **WHEN** no capture exists for an identity
- **THEN** its row reads "Unverified" and names what is missing

### Requirement: 8BitDo Wired Xbox Pads Deliver Input

OJD SHALL deliver input from the 8BitDo Ultimate C Wired for Xbox (`2DC8:2027`) and the Ultimate Mini Wired for Xbox (`2DC8:2019`), which send no GIP announce packet.

#### Scenario: Pad that sends no announce packet

- **WHEN** a GIP pad sends input packets and no announce packet
- **THEN** OJD completes the session start and publishes the input

### Requirement: Input Health Reflects Received Input

OJD SHALL report a controller's input as healthy only after it has received an input report in the session.

#### Scenario: Session with no input

- **WHEN** a session is open and no input report has arrived
- **THEN** the controller detail and `ojd controller show` report that no input has arrived
- **AND** neither reports the input as healthy
