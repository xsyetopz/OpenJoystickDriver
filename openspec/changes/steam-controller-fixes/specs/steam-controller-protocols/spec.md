## ADDED Requirements

### Requirement: Triton grip touch is an input

The 2026 Steam Controller SHALL report grip capacitive touch as the controls `RightGripTouch` and `LeftGripTouch`. The vocabulary, crosswalk and schema SHALL list both ids, and no earlier name for them SHALL exist.

#### Scenario: Right grip touched

- **WHEN** a state report has bit 28 of the button word set
- **THEN** `RightGripTouch` is pressed and no other control changes

#### Scenario: Left grip released

- **WHEN** a state report has bit 29 of the button word clear after it was set
- **THEN** `LeftGripTouch` is released

#### Scenario: Unknown id

- **WHEN** a profile names a grip control with another spelling
- **THEN** the profile is rejected like any invalid control id

### Requirement: Pad haptic pulse is a named output

A controller of the 2026 Steam Controller family SHALL accept a pad haptic pulse command that names the pad, the on time, the off time and the repeat count, and SHALL advertise a matching output capability. Another family SHALL reject the command as unsupported.

#### Scenario: Pulse on the Triton

- **WHEN** a pad haptic pulse command is sent to a connected Triton controller
- **THEN** one pulse output report with that pad, on time, off time and repeat count is written

#### Scenario: Pulse on another family

- **WHEN** the command is sent to a controller of another family
- **THEN** it fails with an unsupported-capability error and nothing is written

### Requirement: Rumble keeps the reference report

The Triton rumble report SHALL carry the motor speeds with type, intensity and both gains at zero until hardware shows a reason to change them.

#### Scenario: Both motors

- **WHEN** low-frequency and high-frequency rumble are set
- **THEN** a 10-byte report with id `0x80`, the speeds in the left and right speed fields and zero in the other fields is written

### Requirement: 2015 activation resets the settings first

Activating a 2015 Steam Controller over USB or Bluetooth LE SHALL clear digital mappings, load default settings, and then write the trackpad modes, the smooth absolute mouse setting at zero and the IMU mode.

#### Scenario: USB activation

- **WHEN** a 2015 controller is activated over USB
- **THEN** the writes go out in the order clear mappings, load defaults, settings

#### Scenario: Deactivation

- **WHEN** the controller is deactivated
- **THEN** the writes restore default mappings and default settings so the OS sees the mouse and keys again

### Requirement: Dongle slots are interfaces 2 to 5

For the 2026 dongles `28de:1304` and `28de:1305`, only HID interfaces 2 to 5 SHALL be controller slots; any other interface of the dongle is not a controller.

#### Scenario: Keyboard interface

- **WHEN** interface 0 of a `1305` dongle is observed
- **THEN** it is not a controller role

### Requirement: Optional lizard settings are adopted only with evidence

The Triton description SHALL NOT send `CLEAR_DIGITAL_MAPPINGS` or turn the firmware watchdog off unless the same change also restores the controller when OJD stops.

#### Scenario: Watchdog off without restore

- **WHEN** a description turns the watchdog off and has no deactivation that restores defaults
- **THEN** the description is rejected by review and by its test
