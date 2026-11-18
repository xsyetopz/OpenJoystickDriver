# Apple Controller Ownership and Transport Evidence

Controller records and protocol implementations define OJD support, not Apple's personality lists. Covers the route OJD picks for a USB controller.

## Route Policy

`OpenJoystickDriverUSBTransportProvider.selectDevices` picks each USB device's route. Records mark models that Apple's XboxGamepad.dext holds with `heldByAppleDriver`, which `USBDriverKitExtensionConfiguration.appleHeldModels(in:)` reads.

| Model | Held by Apple's driver | Route |
| --- | --- | --- |
| 045E:02EA, 045E:0B00, 045E:0B12 | yes | Extension, only when OJD's extension is active and matches the device. Otherwise no session: macOS serves the controller and the app lists it as served by macOS. |
| 045E:02D1, 045E:02DD, 045E:02E3, 045E:0B0A | no | Direct, no extension. |
| Any other USB model | no | Direct. |

- Hardware: `docs/testing/xbox-one-02d1.md` (045E:02D1, direct).
- An inactive extension never makes OJD claim a device another way.
- The marking is static: when Apple adds a personality, set `heldByAppleDriver` in the record.
- `OpenJoystickDriverUSB` records the route with each service, infers no transport from a brand name, and never retries a failed open on another backend.

## Purpose of the Extension

Only a DriverKit extension with the `transport.usb` entitlement for the exact model can open an interface Apple's driver holds. Every other model uses IOUSBHost.

Only a user action sends the activation request. App launch, service start, and controller arrival send none.

| Trigger | Condition |
| --- | --- |
| Claim button | held model, in the Controllers list and detail |
| Driver banner button | a connected controller's route is the extension |
| `ojd controller claim` | held model; writes no record |
| `ojd transport-extension activate` | none |

Banner states: running (button disabled), needs approval (button opens the approval pane), cancelled, timed out, failed. A failure shows the NSError domain, code, and text.

## Transport Rule

| Interface | Path |
| --- | --- |
| Standard HID input | IOHID (`IOHIDManager`, `IOHIDDevice`) |
| Accessible raw or vendor-specific USB | app-side [IOUSBHost framework](https://developer.apple.com/documentation/iousbhost?language=objc), since macOS 10.15 |
| Raw, held by Apple's driver | restricted USBDriverKit configuration: XboxUSB personality of `com.openjoystickdriver.XboxUSBDevice`, exact user-client allowlist |
| Consumer virtual HID | app-owned; `com.apple.developer.hid.virtual.device` is not a DriverKit entitlement and never belongs in the DEXT |

## Apple-Issued OJD Scope

Apple assigned the team's `transport.usb` capability (VendorID and ProductID). Enable it on the `com.openjoystickdriver.XboxUSBDevice` App ID and regenerate the DriverKit profile; the build rejects a DEXT profile with a different USB entitlement. The grant covers only:

```text
045E:02D1  045E:02DD  045E:02E3  045E:02EA
045E:0B00  045E:0B0A  045E:0B12
```

The personality matches only configuration 1, interface 0, class 0xFF, subclass 0x47, protocol 0xD0: the exclusive Microsoft GIP case, not every controller. Development uses the same entitlement. The app finds the GameSir G7 SE as an IOUSBHostDevice, configures it from its catalog requirement, and opens it once the GIP interface appears.

## Installed-System Observations

Local observations on macOS 27.2 (Darwin 27.2.0), not a compatibility contract.

| Plist | Content |
| --- | --- |
| `/System/Library/DriverExtensions/XboxGamepad.dext/Info.plist` | bundle identifier `com.apple.gamecontroller.driver.XboxGamepad`; IOUSBHost device and interface personalities for specific Microsoft devices, including 045E:028E, 045E:02EA, 045E:0B00, 045E:0B12 |
| `/System/Library/Extensions/AppleGameControllerPersonality.kext/Contents/Info.plist` | selected Sony, Nintendo, Amazon, and generic HID personalities |

Apple can change these plists, and a missing entry does not make a controller unsupported. Entitlement scope, catalog, and hardware evidence decide what OJD serves.

Hardware-gated: no capture shows OJD serving 02EA, 0B00, or 0B12 through the extension.

## Security Boundary

- The host allowlist is exactly `com.openjoystickdriver.XboxUSBDevice`.
- Allow-any DriverKit user-client access is forbidden.
- The DEXT's USB entitlement holds exact device dictionaries and no HID virtual-device entitlement.
- No route disables SIP, installs a kernel extension, or uses a libusb or IOUSBFamily shim.

Source tests and unsigned builds do not show signed activation, the production provisioning profile, exclusive ownership transfer, or packet delivery; those need hardware and an Apple account.
