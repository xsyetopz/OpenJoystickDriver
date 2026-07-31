# #22: Controller with bDeviceClass=0 is never discovered (vendor-specific class only on interface)

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/22
- **State:** OPEN
- **Labels:** bug, help wanted

## Report

**Device:** ZD Ultimate Legend in XInput mode, wired USB
**VID** `0x413D`, **PID** `0x2104` ("XBOX 360 For Windows")
**macOS** 26.6.0, OJD v0.4.1

Profile `413d-2104.json` already exists in the catalog, but the device
is never detected. `diagnose report` prints:

```
USB Game Controllers (class 0xFF):
  (none detected)
```

**Cause:** this controller reports `bDeviceClass = 0` and declares the
vendor-specific class only at the interface level. Confirmed via
`ioreg`: `"bDeviceClass" = 0` for this device.

Both discovery paths filter on the device descriptor class:

- `USBDetection.swift:73`
  `context.findDevices(deviceClass: usbVendorSpecificClass, findAll: true)`
- `USBControllerScanner.swift`
  `context.findDevices(deviceClass: .vendorSpecific, findAll: true)`

So the device is skipped before the catalog lookup ever happens.

`USBDescriptorTransportResolver.swift:94` already does the right thing
elsewhere (`for interface in interfaces where interface.interfaceClass == 0xFF`),
so discovery probably needs the same interface-level check as a fallback
when `bDeviceClass` is 0.

Happy to test a build.
