# Test The GameSir K1 (Wired)

USB device `13623:4226` (`3537:1082` in hexadecimal), `GameSir-K1 Controller for Xbox` (K1 Kaleid), wired
USB-C. On macOS it enumerates as a HID gamepad (interface class 3), not GIP, and stays on Generic HID.

The descriptor matches the WR-007 layout: 15 sparse Xbox-style buttons, a hat, X/Y left stick, Z/Rz right
stick, and Simulation Brake/Accelerator analog triggers in 10-byte input report 5. The triggers are the other
way round from WR-007: Brake is the left trigger and Accelerator the right. Button 13 is Guide.

## Observed Reports

Captured on macOS 26 (Apple Silicon) with an IOHIDManager input-report callback, one control at a time:

- Right trigger: Accelerator 0-255 and button 10; left trigger: Brake 0-255 and button 9
- Left stick X/Y and right stick Z/Rz, 0-255 centred on 128
- A, B, X, Y: buttons 1, 2, 4, 5; LB, RB: 7, 8
- View, Menu, Guide: 11, 12, 13; left and right stick clicks: 14, 15
- D-pad: hat 0, 2, 4, 6 for up, right, down, left; 15 when released

Share was not captured.

## Live Input

The signing-free USB record probe does not exercise Generic HID element parsing. Use a maintainer-signed build.

Connect the controller and confirm the runtime selects Generic HID for `3537:1082`:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver \
  --headless controller list
```

Press each physical control. Confirm face buttons, bumpers, View, Menu, Guide, stick clicks, D-pad, both
sticks, and both analog triggers on the correct side. Enable Apple GameController identity and confirm a
GameController.framework consumer receives the virtual device.
