## ADDED Requirements

### Requirement: REQ-48 Gyro-Stick Template

`ojd profile create NAME --controller VID:PID --template gyro-stick [--stick left|right] [--activation CONTROL]` and the New profile sheet MUST create a profile with `gyroOutput` mode `LeftStick` or `RightStick` (default `RightStick`), activation `WhileHeld` on the chosen control (`Always` when none), and a virtual gamepad that includes unmapped controls. The command MUST fail with a named error when the model has no motion sensor, and MUST NOT alter another profile.

#### Scenario: Create the Template

- **WHEN** the user runs `ojd profile create Gyro --controller 054C:0CE6 --template gyro-stick --activation button:leftShoulder` for a controller with motion
- **THEN** the profile validates, has `gyroOutput` mode `RightStick` with `WhileHeld` on the left shoulder, and a virtual gamepad is enabled

#### Scenario: No Motion Sensor

- **WHEN** the model has no motion sensor
- **THEN** the command fails with a message that names the model and says it has no motion sensor

### Requirement: REQ-49 Gyro-Stick Hardware Check

The repository MUST hold `docs/testing/gyro-stick.md`: numbered steps to create the template, tilt the controller and read the virtual stick axes, and the fields to record (controller, VID:PID, connection, OJD version, macOS version, whether the stick moved). The wiki MUST say `Not checked` for hardware behavior until an operator ran it.

#### Scenario: Check Document Exists

- **WHEN** a maintainer opens `docs/testing/gyro-stick.md`
- **THEN** it lists the steps and the fields to record, and each step names the app control or command to use
