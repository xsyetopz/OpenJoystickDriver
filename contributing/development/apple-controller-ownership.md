# Apple Controller Ownership And Transport Evidence

Controller records and protocol implementations define OJD support, not Apple's controller-personality lists. macOS ownership determines which Apple USB transport can reach a particular physical interface.

## Current Transport Rule

- Standard HID input uses IOHID (`IOHIDManager` / `IOHIDDevice`) on every supported macOS.
- Accessible raw or vendor-specific USB interfaces use the app-side [IOUSBHost framework](https://developer.apple.com/documentation/iousbhost?language=objc), available since macOS 10.15.
- A raw interface owned through OJD's restricted USBDriverKit configuration uses the `XboxUSB` personality of `com.openjoystickdriver.VirtualHIDDevice` and its exact user-client allowlist.
- Consumer virtual HID is app-owned. `com.apple.developer.hid.virtual.device` is not a DriverKit entitlement and never belongs in the DEXT.

`OpenJoystickDriverUSB` records the selected route with each discovered service. It does not infer transport from a brand name and does not retry an open failure through a different backend. The Apple-entitled Microsoft models are always reserved for the DEXT, even when unavailable: direct claims would bypass the established ownership and provisioning boundary.

## Apple-Issued OJD Scope

The team's `transport.usb` capability (VendorID and ProductID) is already assigned. Enable it on the `com.openjoystickdriver.VirtualHIDDevice` App ID and regenerate the DriverKit profile; a profile without it builds factory-only (no Xbox USB ownership). The USB transport entitlement covers only:

```text
045E:02D1  045E:02DD  045E:02E3  045E:02EA
045E:0B00  045E:0B0A  045E:0B12
```

The generated personality additionally restricts matching to configuration 1, interface 0, class `0xFF`, subclass `0x47`, and protocol `0xD0`. This grant solves the exclusive Microsoft GIP ownership case; it is not a request or grant for every first-party or third-party controller. Development uses the same exact entitlement. The GameSir G7 SE is discovered as an `IOUSBHostDevice`, configured from its catalog requirement, and opened by the app after its GIP interface appears.

## Installed-System Observations

Local macOS 26.6.1 observations, not a public compatibility contract:

- `/System/Library/DriverExtensions/XboxGamepad.dext/Contents/Info.plist` has bundle identifier `com.apple.gamecontroller.driver.XboxGamepad` and specific Microsoft matches including `045E:028E`, `045E:02EA`, `045E:0B00`, and `045E:0B12` through IOUSBHost device/interface personalities.
- the installed `AppleGameControllerPersonality.kext` contains selected Sony, Nintendo, Amazon, and generic HID recognition personalities.

Those plists explain why macOS can report an exclusive owner for some controllers. Apple can change this implementation snapshot; absence does not prove a controller is unsupported. OJD must still use live registry ownership, its signed entitlement scope, its catalog, and hardware evidence.

## Security Boundary

The host allowlist is exactly `com.openjoystickdriver.VirtualHIDDevice`; allow-any DriverKit user-client access is forbidden. The DEXT's optional USB entitlement contains exact device dictionaries, and the DEXT has no HID virtual-device entitlement. No route disables SIP, installs a kernel extension, or restores the removed libusb/IOUSBFamily shim path.

Signed activation, the production provisioning profile, exclusive ownership transfer, and physical packet delivery remain hardware-and-account checks. Source tests and unsigned DriverKit builds do not prove them.
