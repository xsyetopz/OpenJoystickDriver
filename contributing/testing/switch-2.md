# Test Switch 2 Controllers

The Switch 2 Pro Controller is `0x057e:0x2069`. The Joy-Con 2 are `0x2066` (right) and `0x2067` (left). The NSO GameCube controller is `0x2073`. The `switch-2` quirk selects `Switch2Driver`, and the `joy-con-left`, `joy-con-right` or `gamecube` quirk selects the layout. The USB driver follows SDL `SDL_hidapi_switch2.c`. The Bluetooth LE transport follows [ndeadly's switch2_controller_research][1] and [joycon2cpp][2]. None of these controllers is hardware-verified.

## What the Driver Does

- Opens the vendor bulk interface 1 (OUT `0x02`, IN `0x82`) next to HID interface 0.
- Reads the stick calibration from flash, then sends SDL's init sequence. A user calibration replaces the factory calibration when its marker is present.
- Decodes the 64-byte HID report `0x05`: buttons, D-pad, sticks and, on the GameCube controller, analog triggers.
- Sets the player LEDs through the bulk interface.
- Sends HD rumble on the Pro Controller and Joy-Con 2, and PWM rumble on the GameCube controller. The driver resends rumble every 12 ms and sends two stop packets after a stop.
- A single Joy-Con 2 uses its half of the full layout. OJD does not rotate it sideways.

- Two Joy-Con 2 can be paired as one controller from the Profiles pair sheet, the same way as the first-generation Joy-Con.

Motion is not supported yet.

## Bluetooth LE

macOS has no HID driver for these controllers over Bluetooth. They speak GATT only. `Switch2BluetoothLECentral` scans while OJD runs and connects to a controller whose advertisement carries Nintendo company ID `0x0553`, VID `0x057e`, and one of the four product IDs. `Switch2BluetoothLEHub` then presents the GATT link to `DeviceManager` as a HID connection with the same product ID, so the USB driver serves it:

- The input characteristic carries report `0x05` without its report ID byte. The hub prepends `0x05`.
- Commands go to the command characteristic, and replies come back as notifications on the reply characteristic. The driver marks each command with transport byte `0x01` instead of the USB `0x00`.
- Rumble goes to the model's vibration characteristic as the 42-byte USB rumble report with byte 0 set to `0x00`.

Limits:

- OJD does not pair or bond: a pairing attempt makes the controller disconnect. Press the sync button each time the controller connects.
- macOS asks for Bluetooth access the first time OJD starts.
- The report rate, connection interval and MTU are not verified. A command reply that does not arrive in 500 ms fails that command.
- `controller disconnect` does not work for these controllers.
- The scan runs for as long as OJD runs.

[1]: https://github.com/ndeadly/switch2_controller_research
[2]: https://github.com/TheFrano/joycon2cpp

The right Joy-Con 2 reads its calibration from the primary flash slot, as SDL does. This choice is not verified.

## Checks

1. Run `ioreg -r -c IOUSBHostInterface -l -w0` and paste every `057e` entry with its `bInterfaceNumber`, `bInterfaceClass` and endpoint addresses.
1. Run the HID monitor and press each button once:

   ```bash
   swift run OpenJoystickDriverHIDTool --monitor --vid 0x057e --pid 0x2069 --seconds 30
   ```

   Use `0x2066`, `0x2067` or `0x2073` for the other controllers.

1. Start OJD. Check in Controller Settings Live that every button, the sticks and, on the GameCube controller, the triggers move. Check that a centered stick reads center.
1. Check that the player LED shows the slot OJD assigned.
1. Run a rumble from Controller Settings. Check that it starts and that it stops at the end.
1. Paste the OJD log lines that name the controller, including any `USB command` errors.
1. Unplug the controller and press its sync button. Allow Bluetooth access when macOS asks. Repeat checks 3 to 6 over Bluetooth, and note how long the controller took to appear.
