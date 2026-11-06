## ADDED Requirements

### Requirement: Input reports are identified from captures

The Switch 2 driver SHALL decode the input report of each transport from the report ID and layout that recorded hardware captures show. A report whose ID the driver does not decode SHALL be ignored and SHALL NOT change the controller state.

#### Scenario: Known state report

- **WHEN** a recorded state report of a Pro Controller 2 arrives
- **THEN** each button and stick in the capture's action decodes to the control that the action names

#### Scenario: Other report ID

- **WHEN** a report with an ID that the driver does not decode arrives
- **THEN** the state stays unchanged and no event is produced

#### Scenario: Short report

- **WHEN** a state report is shorter than the layout needs
- **THEN** it is ignored

### Requirement: Bluetooth LE buttons match the capture

Each button and stick over Bluetooth LE SHALL decode from the bit and byte that a Bluetooth LE capture shows. The driver SHALL use a separate Bluetooth LE table only for a control whose bit differs from the USB table.

#### Scenario: Same bit on both links

- **WHEN** a button has the same bit on USB and on Bluetooth LE
- **THEN** both links decode it from the shared table

#### Scenario: Different bit

- **WHEN** a button has a different bit on Bluetooth LE
- **THEN** the Bluetooth LE link decodes it from its own table entry

### Requirement: Motion samples come from the IMU

A Switch 2 controller SHALL report accelerometer and gyroscope samples with the controller's flash bias applied and with a sample time derived from the sensor timestamp. A report whose sensor timestamp is zero SHALL carry no sample.

#### Scenario: Controller at rest

- **WHEN** a still controller's report arrives after the bias was read
- **THEN** the gyroscope sample is near zero and the accelerometer magnitude is near one g

#### Scenario: No timestamp

- **WHEN** a report has a zero sensor timestamp
- **THEN** no motion sample is produced

### Requirement: Rumble cadence is description data

The interval at which the driver resends the rumble report SHALL be a value in the family description, and a trailing number of stop reports SHALL follow the end of a rumble.

#### Scenario: Rumble running

- **WHEN** a motor is on
- **THEN** the rumble report is sent again at the described interval with a rolling sequence number

#### Scenario: Rumble ends

- **WHEN** both motors reach zero
- **THEN** the described number of stop reports follows and then the resends end

### Requirement: Records give each product its layout

The records of `057E:2066`, `2067`, `2069` and `2073` SHALL bind the Switch 2 family with the layouts right Joy-Con (`2066`), left Joy-Con (`2067`) and GameCube controller (`2073`); the `2069` record sets no `layout` and uses the family default, the Pro Controller layout.

#### Scenario: Left Joy-Con

- **WHEN** a controller with ID `057E:2067` is detected
- **THEN** it is served with the left Joy-Con layout
