# #22: Controller with bDeviceClass=0 is never discovered (vendor-specific class only on interface)

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/22
- **State:** OPEN
- **Author:** lunarephemera
- **Created:** 2026-07-30T18:46:37Z
- **Updated:** 2026-08-29T11:11:53Z
- **Closed:** —
- **Labels:** bug, help wanted

## Report

Device: ZD Ultimate Legend in XInput mode, wired USB
VID 0x413D, PID 0x2104 ("XBOX 360 For Windows")
macOS 26.6.0, OJD v0.4.1

Profile 413d-2104.json already exists in the catalog, but the device
is never detected. `diagnose report` prints:

  USB Game Controllers (class 0xFF):
    (none detected)

Cause: this controller reports bDeviceClass = 0 and declares the
vendor-specific class only at the interface level. Confirmed via
ioreg: "bDeviceClass" = 0 for this device.

Both discovery paths filter on the device descriptor class:

  USBDetection.swift:73
    context.findDevices(deviceClass: usbVendorSpecificClass, findAll: true)
  USBControllerScanner.swift
    context.findDevices(deviceClass: .vendorSpecific, findAll: true)

So the device is skipped before the catalog lookup ever happens.

USBDescriptorTransportResolver.swift:94 already does the right thing
elsewhere (`for interface in interfaces where interface.interfaceClass == 0xFF`),
so discovery probably needs the same interface-level check as a fallback
when bDeviceClass is 0.

Happy to test a build.

## Comments

### xsyetopz — 2026-07-31T03:21:35Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5138901236)

Damn, some controllers just *cannot* be standard, huh? Gotta love providers just doing their own thing. Alright, that's another thing to get going.

### lunarephemera — 2026-08-01T08:10:32Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5150559853)

Thanks for turning this around so fast.

I still have the hardware here (ZD Ultimate Legend, 413D:2104), so I'm happy to test the fix before it ships. Is there a build of main I could grab somewhere? I don't have a Swift toolchain set up on my side, so a packaged .app would be ideal — but no rush if you'd rather just fold it into the next release.

One thing worth checking while I'm at it: 413d-2104.json is marked verified: false and came from linux-xpad.c, so the button mapping has never been confirmed on real hardware. Once detection works I can go through Input Test and report back on whether the mapping is correct, and you can flip the flag if it is.

### xsyetopz — 2026-08-01T12:56:04Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5151514770)

> Thanks for turning this around so fast.
>
> I still have the hardware here (ZD Ultimate Legend, 413D:2104), so I'm happy to test the fix before it ships. Is there a build of main I could grab somewhere? I don't have a Swift toolchain set up on my side, so a packaged .app would be ideal — but no rush if you'd rather just fold it into the next release.
>
> One thing worth checking while I'm at it: 413d-2104.json is marked verified: false and came from linux-xpad.c, so the button mapping has never been confirmed on real hardware. Once detection works I can go through Input Test and report back on whether the mapping is correct, and you can flip the flag if it is.

I've yet to make a new release (beta) as 0.5.0 is supposed to be a giant update that breaks some changes, therefore there's time before I get there. It needs a new MenuApp GUI.

### lunarephemera — 2026-08-01T13:50:40Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5151707639)

Ran the unsigned CLI path against the hardware. Summary: the raw USB side works perfectly and the record's mapping is correct, but `diagnose record` itself fails. Details below.

**Descriptors confirm the fix targets the right thing**

```
bDeviceClass = 0
  interface 0: bInterfaceClass = 255, bInterfaceSubClass = 93   <- XInput
  interface 1: bInterfaceClass = 3,   bInterfaceSubClass = 1
  interface 2: bInterfaceClass = 3,   bInterfaceSubClass = 0
```

So this is a composite device: a vendor-specific XInput interface plus two HID interfaces. The HID ones are already matched by macOS (`IOClass = AppleUserHIDDevice`, `com.apple.AppleUserHIDDrivers`); the vendor-specific interface is unclaimed.

**Raw USB monitor works**

```
OpenJoystickDriverHIDTool --usb-monitor --vid 0x413d --pid 0x2104 --interface 0 --seconds 20
-> USB_SUMMARY packets=159617 disabled_endpoints=14
```

Endpoint 0x81, 20-byte reports, standard wired Xbox 360 layout, e.g.

```
00 14 00 00 00 00 35 77 e9 c2 77 eb 22 dc 00 00 00 00 00 00
```

