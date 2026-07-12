# Physical output evidence

OJD reports each output capability with its evidence level.

- `hardwareVerified` means the record contains accepted hardware evidence and the parser implements the output.
- `sourceBacked` means production code follows a named protocol source, but matching hardware has not passed the project test.
- `unavailable` means the parser exposes no implementation.

See the evidence in `physical-output list`, `physical-output list --json`, `status`, Input Test, and redacted support reports. Generate device-specific checks with `physical-output plan <vid> <pid>`.

## Implemented output

### GIP

Left and right main motors plus left and right trigger motors.

### Xbox 360

Left and right main motors plus player indicator.

### DualShock 4

Two motors and programmable RGB lightbar over USB or Bluetooth.

### DualSense

Two compatible-rumble motors, five player LEDs, and RGB lightbar over USB or Bluetooth. Bluetooth reports use sequence framing and CRC32 seed `0xA2`.

### DualShock 3

Analog large motor, binary small motor, and four player LEDs in the fixed Sixaxis output report. Structured output lists the small motor under `binaryRumbleMotors`.

### Switch Pro

Independent HD-rumble actuators at the Linux default 160/320 Hz frequencies and four player LEDs. Packets use a wrapping four-bit sequence. Startup pacing is 20 ms over USB and 60 ms over Bluetooth; physical output is limited to one packet per 50 ms.

### Steam Controller

Independent left and right trackpad haptics through feature command `0x8F`, plus home-button brightness through setting 45. Haptic gain maps to -24 through +6 dB. Long effects are split into bounded pulses. Wireless output stops when no logical controller is connected.

Xbox Adaptive Joystick and Generic HID expose no physical output. Add source-backed report construction and tests before advertising output for either parser.
