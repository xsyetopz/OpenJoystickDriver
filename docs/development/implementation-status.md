# Implementation Status

OpenJoystickDriver 0.6 runs a persistent application runtime. The signed app host owns controller processing, virtual output, login registration, permission state, and the authenticated RPC endpoint. Sources contain no helper daemon, LaunchAgent plist, or alternate RPC route.

The authenticated Unix socket is the typed GUI and CLI boundary. The installed-CLI forwarder blocks unsigned or stale executables from impersonating the signed client.

Endpoint, schemas, and stored documents use `apiVersion` `openjoystickdriver/v1alpha3`. Others are rejected; `ojd migrate` converts older stored documents. `Scripts/SDK/reference_client.py` speaks only that version.

Sessions separate physical connection from reversible OJD suspension. A failed virtual HID profile replacement keeps the live profile.

DualShock 4 Bluetooth reports need a valid CRC. Stale report progress retires non-neutral OJD output after one second. Recovery: a fresh neutral report.

GameSir G7 SE sends the GIP LED-on command on every USB open and resume. Diagnostics keep the latest result.

Another profile library schema version returns a typed unsupported-version error; an empty unsupported library keeps its bytes and unknown fields.

CLI and app runtime report Input Monitoring and Accessibility states for `OpenJoystickDriver.app`. Input Monitoring gates physical controller reads; Accessibility gates virtual-HID publication. OJD never resets TCC.

Controller records are generated; shared protocol behavior stays in code. Output dispatch is concurrent across devices, ordered per virtual device.

Codec tests do not show signed consumer binding or hardware delivery ([wire protocols](wire-protocols.md)).

`OpenJoystickDriverUSB` exposes one controller-neutral raw USB API; accessible vendor-specific interfaces use app-side IOUSBHost.

The SwifterKit adapter talks to the DriverKit extension's XboxUSB personality only for an observed DEXT-owned service or a model under OJD's restricted production entitlement. The extension `com.openjoystickdriver.XboxUSBDevice` has that one personality. The app publishes virtual gamepads through `IOHIDUserDevice`.

SwifterKit generates its native project at build time. Validated locally: generation, unsigned native builds. Needs a provisioned Mac and evidence: signed activation, macOS approval, physical USB delivery. Controllers with incomplete hardware evidence: [experimental controllers](experimental-controllers.md).

## Platform Boundaries

Every supported macOS (12+): physical HID uses IOHID, consumer virtual output uses IOHIDUserDevice, raw USB uses IOUSBHost and USBDriverKit. `OpenJoystickDriverUSB` hides USB host transport from parsers and app callers. No libusb fallback.

## Known Issues

Intermittent app crash on macOS 27.0 (26A428). The main thread traps with `CFRelease() called with NULL` while IOHIDManager drops a removed device: `__IOHIDManagerDeviceRemoved` releases the device, `IODestroyPlugInInterface` destroys its IOHIDDeviceClass, `CFPlugInRemoveInstanceForFactory` deallocates the plug-in bundle. No OJD frame is on the stack; no other thread did HID work. Manager: OJD's `HIDDeviceStream`, main run loop.

Before the second crash, every controller behind one USB 2 hub disconnected at once. Reproduction needs a whole-hub disconnect. On macOS 27, Sony pads and the GameSir G7 SE load Apple's `GCHIDLib`, not `IOHIDLib`. Suspected trigger: the last `GCHIDLib`-backed device leaving the process. Not reproduced: per-device USB resets (singly or together), a standalone IOHIDManager program. Relaunch restores controllers.
