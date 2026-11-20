# ZD O+ Excellence

The ZD O+ Excellence picks its USB mode at every plug-in. It first appears as a Switch Pro Controller: `057E:2009` "Pro Controller", bcdDevice `0x0020`, light red. If nothing greets it as a Switch for about a second, it re-enumerates as `11C0:5505` "Xbox 360 for Windows Controller", light blue. Start + Back only toggles XInput and DInput inside PC mode.

## What OJD Does

- `057E:2009` at bcdDevice `0x0020` matches the `zd-o-plus` mode of the bundled `057e-2009` patch. The mode states `server: OJD` and `idle: AwaitsReenumeration`. OJD seizes the HID device so macOS doesn't greet it, and sends it nothing. The Controllers page shows the reason until the pad leaves.
- `11C0:5505` has a bundled record on `XboxXUSB` `Wired`: interface 255/93/1, input endpoint `0x81`.
- Other `057E:2009` pads keep `NintendoSwitch1`. The Thunderobot G50S (bcdDevice `0x0200`) and the GameSir Cyclone 2 dongle (`0x0116`) need the Switch handshake.
- Over Bluetooth the pad is `045E:02E0` and needs a patch with `server: OJD`.

## What the Owner Saw

The owner ran 0.6.0-alpha.1 on macOS 27.2 with a user patch that has the same mode without `idle`. The log shows OJD bind `057E:2009` with `HIDDescriptor`, which sends nothing. About a second later the device disconnects and returns as `11C0:5505`. OJD bound it as `XboxXUSB:Wired` through its interface signature. Every control and rumble worked.

The owner's alpha.1 patch migrates with `ojd migrate`, and every key is kept. It still merges over the bundled mode, so it can stay installed or be removed.

## Not Yet Checked

These need the controller:

- With no user patch, a replug stays blue (`11C0:5505`).
- The bundled `11C0:5505` record gives every control and rumble.
- The Controllers page shows "This controller changes mode when nothing answers it." for about a second, then the Xbox pad.

To check, remove `~/Library/Application Support/OpenJoystickDriver/Controllers/057e-2009.patch.*`, then unplug and plug the pad in. Run `ojd status` and `ojd controller show 11C0:5505`. Send the output and the light color.
