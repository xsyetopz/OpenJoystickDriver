## ADDED Requirements

### Requirement: Wii Remote family and records

OpenJoystickDriver SHALL drive the Wii Remote through the protocol family `NintendoWii`, with bundled records for `057E:0306` and `057E:0330`. A record SHALL match a device only when its product string is `Nintendo RVL-CNT-01` (`0306`) or `Nintendo RVL-CNT-01-TR` (`0330`).

#### Scenario: Remote pairs and connects

- **WHEN** a Wii Remote paired through macOS Bluetooth connects with product string `Nintendo RVL-CNT-01`
- **THEN** the controller list shows it as a Wii Remote served by `NintendoWii`

#### Scenario: Shared product ID, other device

- **WHEN** a device with `057E:0306` reports the product string `Nintendo RVL-WBC-01`
- **THEN** no mode of the Wii Remote records matches and the device is reported as unsupported

### Requirement: Report modes

The driver SHALL decode input report modes `0x30` to `0x3F`, choose the smallest mode that carries the enabled features, and set it with output report `0x12`.

#### Scenario: Buttons only

- **WHEN** only the core buttons are enabled
- **THEN** the driver sets mode `0x30` and decodes the two button bytes of each report

#### Scenario: Accelerometer and extension

- **WHEN** the accelerometer is enabled and a Nunchuk is attached
- **THEN** the driver sets a mode that carries the core buttons, the accelerometer and the extension bytes, and sets the continuous reporting bit

### Requirement: Report mode survives status reports

The driver SHALL send the chosen report mode again after every status report (`0x20`), because the remote resets its mode to `0x30` when it sends one.

#### Scenario: Status after extension change

- **WHEN** a status report arrives while the chosen mode is `0x35`
- **THEN** the driver sends `0x12` with mode `0x35` once

### Requirement: Core buttons and accelerometer

The driver SHALL map the remote's buttons to canonical controls and decode the 10-bit accelerometer from the three high bytes and the two low bits carried in the button bytes.

#### Scenario: Button press

- **WHEN** a report has the A button bit set
- **THEN** the frame has `South` pressed and no other control

#### Scenario: Accelerometer value

- **WHEN** a report carries X high byte `0x84` and low bits `0b10`
- **THEN** the raw X value is 0x212

### Requirement: Player indicator and rumble

The driver SHALL set the four player-indicator LEDs with output report `0x11` and the rumble motor with the rumble bit. Every output report the driver sends SHALL carry the current rumble state in bit 0 of its first data byte.

#### Scenario: Rumble on, then LEDs

- **WHEN** rumble is on and the driver sets the player indicator to slot 2
- **THEN** the `0x11` report has LED 2 set and the rumble bit set

#### Scenario: Memory write while rumbling

- **WHEN** the driver sends a memory write while rumble is on
- **THEN** the write report has the rumble bit set

### Requirement: Status and battery

The driver SHALL request status on connect and report the battery level and low-battery flag from status reports.

#### Scenario: Battery value

- **WHEN** a status report has battery byte `0x64`
- **THEN** the controller shows 50 percent

### Requirement: Extension detection

The driver SHALL detect an attached extension from the status flags, run the handshake (write `0x55` to `0xA400F0`, write `0x00` to `0xA400FB`, read six bytes at `0xA400FA`), and identify Nunchuk, Classic Controller, Classic Controller Pro and Motion Plus from the ID. An unrecognized ID SHALL be reported with its six bytes.

#### Scenario: Nunchuk plugged in

- **WHEN** a status report shows an extension and the ID read is the Nunchuk ID
- **THEN** the controller reports a Nunchuk and decodes its stick, `Z`, `C` and accelerometer

#### Scenario: Unknown extension

- **WHEN** the ID read matches no known extension
- **THEN** the controller reports an unknown extension with the ID in hex and decodes only the core buttons and the accelerometer

### Requirement: Extension hot-plug

The driver SHALL start the handshake when a status report shows an extension that was not attached, and SHALL return the extension's controls to neutral when a status report shows it removed.

#### Scenario: Nunchuk unplugged while the stick is held

- **WHEN** a status report shows no extension while `LeftStickX` is 1.0
- **THEN** the next frame has `LeftStickX` 0

### Requirement: Handshake failure is reported

A handshake or setup step whose acknowledgement carries an error code, or whose reply does not arrive within its timeout, SHALL end the sequence with the named failure `ExtensionHandshakeFailed`, which has a localized message and an error code. The driver SHALL NOT retry silently.

#### Scenario: Read timeout

- **WHEN** the ID read gets no reply within the timeout
- **THEN** the controller shows the failure and the step that timed out, and sends no further handshake write

### Requirement: Nunchuk and Classic Controller

The driver SHALL decode the Nunchuk (stick, `C`, `Z`, accelerometer) and the Classic Controller and Classic Controller Pro (two sticks, analog triggers, digital shoulder buttons, face buttons, D-pad, Home, Plus, Minus) to canonical controls, using the calibration read from the extension.

#### Scenario: Classic face buttons

- **WHEN** a Classic Controller report has `a` pressed
- **THEN** the frame has `East` pressed

#### Scenario: Nunchuk stick

- **WHEN** a Nunchuk report holds the stick at its calibrated maximum right
- **THEN** `LeftStickX` is 1.0

### Requirement: Motion Plus

