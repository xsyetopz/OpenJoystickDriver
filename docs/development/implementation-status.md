# Implementation Status

What OJD has built so far.

## One App Does Everything

OpenJoystickDriver 0.6 is one app that keeps running in the background. That signed app does all the work itself: it reads controllers, makes virtual gamepads, starts at login, tracks permissions, and runs the RPC endpoint other programs talk to. The source has no helper daemon, no LaunchAgent plist, and no second RPC road.

The app and the `ojd` command-line tool talk through a Unix socket that checks who is calling, like a door with an ID check. The installed command-line forwarder stops unsigned or out-of-date programs from pretending to be the signed client.

## Versions of Saved Files

The endpoint, the schemas, and saved documents use `apiVersion` `openjoystickdriver/v1alpha4`. OJD refuses any other version. `ojd migrate` upgrades older saved documents. `Scripts/SDK/reference_client.py` speaks only that version.

A profile library saved with a different schema version gets a clear unsupported-version error. An empty library in an unsupported version keeps its bytes and any fields OJD doesn't know.

## Controllers and Output

- A session keeps two things apart: whether the controller is plugged in, and whether OJD has paused it (a pause you can undo).
- If swapping a virtual HID profile fails, the profile in use stays.
- DualShock 4 Bluetooth reports need a valid CRC (a checksum).
- If reports stop arriving, OJD lets go of any held buttons or sticks after one second. A fresh report at rest brings things back.
- The GameSir G7 SE gets the GIP light-on command every time USB opens it or it wakes. Diagnostics keep the latest result.
- Controller records are generated. Behavior shared by a whole protocol stays in code.
- OJD sends output to different devices at the same time, and in order for each virtual device.
- Codec tests don't prove a signed app reads OJD's gamepad, or that real hardware gets the output ([wire protocols](wire-protocols.md)).

## Permissions

The command-line tool and the app report the Input Monitoring and Accessibility states for `OpenJoystickDriver.app`. OJD needs Input Monitoring to read real controllers, and Accessibility to publish virtual gamepads. OJD never resets TCC (the macOS privacy database).

## USB and the Driver Extension

`OpenJoystickDriverUSB` offers one raw USB API that fits any controller. Vendor-specific interfaces the app can reach use IOUSBHost inside the app.

The SwifterKit adapter talks to the DriverKit extension's XboxUSB personality only when the extension already owns the device, or for a model covered by OJD's restricted production entitlement. The extension `com.openjoystickdriver.XboxUSBDevice` has that one personality. The app publishes virtual gamepads through `IOHIDUserDevice`.

SwifterKit generates its native project at build time.

| Part | State |
| --- | --- |
| Project generation, unsigned native builds | Checked on a local Mac |
| Signed activation, macOS approval, real USB delivery | Needs a Mac with signing profiles, and results |

Controllers still missing hardware results are listed in [experimental controllers](experimental-controllers.md).

## What macOS Pieces OJD Uses

On every supported macOS (12 and later):

| Job | macOS piece |
| --- | --- |
| Read real HID controllers | IOHID |
| Publish virtual gamepads for games | IOHIDUserDevice |
| Raw USB | IOUSBHost and USBDriverKit |

`OpenJoystickDriverUSB` hides the USB details from the code that reads reports. There's no libusb backup.

## Known Issues

The app sometimes crashes on macOS 27.0 (26A428). The main thread stops with `CFRelease() called with NULL` while IOHIDManager drops a removed device: `__IOHIDManagerDeviceRemoved` releases the device, `IODestroyPlugInInterface` destroys its IOHIDDeviceClass, `CFPlugInRemoveInstanceForFactory` deallocates the plug-in bundle. No OJD frame is on the stack; no other thread did HID work. Manager: OJD's `HIDDeviceStream`, main run loop.

Before the second crash, every controller behind one USB 2 hub disconnected at once. Making it happen again needs the whole hub to disconnect. On macOS 27, Sony pads and the GameSir G7 SE load Apple's `GCHIDLib`, not `IOHIDLib`. The likely trigger is the last `GCHIDLib` device leaving the app. These didn't cause it: resetting USB devices one by one or all together, and a small separate IOHIDManager program. Relaunching the app brings the controllers back.

The workaround, not yet confirmed on the hardware that crashed: `HIDPlugInBundles` holds a `CFBundle` reference to each plug-in that a matched device's `IOCFPlugInTypes` names, from `HIDDeviceStream.handleDeviceAdded` until the process exits. `CFBundleCreate` returns the bundle `CFPlugInCreate` gives IOKit (`HIDPlugInBundlesTests`), so `CFPlugInRemoveInstanceForFactory` never releases its last reference.
