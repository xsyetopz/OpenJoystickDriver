# #21: Nacon Revolution X Pro (3285:0634): add GIP profile and investigate USB disconnects

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/21
- **State:** OPEN
- **Author:** TanelLaas
- **Created:** 2026-07-22T18:40:00Z
- **Updated:** 2026-07-22T20:17:17Z
- **Closed:** —
- **Labels:** enhancement, help wanted

## Report

### Summary

Please add a GIP profile for the wired Nacon Revolution X Pro / NC7270
(`3285:0634`). With the correct interface and endpoints, current `main` can send
the standard three-packet GIP startup sequence and parse real input from this
controller. The remaining native-driver problem is an unstable USB session:
OpenJoystickDriver commonly reaches `LIBUSB_ERROR_IO`, `PIPE`, `NOT_FOUND`, or
`NO_DEVICE` shortly after the handshake.

I have the physical controller and can test focused builds. I also have a local
profile, stream decoder, protocol tests, and a working WebUSB reference path.

### Environment

- macOS 26.4.1 (`25E253`), Apple Silicon (`arm64`)
- Direct USB-C to USB-C connection
- OpenJoystickDriver `main` at `6ea7e80`, plus a local NC7270 profile
- The same controller is stable on Windows

### USB profile

```text
Product:       Nacon Revolution X
VID:PID:       3285:0634 (12933:1588 decimal)
Device class:  0xff
Subclass:      0x47
Protocol:      0xd0
Interface:     0
Interrupt IN:  0x87
Interrupt OUT: 0x07
Configuration: current (no set-before-claim needed in the successful probe)
```

The minimal local record is:

```json
{
  "vendor_id": 12933,
  "product_id": 1588,
  "transport": "usb",
  "protocol": {
    "driver": "GIP",
    "variant": "xboxOne"
  },
  "usb": {
    "endpoints": {
      "in": 135,
      "out": 7
    }
  },
  "provenance": {
    "source": "local-hardware",
    "verified": true
  }
}
```

### Hardware-verified GIP behavior

These three packets wake the controller and turn the LEDs on:

```text
05 20 01 01 00
0a 20 02 03 00 01 14
06 20 03 02 01 00
```

A focused OJD record probe then captured 56 packets, produced four normalized
input events, and reported zero parse errors. Examples:

```text
20 00 02 20 00 00 00 00 00 00 00 00 00 00 00 00 ...
02 20 55 1c d2 0f 89 66 ba 2a 00 00 85 32 34 06 ...
03 20 77 04 80 00 00 00
```

Buttons, triggers, and all four analog axes are also live through a separate
WebUSB implementation using the same startup sequence. That implementation:

- keeps one interrupt read pending;
- treats `0x01` as ACK, `0x02` as announce, and `0x03` as status;
- decodes split and stacked GIP frames with base-128 payload lengths;
- acknowledges only frames whose options request an ACK; and
- sends no periodic host-side `0x03` packet.

### Native OJD failure

One clean run from current source produced:

```text
[GIPParser] Init sequence sent (attempt 1) outEP=0x7
[DevicePipeline] Handshake complete: ... VID:0x3285 PID:0x0634 ...
[DevicePipeline] Starting USB input loop: ... inEP=0x87
[DevicePipeline] Keep-alive failed ... LIBUSB_ERROR_NO_DEVICE
[DevicePipeline] Device disconnected ...
[DevicePipeline] Input loop ended ...
```

Other runs reach `LIBUSB_ERROR_IO`, followed by `PIPE`, `NOT_FOUND`, or
`NO_DEVICE`. This makes the keep-alive suspicious, not conclusively the sole
cause: the current libusb read/reconnect path may also be involved. The wire
capture does confirm that this controller itself emits command `0x03` as a
status frame; it does not need a synthetic host-side `0x03` every four seconds
in the working implementation.

### Suggested scope

1. Add the `3285:0634` controller record with `0x87/0x07` endpoints.
2. Make host-side keep-alive behavior profile-specific and disable it for this
   device rather than removing it globally; wireless GIP still needs separate
   validation.
3. Correct the GIP command identities (`0x01` ACK, `0x02` announce, `0x03`
   status) and handle split/stacked frames plus requested ACKs.
4. Retest through the signed user-space virtual-gamepad output path.

I can split the existing local work into small PRs after you confirm the desired
boundary: record first, then framing/ACK handling, then keep-alive policy.

## Comments

### TanelLaas — 2026-07-22T18:42:52Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/21#issuecomment-5050058238)

### Working workaround: direct WebUSB bridge into GeForce NOW