**Mapping verified, 16/16**

Taken from the raw capture, one control at a time (byte 2 / byte 3):

```
01 00  dpad up        00 01  LB
02 00  dpad down      00 02  RB
04 00  dpad left      00 04  Guide
08 00  dpad right     00 10  A
10 00  Start          00 20  B
20 00  Back           00 40  X
40 00  L3             00 80  Y
80 00  R3
```

Every control matches the standard wired Xbox 360 layout bit for bit — no remapping needed. Triggers are fully analog: byte 4 takes 252 distinct values and byte 5 takes 255 across the capture. Sticks read near zero at rest with no drift and reach full range.

So the identity and parsing side of 413d-2104.json looks correct. I haven't checked reconnect stability or LED/rumble behavior, so I'll leave the call on flipping `verified` to you.

**But `diagnose record` fails**

```
RECORD identity="Controller 413d:2104" vid=16701 pid=8452 driver=Xbox360 interface=0 in=0x81 out=0x1 configuration=current startup=none
USB_MATCHES count=1
USB_DEVICE bus=3 address=2 class=0x0 subclass=0x0 protocol=0x0
USB_STRING manufacturer=Microsoft
USB_STRING product=XBOX 360 For Windows
USB_CLAIM interface=0 result=claimed
RECORD_HANDSHAKE driver=Xbox360 result=complete
ERROR: record probe failed: The operation couldn't be completed. (SwiftUSB.USBError error 1.)
```

No USB_RX, no RECORD_SUMMARY. Same result under sudo. With `--detach` it fails earlier with `LIBUSB_ERROR_ACCESS (code: -3)`, which I assume is expected on macOS.

So: claiming works, the handshake completes, and raw reads on the same endpoint work fine outside the probe — but the probe's first read throws. The read loop only continues on `error.isTimeout`, so anything else aborts.

Two things that made this harder to diagnose, in case they're worth fixing:

- The real libusb code never surfaces. `isExpectedError` suppresses logging for IO / NOT_FOUND / NO_DEVICE, and `USBError` has no `LocalizedError` conformance, so the message degrades to "error 1". Printing the code on probe abort would have made this a one-line report.
- `startup=none` on a wired Xbox 360 record — I wasn't sure whether that's expected, given the docs mention a steady Player 1 ring-light packet.

Happy to run anything else against the hardware.

macOS 26.6.0, MacBook Pro M5, commit 559933f, record is the bundled 413d-2104.json copied verbatim.

### xsyetopz — 2026-08-01T13:52:20Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5151713106)

