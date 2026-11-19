# Who Owns a USB Controller: macOS or OJD

When you plug in a USB controller, macOS and OJD might both want it, like two people reaching for the same cup. This page explains how OJD decides who gets it, and which road OJD then uses to read it.

OJD's own controller records and protocol code decide what OJD supports. Apple's personality lists (the lists of devices a macOS driver claims) don't.

## Which Road Each Model Takes

`OpenJoystickDriverUSBTransportProvider.selectDevices` picks each USB device's road. Records mark models that Apple's XboxGamepad.dext holds with `heldByAppleDriver`, which `USBDriverKitExtensionConfiguration.appleHeldModels(in:)` reads.

| Model | Held by Apple's driver | Road |
| --- | --- | --- |
| 045E:02EA, 045E:0B00, 045E:0B12 | yes | Through OJD's extension, but only when it's turned on and matches the device. Otherwise OJD leaves it alone: macOS handles the controller, and the app lists it as handled by macOS. |
| 045E:02D1, 045E:02DD, 045E:02E3, 045E:0B0A | no | Straight to the device, no extension. |
| Any other USB model | no | Straight to the device. |

- Hardware: `docs/testing/xbox-one-02d1.md` (045E:02D1, direct).
- If the extension is off, OJD never grabs the device some other way.
- The marking is fixed in the record. When Apple's driver starts claiming another model, set `heldByAppleDriver` in that record.
- `OpenJoystickDriverUSB` stores the road with each device, never guesses the road from a brand name, and never retries a failed open through a different backend.

## Why the Extension Exists

When Apple's driver holds a controller, only a DriverKit extension with the `transport.usb` entitlement for that exact model can open it. Think of the entitlement as a key Apple cut for specific doors. Every other model uses IOUSBHost.

OJD only asks macOS to turn on the extension when you click or type something. Starting the app, starting the service, and plugging in a controller never ask.

| What asks | When |
| --- | --- |
| Claim button | a model Apple's driver holds, in the Controllers list and detail |
| Driver banner button | a connected controller's road is the extension |
| `ojd controller claim` | a model Apple's driver holds; writes no record |
| `ojd transport-extension activate` | always |

The banner can say: running (button greyed out), needs approval (button opens the approval pane), cancelled, timed out, or failed. A failure shows the NSError domain, code, and text.

## Which macOS Piece Reads Each Kind of Interface

| Interface | Path |
| --- | --- |
| Standard HID input | IOHID (`IOHIDManager`, `IOHIDDevice`) |
| Accessible raw or vendor-specific USB | app-side [IOUSBHost framework](https://developer.apple.com/documentation/iousbhost?language=objc), since macOS 10.15 |
| Raw, held by Apple's driver | restricted USBDriverKit setup: the XboxUSB personality of `com.openjoystickdriver.XboxUSBDevice`, with an exact list of apps allowed to talk to it |
| Virtual HID gamepads for games | made by the app; `com.apple.developer.hid.virtual.device` isn't a DriverKit entitlement and never goes in the DEXT |

## Which Models Apple Allowed

Apple gave the team the `transport.usb` capability for set VendorID and ProductID pairs. Turn it on for the `com.openjoystickdriver.XboxUSBDevice` App ID and make the DriverKit profile again. The build refuses a DEXT profile with any other USB entitlement. The grant covers only:

```text
045E:02D1  045E:02DD  045E:02E3  045E:02EA
045E:0B00  045E:0B0A  045E:0B12
```

The personality only matches configuration 1, interface 0, class 0xFF, subclass 0x47, protocol 0xD0. That's Microsoft's GIP interface held for one owner, not every controller. Development builds use the same entitlement. The app finds the GameSir G7 SE as an IOUSBHostDevice, sets it up the way its catalog entry asks, and opens it once the GIP interface appears.

## What macOS Ships With

Seen on one Mac with macOS 27.2 (Darwin 27.2.0). Apple promises none of this.

| Plist | Content |
| --- | --- |
| `/System/Library/DriverExtensions/XboxGamepad.dext/Info.plist` | bundle identifier `com.apple.gamecontroller.driver.XboxGamepad`; IOUSBHost device and interface personalities for specific Microsoft devices, including 045E:028E, 045E:02EA, 045E:0B00, 045E:0B12 |
| `/System/Library/Extensions/AppleGameControllerPersonality.kext/Contents/Info.plist` | selected Sony, Nintendo, Amazon, and generic HID personalities |

Apple can change these plists, and a controller missing from them can still work. What OJD handles depends on the entitlement, the catalog, and hardware results.

Waiting on hardware: no capture yet shows OJD reading 02EA, 0B00, or 0B12 through the extension.

## Safety Limits

- The allow list holds exactly one name: `com.openjoystickdriver.XboxUSBDevice`.
- Letting any app talk to the DriverKit extension is forbidden.
- The DEXT's USB entitlement lists exact devices, and has no HID virtual-device entitlement.
- No road turns off SIP, installs a kernel extension, or uses a libusb or IOUSBFamily stand-in.

Source tests and unsigned builds can't show signed activation, the production provisioning profile, the device being handed over to OJD alone, or packets arriving. Those need hardware and an Apple account.
