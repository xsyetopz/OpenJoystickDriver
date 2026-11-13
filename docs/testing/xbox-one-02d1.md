# Xbox One Controller Model 1537 (`045E:02D1`) Detection

This page records [issue #18](https://github.com/xsyetopz/OpenJoystickDriver/issues/18): with
the XboxUSBDevice extension active, `045E:02D1` is not in `ojd controller list`.

## Facts from the thread

Evidence class: reporter (not reproduced here).

- felapas: beta.4, macOS 27.0.1, Apple Silicon, controller revision `0101` behind a GenesysLogic
  hub. The extension activated, `--headless controller list` showed no controller, the Xbox logo
  kept blinking, and Steam lost the controller until the extension was removed.
- cooltune: macOS 26.5.2, M2. A standalone IOUSBHost reader with OJD's GIP packets completed the
  handshake, read all inputs, and drove rumble. Endpoints are `0x81`/`0x01` after
  `SetConfiguration(1)`.

## Source findings

Evidence class: source (read at `1178ab9d` and SwifterKit `0.3.0`, `0e0b4b8`).

1. The extension lists seven Microsoft products, `02D1` first
   (`Sources/OpenJoystickDriverUSB/Configuration.swift`).
2. SwifterKit `USBDeviceConfiguration.matchingProperties` writes a scalar `idProduct` only for
   one product. For seven it writes `idProductArray` (`DriverKit/USB/USBTypes.swift:178-184`).
   The generator copies these keys into the personality (`DriverExtensionGenerator.swift:374-376`).
3. `IOKitDriverTransport.services(matching:)` reads the properties of the DEXT service itself,
   matched by `CFBundleIdentifier` and `IOUserClass`. The USB runtime sources set no `idProduct`
   or `locationID` on that service.
4. `USBDriverKitTransportProvider.device(_:)`
   (`Sources/OpenJoystickDriverUSB/Transport/USBDriverKitTransport.swift:71-74`) returns `nil`
   when the service has no scalar `idProduct`. The DEXT route then lists no device.
5. `OpenJoystickDriverUSBTransportProvider.selectDevices` (`TransportFacade.swift:271-289`)
   drops a direct IOUSBHost device whose model is in `requiredDriverKitModels`, which holds the
   products that Apple's driver holds (`02EA`, `0B00`, `0B12`). `02D1` has no owner, so it takes
   the direct route when no DEXT device exists.
6. `DeviceManager+USBDetection.swift` claims a DEXT-route `02D1` service on interface 0 when one
   is given to it. Detection is not the defect.

`Tests/OpenJoystickDriverKitTests/Device/Discovery/USB/XboxOne02D1DetectionTests.swift` pins
findings 1, 4, 5, and 6.

## Result

Hypothesis 2 holds in a narrower form: the defect is in the USB transport adapter, not in
`DeviceManager+USBDetection.swift`. The idProductArray lead from the thread holds by source.
It is not confirmed on hardware: no registry dump of the active extension exists.

`Sources/OpenJoystickDriverUSB/Transport/USBDriverKitTransport.swift`
reads `idVendor`, `idProduct`, `locationID`, and the strings from the parent
`IOUSBHostDevice` of each DEXT service, and keeps the DEXT service ID for the user-client open.
`dextServiceTakesIdentityFromParentUSBDevice` and `dextServiceWithoutParentYieldsNoDevice` in
`XboxOne02D1DetectionTests.swift` cover it. This behavior is not verified on hardware.

Hypothesis 1 (`userclient-access`) can still block the open after the fix. Hypothesis 3 (GIP
startup) is unlikely: cooltune's capture shows the classic startup works.

## Commands for the maintainer

With the extension active and the controller attached:

```bash
ioreg -l -w0 -r -k IOUserClass | grep -A40 'XboxUSBDevice'
ioreg -l -w0 -r -c IOUSBHostDevice | grep -E 'idVendor|idProduct|locationID'
codesign -d --entitlements - /Applications/OpenJoystickDriver.app
ojd record show 045e:02d1
```

The first command confirms finding 3 when the DEXT service shows `idProductArray` and no
`idProduct`.