The driver SHALL activate Motion Plus (write `0x55` to `0xA600F0`, then the mode to `0xA600FE`), decode its three gyro axes with the slow/fast scale flags, support Nunchuk and Classic passthrough, and expose the gyroscope through the controller's motion data. It SHALL measure a rest offset and show whether the offset is ready.

#### Scenario: Fast flag

- **WHEN** a Motion Plus sample has the fast flag set for yaw
- **THEN** the yaw rate uses the fast scale

#### Scenario: Passthrough frame

- **WHEN** Motion Plus is active with Nunchuk passthrough and frames alternate between gyro and Nunchuk data
- **THEN** each frame updates only its own controls and the other values hold

### Requirement: IR camera setup

The driver SHALL enable the IR camera, with the seven-step register sequence and at least 50 ms between consecutive writes, only while the active profile of the controller binds `PointerX` or `PointerY` as a source, and SHALL reject a configured interval below 50 ms. A source counts in a binding, a chord, a sequence, a layer activator or layer mapping, and the gyro activation or trackball source. While no profile binds the pointer, the driver SHALL use the report mode without IR and SHALL write no IR step. When the binding goes away, the driver SHALL disable the camera (reports `0x13` and `0x1A` with bit 2 cleared), return to the report mode without IR and return the pointer to neutral. After a reconnect, and when a profile that binds the pointer becomes active, the driver SHALL run the setup again.

#### Scenario: No pointer binding

- **WHEN** the active profile binds no pointer axis
- **THEN** the report mode is `0x31` and the driver writes no IR step

#### Scenario: Profile binds the pointer

- **WHEN** a profile that binds `PointerX` becomes active on a connected remote
- **THEN** the driver runs the IR setup and sets the IR report mode

#### Scenario: Binding removed

- **WHEN** the active profile stops binding the pointer
- **THEN** the driver writes `0x13` and `0x1A` with bit 2 cleared, sets the report mode without IR, and `PointerX`, `PointerY` and `PointerTracking` return to neutral

#### Scenario: Reconnect

- **WHEN** the remote reconnects while the active profile binds the pointer
- **THEN** the driver runs the IR setup again after the first status report

#### Scenario: Spacing

- **WHEN** the driver runs the IR setup
- **THEN** no two writes are less than 50 ms apart

#### Scenario: Interval too small

- **WHEN** a patch sets `irWriteIntervalMs` to 20
- **THEN** the record is rejected

### Requirement: IR points and pointer

With the IR camera on, the driver SHALL expose up to four IR points as touch contacts. When two or more points are visible it SHALL set `PointerTracking` and compute `PointerX` and `PointerY` from the midpoint of the two brightest points, mirrored and roll-compensated; otherwise `PointerTracking` SHALL be false and the pointer values SHALL hold.

#### Scenario: Two points

- **WHEN** two points are visible at the horizontal center of the camera
- **THEN** `PointerTracking` is true and `PointerX` is 0

#### Scenario: Points lost

- **WHEN** fewer than two points are visible after tracking
- **THEN** `PointerTracking` is false and `PointerX` and `PointerY` keep their last values

### Requirement: Pointer control ids

The vocabulary SHALL include `PointerX` and `PointerY` (axes from -1 to 1, Y positive down) and `PointerTracking` (digital). The virtual personas SHALL NOT publish them.

#### Scenario: Pointer to mouse

- **WHEN** a profile maps `PointerX` and `PointerY` to `MouseMovement`
- **THEN** the profile loads, and moving the remote moves the cursor

#### Scenario: Pointer to position

- **WHEN** a profile maps `PointerX` to `PointerPosition` on axis X
- **THEN** the cursor's X coordinate follows the pointer from the left edge (-1) to the right edge (1) of the main display and the Y coordinate keeps its value

#### Scenario: Position needs an axis

- **WHEN** a profile maps a button, chord, sequence or macro step to `PointerPosition`
- **THEN** the profile is rejected

#### Scenario: Persona

- **WHEN** a remote with the IR camera on is served through `SDLCompatible`
- **THEN** the persona's report has no pointer data

### Requirement: Speaker output

The driver SHALL expose the speaker as an audio output: it SHALL set the speaker up with the register sequence, encode audio as 4-bit Yamaha ADPCM, send it in `0x18` reports at the speaker's rate, and mute and disable the speaker when playback ends. A command to a controller without the speaker capability SHALL fail with the named error `SpeakerUnavailable`.

#### Scenario: Play a clip

- **WHEN** `ojd controller speaker play` is given a mono PCM WAV file
- **THEN** the driver sets the speaker up, streams the encoded data, and mutes and disables the speaker at the end

#### Scenario: Unsupported file

- **WHEN** the file is not PCM WAV
- **THEN** the command refuses it with a named error and sends nothing

#### Scenario: Stop

- **WHEN** `ojd controller speaker stop` runs during playback
- **THEN** the driver stops sending data and mutes and disables the speaker

### Requirement: No power-off

OpenJoystickDriver SHALL NOT offer a Wii Remote power-off. The wiki SHALL state that the user disconnects the remote in macOS Bluetooth.

#### Scenario: Documentation

- **WHEN** a user reads the Wii Remote wiki page
- **THEN** it says how to disconnect the remote and that OJD has no power-off command

### Requirement: Session end on disconnect

When the remote disconnects, the driver SHALL end the session with neutral input, and on reconnect SHALL run the startup again. It SHALL NOT restore report mode, IR or speaker state from memory.

#### Scenario: Reconnect

- **WHEN** a remote disconnects while IR is on and reconnects
- **THEN** the driver sets the report mode again and runs the IR setup again before IR points appear
