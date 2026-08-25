# Apple controller ownership and transport evidence

OJD controller support is not defined by an Apple controller-personality list. Controller records
and protocol implementations remain OJD's support sources. macOS ownership determines which Apple
USB transport can reach a particular physical interface.

## Current transport rule

- Standard HID input uses the OS-generation HID wrapper: IOHID on macOS 10.15–14 and CoreHID on
  macOS 15 and later.
- Accessible raw or vendor-specific USB interfaces use the app-side
  [IOUSBHost framework](https://developer.apple.com/documentation/iousbhost?language=objc), available
  since macOS 10.15.
- A raw interface owned through OJD's restricted USBDriverKit configuration uses
  `com.openjoystickdriver.XboxUSBDevice` and its exact user-client allowlist.
- Consumer virtual HID is app-owned. `com.apple.developer.hid.virtual.device` is not a DriverKit
  entitlement and never belongs in the DEXT.

`OpenJoystickDriverUSB` records the selected route with each discovered service. It does not infer
transport from a brand name and does not retry an open failure through a different backend. The
Apple-entitled Microsoft models are always reserved for the DEXT, even when that DEXT is not
currently available, because silently claiming them directly would bypass the established
ownership and provisioning boundary.

## Apple-issued OJD scope

Apple granted the host user-client entitlement for the existing external identity
`com.openjoystickdriver.XboxUSBDevice`. The production USB transport entitlement covers only:

```text
045E:02D1  045E:02DD  045E:02E3  045E:02EA
045E:0B00  045E:0B0A  045E:0B12
```

The generated personality additionally restricts matching to configuration 1, interface 0, class
`0xFF`, subclass `0x47`, and protocol `0xD0`. This grant solves the exclusive Microsoft GIP
ownership case; it is not a request or grant for every first-party or third-party controller.
Development uses the same exact entitlement. The GameSir G7 SE is discovered as an
`IOUSBHostDevice`, configured from its catalog requirement, and opened by the app after its GIP
interface appears.

## Installed-system observations

The following is a local observation from macOS 26.6.1, not a public compatibility contract:

- `/System/Library/DriverExtensions/XboxGamepad.dext/Contents/Info.plist` has bundle identifier
  `com.apple.gamecontroller.driver.XboxGamepad` and specific Microsoft matches including
  `045E:028E`, `045E:02EA`, `045E:0B00`, and `045E:0B12` through IOUSBHost device/interface
  personalities.
- the installed `AppleGameControllerPersonality.kext` contains selected Sony, Nintendo, Amazon,
  and generic HID recognition personalities.

Those plists explain why macOS can report an exclusive owner for some controllers. They are an
implementation snapshot that Apple can change, and absence from them does not prove a controller
is unsupported. OJD must still use live registry ownership, its signed entitlement scope, its
catalog, and hardware evidence.

## Security boundary

The host allowlist contains only `com.openjoystickdriver.XboxUSBDevice`; allow-any DriverKit
user-client access is forbidden. The DEXT's USB entitlement contains exact device
dictionaries and no CoreHID virtual-device or HIDDriverKit entitlement. No route disables SIP,
installs a kernel extension, or restores the removed libusb/IOUSBFamily shim path.

Signed activation, the production provisioning profile, exclusive ownership transfer, and physical
packet delivery remain hardware-and-account checks. Source tests and unsigned DriverKit builds do
not prove them.
