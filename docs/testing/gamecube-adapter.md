# Wii U GameCube Adapter

The Nintendo Wii U GameCube adapter is `057E:0337`. It has four controller ports and two USB cables. The black cable carries data. The gray cable powers rumble.

## What OJD Does

- The bundled record `057e-0337` uses the `NintendoGameCubeAdapter` protocol.
- OJD sends the start report `0x13` once, from port 1. The adapter then sends report `0x21`, 37 bytes. Each port has nine bytes at `1 + 9 * port`: status, two button bytes, main stick X and Y, C stick X and Y, L and R. Source: Dolphin `Source/Core/InputCommon/GCAdapter.cpp` lines 753 and 891.
- OJD shows one controller per port. Each has its own port key, so a profile can target one port, and each port gets its own player slot. A port's controller is connected while a pad is in the port. Output waits until then.
- Buttons follow SDL's positional layout: A is South, B is West, X is East, Y is North, Z is the right shoulder. Pressing L or R all the way in is the digital trigger click. The analog L and R values are the triggers.
- Each stick starts with a range of 88 around center, and each trigger starts at 40. A range widens to the largest value seen, and resets when the pad leaves the port.
- Rumble works on a wired pad when the gray cable is plugged in. The status byte has bit `0x04` set then. One report, `0x11` plus one byte per port, sets all four motors. OJD resends it every 500 ms while a motor runs. A wireless pad (status `0x20`) gets no rumble, and OJD reports rumble as unsupported for it. Dolphin skips wireless pads the same way (line 1039).
- Unplugging the adapter removes all four controllers.

## What OJD Doesn't Do

- OJD doesn't change the USB polling interval. The Linux module `gcadapter-oc-kmod` patches `bInterval` from 8 to 1 to poll faster (`gcadapter-oc.c` lines 16-17). The macOS driver GCAdapterDriver (MIT) also asks for a faster interval. OJD reads reports at the interval the adapter states.
- OJD and GCAdapterDriver can't both own the adapter. Remove GCAdapterDriver before testing OJD.
- `ojd controller suspend` on one port closes the HID handle that all four ports share, so the other three stop too.

## Not Yet Checked

No one has tested OJD with this adapter yet. These checks need the hardware:

- macOS shows the adapter as a HID device, and OJD binds it with no user files.
- All four ports give input. Each pad's buttons, sticks and triggers move only its own controller.
- Rumble works on each port with the gray cable plugged in, and two ports can rumble at once.
- Replugging a pad into a port brings back the same controller.

To check, plug in both cables and connect pads to two or more ports. Run `ojd status` and `ojd controller list`. The adapter has four controllers, one per port, so `ojd` refuses `057E:0337` and lists them. Use each port's port key with `ojd controller show` and `ojd controller rumble`, and try Input Test on each port. Send the output and say which ports had pads.
