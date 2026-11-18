# Xbox One Controller Model 1537 (045E:02D1) Detection

[Issue #18](https://github.com/xsyetopz/OpenJoystickDriver/issues/18): with the XboxUSBDevice extension active, 045E:02D1 is missing from `ojd controller list`.

## Facts From the Thread

Evidence class: reporter, not reproduced.

- felapas: beta.4, macOS 27.0.1, Apple Silicon, revision 0101 behind a GenesysLogic hub. Extension activated; `--headless controller list` showed nothing; Xbox logo kept blinking; Steam lost it until the extension was removed.
- cooltune: macOS 26.5.2, M2. A standalone IOUSBHost reader with OJD's GIP packets did the handshake, read all inputs, drove rumble. Endpoints 0x81/0x01 after `SetConfiguration(1)`.

## Source Findings

Evidence class: source (read at `1178ab9d` and SwifterKit 0.3.0, 0e0b4b8).

| # | Finding | Location |
| --- | --- | --- |
| 1 | The extension lists seven Microsoft products, 02D1 first | `Sources/OpenJoystickDriverUSB/Configuration.swift` |
| 2 | SwifterKit `USBDeviceConfiguration.matchingProperties` writes scalar `idProduct` for one product, `idProductArray` for seven; the generator copies them into the personality | `DriverKit/USB/USBTypes.swift:178-184`, `DriverExtensionGenerator.swift:374-376` |
| 3 | `IOKitDriverTransport.services(matching:)` reads DEXT service properties (matched by `CFBundleIdentifier` and `IOUserClass`); the USB runtime sets no `idProduct` or `locationID` there | |
| 4 | `USBDriverKitTransportProvider.device(_:)` returns `nil` without a scalar `idProduct`: no DEXT-route device | `Sources/OpenJoystickDriverUSB/Transport/USBDriverKitTransport.swift:71-74` |
| 5 | `OpenJoystickDriverUSBTransportProvider.selectDevices` drops direct IOUSBHost devices in `requiredDriverKitModels` (02EA, 0B00, 0B12, held by Apple's driver); 02D1 has no owner, so it goes direct without a DEXT device | `TransportFacade.swift:271-289` |
| 6 | `DeviceManager+USBDetection.swift` claims a DEXT-route 02D1 service on interface 0 when given one; detection is not the defect | |

`Tests/OpenJoystickDriverKitTests/Device/Discovery/USB/XboxOne02D1DetectionTests.swift` pins findings 1, 4, 5, 6.

## Result

Hypothesis 2 (the idProductArray lead) holds by source, narrowed: the defect is in the USB transport adapter, not `DeviceManager+USBDetection.swift`. The adapter (`Sources/OpenJoystickDriverUSB/Transport/USBDriverKitTransport.swift`) reads `idVendor`, `idProduct`, `locationID`, and strings from each DEXT service's parent `IOUSBHostDevice`, keeping the DEXT service ID for the user-client open. `dextServiceTakesIdentityFromParentUSBDevice` and `dextServiceWithoutParentYieldsNoDevice` in `XboxOne02D1DetectionTests.swift` cover it. Not verified on hardware: no active-extension registry dump exists.

Hypothesis 1 (userclient-access) can still block the open. Hypothesis 3 (GIP startup) is unlikely: cooltune's capture shows classic startup works.

## Maintainer Commands

Extension active, controller attached:

```bash
ioreg -l -w0 -r -k IOUserClass | grep -A40 'XboxUSBDevice'
ioreg -l -w0 -r -c IOUSBHostDevice | grep -E 'idVendor|idProduct|locationID'
codesign -d --entitlements - /Applications/OpenJoystickDriver.app
ojd record show 045e:02d1
```

The first confirms finding 3 if the DEXT service shows `idProductArray`, no `idProduct`.
