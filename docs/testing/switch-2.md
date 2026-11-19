# Test Switch 2 Controllers

| Controller | Product ID (vendor 0x057e) |
| --- | --- |
| Switch 2 Pro Controller | 0x2069 |
| Joy-Con 2, right | 0x2066 |
| Joy-Con 2, left | 0x2067 |
| NSO GameCube controller | 0x2073 |

The `NintendoSwitch2` family picks `Switch2Driver`, and `layout` (`JoyConLeft`, `JoyConRight`, `GameCube`) picks the button layout. The USB side follows SDL's `SDL_hidapi_switch2.c`. The Bluetooth LE side follows [ndeadly's switch2_controller_research][1] and [joycon2cpp][2]. None of these controllers is confirmed on hardware yet.

## What the Driver Does

- Opens the vendor bulk interface 1 (OUT 0x02, IN 0x82) next to HID interface 0.
- Reads stick calibration from the controller's memory (a saved user calibration wins over the factory one), then sends SDL's startup steps.
- Reads the 64-byte HID report 0x05: buttons, D-pad, sticks, and the GameCube analog triggers.
- Sets the player lights over the bulk interface.
- Rumble: HD rumble on the Pro Controller and Joy-Con 2, PWM on the GameCube controller. OJD resends it every 12 ms and sends two stop packets to stop.
- A single Joy-Con 2 uses its half of the layout, held upright.
- Two Joy-Con 2 pair into one controller with the pair sheet in Profiles, the same as the first Joy-Con.
- No motion.

## Bluetooth LE

macOS has no Bluetooth HID driver for these controllers; it only offers GATT, the low-level Bluetooth LE data channel. So OJD does the work itself:

1. `Switch2BluetoothLECentral` scans while OJD runs and connects to a controller that advertises Nintendo company ID 0x0553, VID 0x057e, and one of the four product IDs.
2. `Switch2BluetoothLEHub` hands it to `DeviceManager` as a HID connection with the same product ID, so the USB driver serves it.

How the Bluetooth parts map to USB:

- Input: report 0x05 without its ID byte. The hub adds 0x05 back in front.
- Commands go to the command characteristic, and replies come back as notifications on the reply characteristic. The transport byte is 0x01 (on USB it's 0x00).
- Rumble: the model's vibration characteristic gets the 42-byte USB rumble report with byte 0 set to 0x00.

Limits:

- OJD doesn't pair or bond, because pairing disconnects the controller. Press sync each time you connect.
- macOS asks for Bluetooth access the first time OJD starts.
- Not checked: report rate, connection interval, MTU. A reply that takes longer than 500 ms fails the command.
- `controller disconnect` doesn't work.

[1]: https://github.com/ndeadly/switch2_controller_research
[2]: https://github.com/TheFrano/joycon2cpp

Not checked: whether the right Joy-Con 2 reads calibration from the main memory slot, the way SDL does.

## Checks

1. Run `ioreg -r -c IOUSBHostInterface -l -w0`. Paste each `057e` entry with its `bInterfaceNumber`, `bInterfaceClass`, and endpoints.
2. Watch the input while you press each button once (other product IDs: 0x2066, 0x2067, 0x2073):

   ```bash
   swift run OpenJoystickDriverHIDTool --monitor --vid 0x057e --pid 0x2069 --seconds 30
   ```

3. In OJD's **Controllers**, select it and click **Open Input Test**. Check that buttons, sticks, and GameCube triggers move, and a resting stick reads center.
4. Check that the player light shows the slot OJD gave it.
5. Start rumble from Input Test. Check that it starts and stops.
6. Paste OJD's log lines that name the controller, including any `USB command` errors.
7. Unplug it, press sync, and allow Bluetooth. Repeat steps 3 to 6 over Bluetooth, and write down how long it took to show up.
