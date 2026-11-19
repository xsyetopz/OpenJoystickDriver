# Xbox One Controller Model 1537 (045E:02D1) Detection

[Issue #18](https://github.com/xsyetopz/OpenJoystickDriver/issues/18): with the XboxUSBDevice extension turned on, 045E:02D1 doesn't show up in `ojd controller list`.

## What People Reported

These come from the people who reported it. Nobody has made it happen again yet.

- felapas: beta.4, macOS 27.0.1, Apple silicon, controller revision 0101 behind a GenesysLogic hub. The extension was on, `--headless controller list` showed nothing, and the Xbox logo kept blinking. Steam lost the controller until the extension was removed.
- cooltune: macOS 26.5.2, M2. A separate IOUSBHost reader that sent OJD's GIP packets did the handshake, read every input, and ran rumble. Endpoints 0x81/0x01 after `SetConfiguration(1)`.

## What the Code Shows

Read at `1178ab9d` and SwifterKit 0.3.0, 0e0b4b8.

| # | Finding | Location |
| --- | --- | --- |
| 1 | The extension lists seven Microsoft products, with 02D1 first | `Sources/OpenJoystickDriverUSB/Configuration.swift` |
| 2 | SwifterKit's `USBDeviceConfiguration.matchingProperties` writes a single `idProduct` for one product and an `idProductArray` for seven. The generator copies them into the personality | `DriverKit/USB/USBTypes.swift:178-184`, `DriverExtensionGenerator.swift:374-376` |
| 3 | `IOKitDriverTransport.services(matching:)` reads the DEXT service's properties (found by `CFBundleIdentifier` and `IOUserClass`). The USB runtime puts no `idProduct` or `locationID` there | |
| 4 | Without a single `idProduct`, `USBDriverKitTransportProvider.device(_:)` returns `nil`, so the DEXT road has no device | `Sources/OpenJoystickDriverUSB/Transport/USBDriverKitTransport.swift:71-74` |
| 5 | `OpenJoystickDriverUSBTransportProvider.selectDevices` drops direct IOUSBHost devices listed in `requiredDriverKitModels` (02EA, 0B00, 0B12, which Apple's driver holds). 02D1 has no owner, so it goes direct, with no DEXT device | `TransportFacade.swift:271-289` |
| 6 | `DeviceManager+USBDetection.swift` claims a DEXT-road 02D1 service on interface 0 when it gets one, so detection itself isn't the bug | |

`Tests/OpenJoystickDriverKitTests/Device/Discovery/USB/XboxOne02D1DetectionTests.swift` locks in findings 1, 4, 5, and 6.

## Result

Idea 2 (the `idProductArray` lead) holds up in the code, more narrowly: the bug is in the USB transport adapter, not in `DeviceManager+USBDetection.swift`. The adapter (`Sources/OpenJoystickDriverUSB/Transport/USBDriverKitTransport.swift`) reads `idVendor`, `idProduct`, `locationID`, and the name strings from each DEXT service's parent `IOUSBHostDevice`, and keeps the DEXT service ID for opening the user client. `dextServiceTakesIdentityFromParentUSBDevice` and `dextServiceWithoutParentYieldsNoDevice` in `XboxOne02D1DetectionTests.swift` test it. Not checked on hardware, because nobody has a registry dump with the extension active.

Idea 1 (userclient-access) could still stop the open. Idea 3 (GIP startup) is unlikely, because cooltune's capture shows the classic startup works.

## Commands for Maintainers

With the extension on and the controller plugged in:

```bash
ioreg -l -w0 -r -k IOUserClass | grep -A40 'XboxUSBDevice'
ioreg -l -w0 -r -c IOUSBHostDevice | grep -E 'idVendor|idProduct|locationID'
codesign -d --entitlements - /Applications/OpenJoystickDriver.app
ojd record show 045e:02d1
```

The first command confirms finding 3 if the DEXT service shows `idProductArray` and no `idProduct`.
