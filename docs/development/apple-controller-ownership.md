# Apple Controller Ownership and Transport Evidence

Controller records and protocol implementations define OJD support, not Apple's controller-personality lists. macOS ownership determines which Apple USB transport can reach a particular physical interface.

## Route Policy

`OpenJoystickDriverUSBTransportProvider.selectDevices` picks the route of each discovered USB device. `USBDriverKitExtensionConfiguration.appleHeldProductIDs` lists the models that Apple's `XboxGamepad.dext` holds.

| Model | Held by Apple's driver | Route |
| --- | --- | --- |
| `045E:02EA`, `045E:0B00`, `045E:0B12` | yes | Extension, only when OJD's extension is active and matches the device. Otherwise no session: macOS serves the controller and the app lists it as served by macOS. |
| `045E:02D1`, `045E:02DD`, `045E:02E3`, `045E:0B0A` | no | Direct, with no extension. |
| Any other USB model | no | Direct. |

- A model with no owner takes the direct route. `docs/testing/xbox-one-02d1.md` records the direct route on hardware for `045E:02D1`.
- The extension route needs an active, matched extension. An inactive extension never makes OJD claim a device by another path.
- The list is static. It is not read from the live registry, so a new Apple personality for another model needs an entry in `appleHeldProductIDs`.
- `OpenJoystickDriverUSB` records the selected route with each discovered service. It does not infer transport from a brand name and does not retry an open failure through a different backend.

## Purpose of the Extension

The extension exists to take a controller from Apple's driver. Only a DriverKit extension that carries the `transport.usb` entitlement for the exact model can open an interface that Apple's driver already holds. It is not a general transport: every other model reaches the app through IOUSBHost.

Nothing sends the activation request on its own. The request starts from a user action:

- The Claim button for a model that Apple's driver holds, in the Controllers list and in the detail.
- The driver banner button, shown while a connected controller's route is the extension.
- `ojd controller claim` for a model that Apple's driver holds, which sends the request instead of writing a record.
- `ojd transport-extension activate`.

App launch, service start and controller arrival send no request. The banner shows the state of the request: running (button disabled), needs approval (button that opens the approval pane), cancelled, timed out, and failed with the `NSError` domain, code and text.

## Transport Rule

- Standard HID input uses IOHID (`IOHIDManager` / `IOHIDDevice`) on every supported macOS.
- Accessible raw or vendor-specific USB interfaces use the app-side [IOUSBHost framework](https://developer.apple.com/documentation/iousbhost?language=objc), available since macOS 10.15.
- A raw interface that Apple's driver holds is owned through OJD's restricted USBDriverKit configuration: the `XboxUSB` personality of `com.openjoystickdriver.XboxUSBDevice` and its exact user-client allowlist.
- Consumer virtual HID is app-owned. `com.apple.developer.hid.virtual.device` is not a DriverKit entitlement and never belongs in the DEXT.

## Apple-Issued OJD Scope

The team's `transport.usb` capability (VendorID and ProductID) is already assigned. Enable it on the `com.openjoystickdriver.XboxUSBDevice` App ID and regenerate the DriverKit profile; the build rejects a DEXT profile whose USB entitlement is not exactly this grant. The USB transport entitlement covers only:

```text
045E:02D1  045E:02DD  045E:02E3  045E:02EA
045E:0B00  045E:0B0A  045E:0B12
```

The generated personality additionally restricts matching to configuration 1, interface 0, class `0xFF`, subclass `0x47`, and protocol `0xD0`. This grant solves the exclusive Microsoft GIP ownership case; it is not a request or grant for every first-party or third-party controller. Development uses the same exact entitlement. The GameSir G7 SE is discovered as an `IOUSBHostDevice`, configured from its catalog requirement, and opened by the app after its GIP interface appears.

## Installed-System Observations

Local macOS 26.6.1 observations, not a public compatibility contract:

- `/System/Library/DriverExtensions/XboxGamepad.dext/Contents/Info.plist` has bundle identifier `com.apple.gamecontroller.driver.XboxGamepad` and specific Microsoft matches including `045E:028E`, `045E:02EA`, `045E:0B00`, and `045E:0B12` through IOUSBHost device/interface personalities.
- the installed `AppleGameControllerPersonality.kext` contains selected Sony, Nintendo, Amazon, and generic HID recognition personalities.

Those plists explain why macOS can report an exclusive owner for some controllers. Apple can change this implementation snapshot; absence does not prove a controller is unsupported. The signed entitlement scope, the catalog, and hardware evidence decide what OJD serves.

Hardware-gated: no capture shows OJD serving `02EA`, `0B00`, or `0B12` through the extension. Task 4.9 of `openspec/changes/0-6-0-alpha-3` runs that check.

## Security Boundary

The host allowlist is exactly `com.openjoystickdriver.XboxUSBDevice`; allow-any DriverKit user-client access is forbidden. The DEXT's USB entitlement contains exact device dictionaries, and the DEXT has no HID virtual-device entitlement. No route disables SIP, installs a kernel extension, or restores the removed libusb/IOUSBFamily shim path.

Signed activation, the production provisioning profile, exclusive ownership transfer, and physical packet delivery remain hardware-and-account checks. Source tests and unsigned DriverKit builds do not prove them.
