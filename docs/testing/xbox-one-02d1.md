# Xbox One Controller Model 1537 (045E:02D1) Detection

[Issue #18](https://github.com/xsyetopz/OpenJoystickDriver/issues/18): with the XboxUSBDevice extension turned on, 045E:02D1 doesn't show up in `ojd controller list`.

## What People Reported

These come from the people who reported it. Nobody has made it happen again yet. A third reporter (eduardopuente, macOS 27, alpha.2, same symptom) got input working on a 0.6.0-alpha.3 tester build, wired, after removing the driver extension; the issue is closed.

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

## Configured Interfaces and Interrupt Transfers

An interface extension exists only once its parent device is configured, and SET_CONFIGURATION ends the interface it runs on. The adapter reads the parent's live `kUSBCurrentConfiguration` and sends SET_CONFIGURATION only when the record asks for a different configuration or the registry cannot be read. A device in configuration 0 publishes no interface for the extension to match, so discovery configures a vacant catalogued Microsoft device first; [Unconfigured Xbox USB Bootstrap](xbox-usb-bootstrap.md) covers that step.

USBDriverKit's `IOUSBHostPipe::IO` and `AsyncIO` require a zero completion timeout on an interrupt endpoint. The GIP protocol's 2000 ms transfer deadline is a host deadline, so the adapter reads each endpoint descriptor and passes 0 to an interrupt pipe and the millisecond timeout to a bulk pipe. Transfers are enqueued asynchronously, and one runtime event subscription matches IN and OUT completions by request identifier, including a completion that arrives before its enqueue reply.

When the host deadline passes with no completion, the adapter aborts that pipe and returns a timeout, and the connection stays open for the next request. Cancellation, an event-stream failure, an explicit close or a failed abort closes the connection and wakes every pending caller. No interrupt read with no native timeout blocks the driver's work queue.

### Separate Hardware Evidence

On macOS 26.6.1 (25G76), Apple Silicon M1, a standalone IOUSBHost reader sent powerOn, ledOn and authDone to an Xbox One `045E:02D1` with endpoints `81`/`01`. A 30-second run received 1284 input reports and the operator confirmed a solid LED. A later run fed input through the signed app's `ojd virtual feed --as game-controller-compatible`; GameController.framework reported a connected extended gamepad and live input. The operator reported days of gameplay with an original Elite `045E:02E3` through the same external bridge.

The signed app used for the bridge was `0.6.0-alpha.2+build.1.21.99.sha.93d79f3973f0 (1.21.99)`. This verifies the external IOUSBHost/GIP-to-virtual-feed route, not a signed build of the extension adapter above. Native DriverKit input through this adapter, independent Elite paddle inputs, physical rumble and cold enumeration in configuration 0 are not checked. The Elite record `045e-02e3.plist` uses the same endpoints `0x81`/`0x01`, and an owner reports input, rumble, and a game working on 0.6.0-alpha.3 ([issue #55](https://github.com/xsyetopz/OpenJoystickDriver/issues/55)).

## Commands for Maintainers

With the extension on and the controller plugged in:

```bash
ioreg -l -w0 -r -k IOUserClass | grep -A40 'XboxUSBDevice'
ioreg -l -w0 -r -c IOUSBHostDevice | grep -E 'idVendor|idProduct|locationID'
codesign -d --entitlements - /Applications/OpenJoystickDriver.app
ojd record show 045e:02d1
```

The first command confirms finding 3 if the DEXT service shows `idProductArray` and no `idProduct`.