> Ran the unsigned CLI path against the hardware. Summary: the raw USB side works perfectly and the record's mapping is correct, but `diagnose record` itself fails. Details below.
>
> **Descriptors confirm the fix targets the right thing**
>
> ```
> bDeviceClass = 0
>   interface 0: bInterfaceClass = 255, bInterfaceSubClass = 93   <- XInput
>   interface 1: bInterfaceClass = 3,   bInterfaceSubClass = 1
>   interface 2: bInterfaceClass = 3,   bInterfaceSubClass = 0
> ```
>
> So this is a composite device: a vendor-specific XInput interface plus two HID interfaces. The HID ones are already matched by macOS (`IOClass = AppleUserHIDDevice`, `com.apple.AppleUserHIDDrivers`); the vendor-specific interface is unclaimed.
>
> **Raw USB monitor works**
>
> ```
> OpenJoystickDriverHIDTool --usb-monitor --vid 0x413d --pid 0x2104 --interface 0 --seconds 20
> -> USB_SUMMARY packets=159617 disabled_endpoints=14
> ```
>
> Endpoint 0x81, 20-byte reports, standard wired Xbox 360 layout, e.g.
>
> ```
> 00 14 00 00 00 00 35 77 e9 c2 77 eb 22 dc 00 00 00 00 00 00
> ```
>
> **Mapping verified, 16/16**
>
> Taken from the raw capture, one control at a time (byte 2 / byte 3):
>
> ```
> 01 00  dpad up        00 01  LB
> 02 00  dpad down      00 02  RB
> 04 00  dpad left      00 04  Guide
> 08 00  dpad right     00 10  A
> 10 00  Start          00 20  B
> 20 00  Back           00 40  X
> 40 00  L3             00 80  Y
> 80 00  R3
> ```
>
> Every control matches the standard wired Xbox 360 layout bit for bit — no remapping needed. Triggers are fully analog: byte 4 takes 252 distinct values and byte 5 takes 255 across the capture. Sticks read near zero at rest with no drift and reach full range.
>
> So the identity and parsing side of 413d-2104.json looks correct. I haven't checked reconnect stability or LED/rumble behavior, so I'll leave the call on flipping `verified` to you.
>
> **But `diagnose record` fails**
>
> ```
> RECORD identity="Controller 413d:2104" vid=16701 pid=8452 driver=Xbox360 interface=0 in=0x81 out=0x1 configuration=current startup=none
> USB_MATCHES count=1
> USB_DEVICE bus=3 address=2 class=0x0 subclass=0x0 protocol=0x0
> USB_STRING manufacturer=Microsoft
> USB_STRING product=XBOX 360 For Windows
> USB_CLAIM interface=0 result=claimed
> RECORD_HANDSHAKE driver=Xbox360 result=complete
> ERROR: record probe failed: The operation couldn't be completed. (SwiftUSB.USBError error 1.)
> ```
>
> No USB_RX, no RECORD_SUMMARY. Same result under sudo. With `--detach` it fails earlier with `LIBUSB_ERROR_ACCESS (code: -3)`, which I assume is expected on macOS.
>
> So: claiming works, the handshake completes, and raw reads on the same endpoint work fine outside the probe — but the probe's first read throws. The read loop only continues on `error.isTimeout`, so anything else aborts.
>
> Two things that made this harder to diagnose, in case they're worth fixing:
>
> * The real libusb code never surfaces. `isExpectedError` suppresses logging for IO / NOT_FOUND / NO_DEVICE, and `USBError` has no `LocalizedError` conformance, so the message degrades to "error 1". Printing the code on probe abort would have made this a one-line report.
> * `startup=none` on a wired Xbox 360 record — I wasn't sure whether that's expected, given the docs mention a steady Player 1 ring-light packet.
>
> Happy to run anything else against the hardware.
>
> macOS 26.6.0, MacBook Pro M5, commit [559933f](https://github.com/xsyetopz/OpenJoystickDriver/commit/559933fe1afaf7c26bd544e14a3e2ade62e5030e), record is the bundled 413d-2104.json copied verbatim.

Motherf##ing ZD, man. Why do they do this? *siiiiiiigh* back to the code we go...

### xsyetopz — 2026-08-01T13:54:21Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5151720347)

<img width="1600" height="1200" alt="Image" src="https://github.com/user-attachments/assets/9901c4fc-e51c-46d5-a74e-5c03b38a29c9" />

### lunarephemera — 2026-08-01T13:57:07Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5151735439)

Sorry about the extra work, didn't mean to ruin your weekend with a no-name controller

For what it's worth, the hardware's here and the CLI builds fine on my side, so I'm around whenever you want something tested or captured. Just say what you need and I'll run it

### xsyetopz — 2026-08-01T13:59:56Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5151745523)

> Sorry about the extra work, didn't mean to ruin your weekend with a no-name controller
>
> For what it's worth, the hardware's here and the CLI builds fine on my side, so I'm around whenever you want something tested or captured. Just say what you need and I'll run it

Haha, it's all good. Nothing was ruint. Trust. I *REALLY* appreciate people actually finding this project useful and contributing. HOWEVER, ZD... the company... yeah, they can take a walk in the forest.

### xsyetopz — 2026-08-25T16:21:01Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5413398474)

Try [0.5.0-beta.1](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-beta.1) and tell me if it works!

### lunarephemera — 2026-08-27T11:21:34Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5438245132)

Tested 0.5.0-beta.1 against the same hardware (ZD Ultimate Legend, 413D:2104). Good news first: detection and handshake both work now, which they didn't in the pre-beta build. But there's a regression that breaks the record probe and, from the app's Console log, the real pipeline too.

**CLI record probe**

```
RECORD identity="Controller 413d:2104" vid=16701 pid=8452 driver=Xbox360 interface=0 in=0x81 out=0x1 configuration=current profile_startup=none usb_startup=01 03 06
USB_MATCHES count=1
USB_DEVICE service=4295047396 location=51380224
USB_STRING product=XBOX 360 For Windows
USB_OPEN interface=0 route=ioUSBHost result=opened
RECORD_HANDSHAKE driver=Xbox360 result=complete
ERROR: record probe failed: The operation couldn't be completed. (OpenJoystickDriverKit.USBTransportError error 5.)
```

Error 5 is `.notSupported`. It happens right after the handshake completes, i.e. while sending the `01 03 06` player-1 LED packet.

**Root cause, I think**

Both `ControllerRecordProbeRunner.sendStartupPackets` and `USBPipeline.isIgnorableUSBStartupOutputError` only forgive this specific rejection when `error.isInputOutput`:

```swift
catch let error as USBTransportError
  where parser is Xbox360Parser && packet == [0x01, 0x03, 0x06] && error.isInputOutput
```

Under the old libusb-backed transport, this pad's LED-set rejection surfaced as an IO error, so it got swallowed here. Under the new IOUSBHostTransport, the same rejection surfaces as `kIOReturnUnsupported`/`kIOReturnBadArgument`, which maps to `.notSupported` — not `.isInputOutput` — so the guard no longer matches and the error propagates instead of being ignored.

**App behavior (Console.app, filtered to OJD)**

Same failure signature in the real pipeline, looping continuously:

```
[DeviceManager] USB device added: XBOX 360 For Windows (DeviceIdentifier(VID:0x413D PID:0x2104 loc=51380224))
[DevicePipeline] Handshake failed for DeviceIdentifier(VID:0x413D PID:0x2104 loc=51380224): notFound
... (repeats)
[DevicePipeline] Controller sleeping after idle: DeviceIdentifier(VID:0x413D PID:0x2104 loc=51380224)
```

Note the app logs `notFound` rather than `notSupported` — possibly a different failure point, or the error gets remapped somewhere in the pipeline vs. the CLI path. Menu bar icon blinks roughly once a minute, and macOS's own Controllers system pane lists the pad and forwards "Identify" rumble requests to OJD's virtual device (visible in Console as repeated "App rumble report"), but nothing reaches the hardware since the real handshake never completes on that path.

Controller identity in Controllers pane: tried all four options (Generic HID, Xbox One HID, SDL2/3, Apple GameController), same result under each.

Happy to test a patch or run more diagnostics. macOS 26.6.0, MacBook Pro (Apple Silicon)

### xsyetopz — 2026-08-27T12:37:58Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5439243062)

Alright, patch coming up. I really should probably create a Discord specifically to share temporary patch builds... Or something.

### xsyetopz — 2026-08-27T12:53:44Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5439420564)

> Alright, patch coming up. I really should probably create a Discord specifically to share temporary patch builds... Or something.

https://discord.gg/zdaRa9zy5c meanwhile patch is on the way.

### lunarephemera — 2026-08-27T17:21:24Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5442711879)

### Update: remaining `0.5.0-beta.2` failure localized to `IOUSBHost copyPipe()` on OUT endpoint `0x01`

I managed to localize the remaining failure more precisely.

**Version confirmed:**
- Checkout: `192c926`
- Tag: `0.5.0-beta.2`
- Installed app: `0.5.0-beta.2`

**What is working:**
- Controller is detected
- USB device is matched
- `IOUSBHost` opens interface `0`
- Xbox 360 handshake completes successfully

The normal probe reaches:

```text
USB_OPEN interface=0 route=ioUSBHost result=opened
RECORD_HANDSHAKE driver=Xbox360 result=complete
```

I added temporary logging around the `IOUSBHost` transfer path to determine the exact failure point.

The failure happens **before any input read**.

It occurs when the Xbox 360 startup packet `01 03 06` is about to be sent through OUT endpoint `0x01`.

The debug output is:

```text
DEBUG transfer start endpoint=1
DEBUG copyPipe failed endpoint=1 raw=Error Domain=IOUSBHostErrorDomain Code=-536870160 "Unable to copy pipe." UserInfo={NSLocalizedRecoverySuggestion=Select a valid endpoint address, NSLocalizedDescription=Unable to copy pipe., NSLocalizedFailureReason=Endpoint address not found.} mapped=notFound
ERROR: record probe failed: The operation couldn’t be completed. (OpenJoystickDriverKit.USBTransportError error 5.)
```

So the failure is specifically happening here:

```swift
interface.copyPipe(withAddress: Int(endpoint))
```

for endpoint `0x01`.

`IOUSBHost` reports:

```text
Unable to copy pipe.
Endpoint address not found.
```

and OJD maps that error to:

```text
USBTransportError.notFound
```

This also appears to explain why the GUI was previously showing:

```text
Handshake failed ... notFound
```

The important detail is that the beta.2 startup-output ignore helper currently handles:

```swift
case .inputOutput, .notSupported:
    return true
```

but the actual error returned on my controller/Mac is `.notFound`.

So the beta.2 `.notSupported` fix does not catch this case.

At this point, the remaining issue appears to be:

> `IOUSBHost` cannot resolve the OUT pipe for endpoint `0x01` on this controller/interface, and the resulting `.notFound` escapes when OJD tries to send the Xbox 360 startup packet `01 03 06`.

If useful, I can test a patch that also treats `.notFound` as ignorable for this specific Xbox 360 startup packet, or run any additional diagnostics you want.

### lunarephemera — 2026-08-29T10:40:16Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5461854120)

After the latest patch, USB open, handshake, and startup output all succeed. Here's what each virtual output mode actually does on this hardware (ZD Ultimate Legend, 413D:2104, macOS 26.6.0, Apple Silicon).

---

**Generic HID** — detected as "OJD Generic"

Steam Test Device Inputs: mostly works, with occasional dropped button events.
Games: no response.
Vibration: not tested yet.

This is the most functional mode right now. Input physically reaches Steam, buttons and sticks are read correctly most of the time.

---

**SDL2/3** — detected as "ASTRO C40 TR"

Steam Test Device Inputs: works, but:
- buttons are remapped to PlayStation layout
- both sticks are inverted on Y axis (in addition to the hardware inversion already applied by Xbox360Parser)
- identity is obviously wrong

Games: no response.
Vibration: not tested yet.

Input does reach Steam through this path. The inversion is likely a double-negation: Xbox360Parser correctly negates Y on parse, but SDL's ASTRO C40 TR mapping also flips Y, so they cancel each other in the wrong direction. Mapping is Sony-style throughout.

---

**Xbox One HID** — detected as "Xbox One S Controller" (045E:02EA)

Steam Test Device Inputs: no button or stick events.
Games: no response.
Vibration: not tested yet.

The virtual device is visible and registered. Steam sees it as a real Xbox One S and likely uses a direct XInput/GIP path rather than HID, so OJD's HID report format doesn't reach it.

---

**Apple GameController** — also detected as "Xbox One S Controller"

Behavior identical to Xbox One HID: device exists, zero input events in Steam.

---

**One interesting observation across all modes:**

When the physical controller is disconnected, games show a controller-disconnected notification — so connection state does reach them. Only gameplay input doesn't.

---

**Vibration note:**

The output endpoint `0x01` failure was only fixed in the latest patch. Vibration hasn't been tested since then. Happy to test it now if you want that data before moving on.

---

Summary: Generic HID is the only mode delivering actual input to Steam right now (after steam input layout setup). SDL2/3 delivers input but with wrong identity and doubled Y inversion. Xbox One HID and Apple GameController register cleanly but deliver nothing. The gap between "Steam sees it" and "games respond" appears to be the XInput/direct-input layer that Generic HID can't satisfy.

### lunarephemera — 2026-08-29T11:04:56Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5461971769)

Update on virtual output modes:

Apple GameController works in Hotline Miami 2 — both with and without Steam Input forced on. Other modes (Generic HID, SDL2/3, Xbox One HID) are not detected by that game at all.

Cyberpunk 2077 does not detect the controller in any mode. Since CP2077 on Mac uses the Apple GameController framework directly (bypassing Steam Input), and Hotline Miami 2 works fine through that same path, the difference is probably somewhere in how CP2077 filters or enumerates controllers — not in OJD's virtual device itself.

Polling rate measured at 1000 Hz current / 375 Hz effective, jitter 0.19 ms, through Generic HID mode (screenshot attached if useful).

Happy to test specific scenarios in either game.

Tried launching CP2077 with controller already connected, and connecting after launch — neither works. Since Apple GameController mode uses 045E:02EA (Xbox One S VID/PID), the issue might be that OJD registers as GCExtendedGamepad rather than GCXboxGamepad specifically. CP2077 may filter on the subclass.


Comparison: Windows shows 8029 Hz max / 5575 Hz effective on the same controller in the same XInput mode. macOS through OJD shows 1004 Hz max / 375 Hz effective. The gap suggests Windows driver requests a different USB transfer interval — possibly the controller supports multiple polling modes and only switches to the fast one when the driver asks. Worth checking if IOUSBHost allows requesting a shorter bInterval at open time.
