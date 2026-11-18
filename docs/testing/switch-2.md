# Test Switch 2 Controllers

Switch 2 Pro Controller 0x057e:0x2069; Joy-Con 2 0x2066 (right), 0x2067 (left); NSO GameCube 0x2073. `NintendoSwitch2` selects `Switch2Driver`; `layout` (`JoyConLeft`, `JoyConRight`, `GameCube`) picks the layout. USB follows SDL `SDL_hidapi_switch2.c`; Bluetooth LE follows [ndeadly's switch2_controller_research][1] and [joycon2cpp][2]. No controller is hardware-verified.

## Driver Behavior

- Opens vendor bulk interface 1 (OUT 0x02, IN 0x82) beside HID interface 0.
- Reads stick calibration from flash (a marked user calibration replaces the factory one), then sends SDL's init sequence.
- Decodes 64-byte HID report 0x05: buttons, D-pad, sticks, GameCube analog triggers.
- Sets player LEDs by bulk.
- Rumble: HD on Pro Controller and Joy-Con 2, PWM on GameCube; resent every 12 ms, two stop packets at stop.
- A single Joy-Con 2 uses its half of the layout, unrotated.
- Two Joy-Con 2 pair as one controller via the Profiles pair sheet, like first-generation Joy-Con.
- No motion.

## Bluetooth LE

macOS has no Bluetooth HID driver for them (GATT only). `Switch2BluetoothLECentral` scans while OJD runs and connects to a controller advertising Nintendo company ID 0x0553, VID 0x057e, and one of the four PIDs. `Switch2BluetoothLEHub` presents it to `DeviceManager` as a HID connection with the same PID, so the USB driver serves it:

- Input characteristic: report 0x05 without its ID byte; the hub prepends 0x05.
- Commands go to the command characteristic, replies come as notifications on the reply characteristic. Transport byte 0x01 (USB: 0x00).
- Rumble: model's vibration characteristic, 42-byte USB rumble report with byte 0 = 0x00.

Limits:

- OJD does not pair or bond (pairing disconnects the controller). Press sync on each connect.
- macOS asks for Bluetooth access at first start.
- Not verified: report rate, connection interval, MTU. A reply later than 500 ms fails the command.
- `controller disconnect` does not work.

[1]: https://github.com/ndeadly/switch2_controller_research
[2]: https://github.com/TheFrano/joycon2cpp

Not verified: right Joy-Con 2 reads calibration from the primary flash slot, as SDL does.

## Checks

1. Run `ioreg -r -c IOUSBHostInterface -l -w0`. Paste each `057e` entry with `bInterfaceNumber`, `bInterfaceClass`, endpoints.
2. Monitor, pressing each button once (other PIDs: 0x2066, 0x2067, 0x2073):

   ```bash
   swift run OpenJoystickDriverHIDTool --monitor --vid 0x057e --pid 0x2069 --seconds 30
   ```

3. In OJD, **Controllers**, select it, click **Open Input Test**. Check buttons, sticks, GameCube triggers move; centered stick reads center.
4. Check the player LED shows the assigned slot.
5. Rumble from Input Test: check it starts and stops.
6. Paste OJD log lines naming the controller, including `USB command` errors.
7. Unplug, press sync, allow Bluetooth. Repeat 3 to 6 over Bluetooth; note time to appear.
