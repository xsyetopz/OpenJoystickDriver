# Xbox One Controller Model 1537 (`045E:02D1`) Detection

This page records [issue #18](https://github.com/xsyetopz/OpenJoystickDriver/issues/18): with
the XboxUSBDevice extension active, `045E:02D1` is not in `ojd controller list`.

## Facts From The Thread

Evidence class: reporter (not reproduced here).

- felapas: beta.4, macOS 27.0.1, Apple Silicon, controller revision `0101` behind a GenesysLogic
  hub. The extension activated, `--headless controller list` showed no controller, the Xbox logo
  kept blinking, and Steam lost the controller until the extension was removed.
- cooltune: macOS 26.5.2, M2. A standalone IOUSBHost reader with OJD's GIP packets completed the
  handshake, read all inputs, and drove rumble. Endpoints are `0x81`/`0x01` after
  `SetConfiguration(1)`.

## Source Findings

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
   drops a direct IOUSBHost device whose model is in `requiredDriverKitModels`, which holds all
   seven products. With no DEXT device, `02D1` reaches no route.
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

## Configured Interfaces And Interrupt Transfers

The extension transport also needs to distinguish interface ownership from a failed startup
operation. For a record requesting configuration 1, the old transport replayed a standard
device SET_CONFIGURATION through the extension after its interface had already been claimed.
The adapter now reads the parent device's live `kUSBCurrentConfiguration` and verifies the
requested value before opening the user client. It does not reconfigure an owned interface;
an unknown or mismatched requested configuration is rejected.

USBDriverKit's `IOUSBHostPipe::IO` and `AsyncIO` require a zero completion timeout for interrupt
endpoints. The GIP protocol's 2000 ms transfer deadline is a host deadline, not permission to
pass that value to an interrupt pipe. The adapter reads endpoint descriptors and enqueues
asynchronous transfers with zero interrupt timeouts, retaining millisecond timeouts for bulk
endpoints. One runtime event subscription matches IN and OUT completions by request identifier,
including completions delivered before their enqueue responses.

An idle host deadline aborts the affected pipe before returning a timeout, keeping the
connection open for the next request. Cancellation, event-stream failure, explicit close, or
an abort failure releases the connection and wakes pending callers. This avoids blocking the
driver work queue on an interrupt read with no native timeout.

### Separate Hardware Evidence

On macOS 26.6.1 (25G76), Apple Silicon M1, a standalone IOUSBHost reader sent powerOn, ledOn
and authDone to an Xbox One `045E:02D1` with endpoints `81`/`01`. A 30-second run received
1284 input reports and the operator confirmed a solid LED. A later run fed input through
the signed app's `ojd virtual feed --as game-controller-compatible`; GameController.framework
reported a connected extended gamepad and live input. The operator subsequently reported
days of gameplay using an original Elite `045E:02E3` through the same external bridge.

The signed app used for the bridge was
`0.6.0-alpha.2+build.1.21.99.sha.93d79f3973f0 (1.21.99)`. This verifies the external
IOUSBHost/GIP-to-virtual-feed route, not a signed build of the extension adapter above.
Native DriverKit input after this change, independent Elite paddle inputs, physical rumble
and cold enumeration in configuration 0 are not checked on this branch.

The unconfigured-device discovery bootstrap remains outside this change. The Elite endpoint
override is tracked separately in [PR #56](https://github.com/xsyetopz/OpenJoystickDriver/pull/56)
and [issue #55](https://github.com/xsyetopz/OpenJoystickDriver/issues/55). Neither issue #18
nor #55 is established as fully resolved by the transport changes alone.

## Commands For The Maintainer

With the extension active and the controller attached:

```bash
ioreg -l -w0 -r -k IOUserClass | grep -A40 'XboxUSBDevice'
ioreg -l -w0 -r -c IOUSBHostDevice | grep -E 'idVendor|idProduct|locationID'
codesign -d --entitlements - /Applications/OpenJoystickDriver.app
./Scripts/ojd record show 045e:02d1
```

The first command confirms finding 3 when the DEXT service shows `idProductArray` and no
`idProduct`.