We now have a fully working workaround that may also be useful as a protocol
reference: a small unpacked Brave/Chrome extension connects to the NC7270 with
WebUSB and exposes it directly to the GeForce NOW web client as a standard Xbox
360 gamepad.

This bypasses the macOS virtual-HID/signing problem completely:

```text
NC7270 USB
  -> Chromium WebUSB
  -> GIP startup/read/ACK bridge in the GFN page
  -> navigator.getGamepads() standard Xbox gamepad
  -> GeForce NOW web client
```

There is no keyboard translation, native virtual device, login item, service
worker, or standalone daemon. The USB read loop exists only inside the open
`play.geforcenow.com` tab.

#### What the bridge does

1. Requests only `3285:0634`, opens configuration 1 if necessary, claims
   interface 0, and uses interrupt endpoints `0x87/0x07`.
2. Arms the first interrupt read before startup. If the controller is already
   producing data it does not restart it; otherwise it sends the three verified
   startup packets.
3. Maintains one continuous input read, decodes base-128 GIP lengths across
   split/stacked USB transfers, and dynamically ACKs only requested frames.
4. Maps command `0x20` input plus `0x07` guide events to an 18-button,
   four-axis standard Gamepad object with real analog triggers and sticks.
5. Runs at `document_start` and automatically reopens an already-authorized
   controller after a GFN navigation or USB reconnect.

The injected gamepad identity is:

```text
Xbox 360 Controller (STANDARD GAMEPAD Vendor: 045e Product: 028e)
mapping=standard, buttons=18, axes=4
```

The navigation behavior mattered. Our first live proof was a temporary page
injection; it worked, then vanished when GFN navigated from its catalog to a
game page. Packaging the same code as a `document_start` content script and
reconnecting through `navigator.usb.getDevices()` made it survive that boundary.

#### Physical result

- USB chooser selects **Revolution X** once.
- Startup turns the controller LEDs on.
- The bridge reaches **Input live** after the first `0x20` report.
- Buttons, both triggers, and both sticks arrive as real Gamepad API values.
- The GFN browser client accepts the synthetic standard gamepad directly.
- Moving the controller no longer kills this path; no periodic host-side
  `0x03` packet is sent.

#### Validation

- 6/6 JavaScript tests pass, including startup bytes, split/stacked/extended
  GIP framing, dynamic ACK construction, analog mapping, guide state, and
  authorized-device reconnect without reopening the chooser.
- 30/30 independent Swift protocol/report checks pass.
- The live controller has been verified through Brave with GeForce NOW.

Current limitation: this targets the Chromium GFN web client, not NVIDIA's
native macOS app, because it deliberately avoids publishing a system-wide
virtual controller. I can publish the reference extension separately or extract
its protocol fixtures into focused OJD tests if useful.

### xsyetopz — 2026-07-22T18:48:29Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/21#issuecomment-5050122378)

Oo la laaaa. Interesting. Never thought somebody thought of NVIDIA app. This will be useful for the next 0.5.0-* release that's been in hard work for a while.

### TanelLaas — 2026-07-22T19:46:45Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/21#issuecomment-5050718999)

Just to avoid confusion, the working WebUSB workaround is only for the GFN browser client in Brave/Chrome. It doesn’t modify or inject anything into NVIDIA’s native macOS app :/ That route still needs OJD’s signed virtual-gamepad output.
The useful bits for OJD 0.5 are the NC7270 profile/endpoints, GIP framing + ACK behaviour, and the keepalive findings which was the most annoying part of it all.
I tried building a native bridge first, but the macOS signing/entitlement stuff made it not worth chasing just for a quick game :P

### xsyetopz — 2026-07-22T19:59:36Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/21#issuecomment-5050845406)

> Just to avoid confusion, the working WebUSB workaround is only for the GFN browser client in Brave/Chrome. It doesn’t modify or inject anything into NVIDIA’s native macOS app :/ That route still needs OJD’s signed virtual-gamepad output. The useful bits for OJD 0.5 are the NC7270 profile/endpoints, GIP framing + ACK behaviour, and the keepalive findings which was the most annoying part of it all. I tried building a native bridge first, but the macOS signing/entitlement stuff made it not worth chasing just for a quick game :P

macOS is a genuine b%%ch here. I'm still trying to see how much I can to do reduce the signing/entitlement buls%%t. I'll install NVIDIA app myself to try it out, too.

### xsyetopz — 2026-07-22T20:16:26Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/21#issuecomment-5051010108)

It's quite interesting how many users of macOS happen to actually find this application. All because I went from Windows/Linux to macOS && my GameSir G7 SE didn't work...

"See a need, fill a need!" -- Bigweld, Robots (2005)

Should I consider setting up a community discord for my projects, or is GitHub enough?
