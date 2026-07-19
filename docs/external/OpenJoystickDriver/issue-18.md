# #18: Original Xbox One controller (model 1537, 045E:02D1) falls back to genericHID — request GIP profile

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/18
- **State:** OPEN
- **Author:** cooltune
- **Created:** 2026-07-18T19:56:50Z
- **Updated:** 2026-07-19T01:17:45Z
- **Closed:** —
- **Labels:** enhancement, help wanted

## Report

### Summary

The original wired Xbox One controller (model 1537, `045E:02D1`) is detected by the daemon but falls back to `protocol=genericHID` with `mappings=none`, so no input is parsed. Since this is a vendor-class (0xFF) GIP device, the generic HID path can't drive it. Could a GIP profile for it be included in the next release?

### Environment

- OpenJoystickDriver 0.5.0-alpha.4 (DMG from releases), user-space virtual device mode, `sdl2-3` identity
- macOS 26.5.2, Apple Silicon (M2)
- Controller connected via USB-C hub; also reproduced on a direct port

### Observed

`--headless list` (daemon running, Input Monitoring granted):

```
Controller (VID:1118 PID:721 GenericHID [USB] SN:7EED828A0937)
  protocol=genericHID endpoints=in:0x82 out:0x2 setConfig=false settleMs=0
  mappings=none backends=driverKitHID,userSpaceHID
```

USB descriptor (from `ioreg`): `bDeviceClass=255`, VID `0x045E`, PID `0x02D1`, in-endpoint `0x82`, out-endpoint `0x02` — same shape as the Xbox One S profile that ships in the bundle.

### Notes

- `main` already has a review-candidate record for this device (`Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-02d1.json`, added in 98b7b0e, `driver: GIP`, `variant: xboxOne`, provenance linux-xpad), but no full controller-profile JSON ships in the alpha.4 bundle, so the daemon has nothing to match.
- On Linux xpad this device uses the standard GIP power-on init; it predates the One S so it presumably needs the classic init without `xboxOneSInit`.

### Proposed profile (derived from `microsoft-xbox-one-s-controller.json`)

```json
{
  "profile_version": "1.0.0",
  "identity": {
    "vendor_id": 1118,
    "product_id": 721,
    "name": "Microsoft Xbox One Controller (1537)",
    "short_name": "XboxOne1537"
  },
  "input": {
    "transport": "usb",
    "usb": {
      "class": 255,
      "interface": 0,
      "endpoints": { "in": 130, "out": 2 }
    }
  },
  "protocol": {
    "driver": "GIP",
    "variant": "xboxOne",
    "startup_packets": ["powerOn", "ledOn", "authDone"]
  },
  "output": {
    "virtual_profile": "xboxOneS",
    "preferred_backends": ["driverKitHID", "userSpaceHID"]
  },
  "provenance": { "source": "linux-xpad.c", "hardware_verified": false }
}
```

I couldn't test this profile locally — adding it to the signed bundle understandably trips signature enforcement, and building from source isn't an option on this machine right now.

### Offer

I have the physical controller and I'm happy to test a build or the next alpha on real hardware and report back (input, rumble, LED).

## Comments

### xsyetopz — 2026-07-18T21:59:06Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/18#issuecomment-5013083316)

Roger that. Working on it!

### cooltune — 2026-07-19T00:54:40Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/18#issuecomment-5013587546)

Hardware result from the model 1537 (`045e:02d1`), as requested. TL;DR: **the GIP protocol path fully works on this controller** — handshake, LED, every button/axis full-range, guide button, and rumble all verified — but I had to bypass two record/transport issues to get there. Details below.

### Environment

- macOS 26.5.2, Apple Silicon (M2), controller behind a USB-C hub
- Source build of `main` (70c7b6c), probe run via a minimal IOUSBHost harness replaying OJD's exact GIP packets (`powerOn`, `ledOn`, `authDone`, `rumbleBegin`/`rumbleEnd` from `GIPStartupPacket.swift`) — reason for not using `ojd diagnose record` directly is item 3 below

### ✅ What works (all physically verified)

- **Handshake**: `powerOn` → `ledOn` → `authDone` accepted; Xbox LED goes **solid**; controller replies with an announce frame:
  ```
  RX announce len=32: 02 20 f2 1c 7e ed 82 8a 09 37 00 00 5e 04 d1 02 01 00 01 00 90 01 06 00 01 00 01 00 01 00 01 00
  ```
- **Input**: 1,817 deduplicated `0x20` input frames over a 45 s capture. All 14 buttons observed (A/B/X/Y, LB/RB, D-pad ×4, Menu, View, both stick clicks); triggers full 10-bit range 0–1023; all four stick axes full range −32768…32767. Sample frame:
  ```
  RX input len=18: 20 00 05 0e 00 00 00 00 00 00 51 09 2d f7 2c 04 34 fc
  ```
- **Guide button**: arrives as `0x07` virtual-key frames (press/release):
  ```
  07 20 01 02 01 5b
  07 20 02 02 00 5b
  ```
- **Rumble**: `rumbleBegin` (`09 00 seq 09 00 0f 00 00 1d 1d ff 00 00`) produced a clear physical pulse; `rumbleEnd` stopped it.

### Findings for the catalog record / transport

1. **Endpoints in the record are wrong for this model.** `045e-02d1` derives `in=0x82 out=0x02`; the actual interrupt endpoints on interface 0 are **`in=0x81 out=0x01`** (`copyPipeWithAddress` fails for 0x82/0x02, succeeds for 0x81/0x01).
2. **The record needs `set1-before-claim`.** With no kernel driver claiming class-FF devices, the 1537 sits **unconfigured** on macOS (libusb debug: `active config: 0, first config: 1`). Everything works after `SetConfiguration(1)` — same treatment as the Flydigi Vader 5S record.
3. **libusb cannot open this device on macOS 26 / Apple Silicon** — `libusb_open` returns `LIBUSB_ERROR_NO_DEVICE` even with the device free, configured, and run as root; with `LIBUSB_DEBUG=4`, the failure path segfaults inside `usbi_log` (Homebrew libusb built for macOS 26 linked into a macOS 11-target binary — the string-descriptor reads in `ControllerRecordProbeRunner` crash the same way). Chrome and Steam both drive this controller via IOUSBHost on the same machine, which is how I ran the capture. You may want an IOUSBHost fallback (or pinned/vendored libusb) for the raw-USB path on newer macOS; happy to share the ~150-line IOUSBHost probe source if useful.

So with endpoints corrected to `0x81/0x01` + `set1-before-claim`, the `045e-02d1` record can be flipped to `verified: true` as far as protocol behavior goes — the remaining gap on this machine is only the libusb open path. Glad to re-test any build or record change on the hardware.

### cooltune — 2026-07-19T01:12:24Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/18#issuecomment-5013634891)

One usability addendum from further testing: the 0.5.0-alpha.4 daemon opens the matched USB device **exclusively** (AppleUSBHostDeviceUserClient) even when it has no usable record/parser for it — for the 1537 this means the daemon holds the controller while parsing nothing, and blocks any other client (Steam Input, Chrome's Gamepad API, or diagnostic tools) from reaching it. Consider only claiming exclusively once a record resolves to a supported protocol, or releasing the device when the parser falls back to genericHID with no mappings.

### cooltune — 2026-07-19T01:17:45Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/18#issuecomment-5013648391)

As offered — the minimal IOUSBHost probe used for the hardware report above, in case it helps with an IOUSBHost transport fallback. Four API details that cost us debugging time:

1. **Interrupt pipes reject completion timeouts** — `sendIORequestWithData` returns `kIOReturnBadArgument` for any nonzero `completionTimeout` on interrupt endpoints; pass `0`.
2. **IO buffers must come from `-[IOUSBHostInterface ioDataWithCapacity:error:]`** — plain `NSMutableData` also yields `kIOReturnBadArgument` (and the returned buffer's length must not be modified).
3. **`configureWithValue:matchInterfaces:` needs `matchInterfaces:YES`** or no `IOUSBHostInterface` services are ever published.
4. **Find interface 0 by iterating the device's registry children** (`IORegistryEntryCreateIterator` + `bInterfaceNumber` property) — property-dictionary matching on `IOUSBHostInterface` didn't match for this device.

<details><summary>usbgip.m (probe source)</summary>

```objc
// usbgip: GIP hardware probe for Xbox One controller 045e:02d1 via IOUSBHost.
// Mirrors OpenJoystickDriver's startup sequence (powerOn, ledOn, authDone) and
// rumbleBegin/rumbleEnd packets so results are comparable with its GIP driver.
#import <Foundation/Foundation.h>
#import <IOUSBHost/IOUSBHost.h>

static NSTimeInterval t0;
static void hexdump(const char *tag, const uint8_t *b, NSUInteger n) {
  char buf[3 * 64 + 1] = {0};
  NSUInteger m = n > 64 ? 64 : n;
  for (NSUInteger i = 0; i < m; i++) sprintf(buf + i * 3, "%02x ", b[i]);
  printf("%8.3f %s len=%lu: %s\n",
         [NSDate timeIntervalSinceReferenceDate] - t0, tag, (unsigned long)n, buf);
  fflush(stdout);
}
static NSTimeInterval t0;

static IOUSBHostInterface *gIntf;
static BOOL sendPacket(IOUSBHostPipe *out, const uint8_t *bytes, NSUInteger len,
                       const char *name) {
  NSMutableData *d = [gIntf ioDataWithCapacity:len error:nil];
  memcpy(d.mutableBytes, bytes, len);
  NSError *err = nil;
  NSUInteger sent = 0;
  BOOL ok = [out sendIORequestWithData:d
                      bytesTransferred:&sent
                     completionTimeout:0
                                 error:&err];
  printf("%8.3f TX %-12s %s (%lu bytes)\n",
         [NSDate timeIntervalSinceReferenceDate] - t0, name,
         ok ? "ok" : err.description.UTF8String, (unsigned long)sent);
  fflush(stdout);
  return ok;
}

int main(int argc, char **argv) {
  @autoreleasepool {
    double seconds = argc > 1 ? atof(argv[1]) : 45.0;
    t0 = [NSDate timeIntervalSinceReferenceDate];

    NSDictionary *match = @{
      @"IOProviderClass" : @"IOUSBHostDevice",
      @"idVendor" : @0x045e,
      @"idProduct" : @0x02d1,
    };
    io_service_t service = IOServiceGetMatchingService(
        kIOMainPortDefault, (__bridge_retained CFDictionaryRef)match);
    if (!service) { fprintf(stderr, "ENUM device not found\n"); return 1; }
    printf("ENUM device found (045e:02d1)\n");

    NSError *err = nil;
    IOUSBHostDevice *dev = [[IOUSBHostDevice alloc] initWithIOService:service
        options:0 queue:nil error:&err interestHandler:nil];
    if (!dev) { fprintf(stderr, "OPEN failed: %s\n", err.description.UTF8String); return 2; }
    printf("OPEN ok\n");

    if (![dev configureWithValue:1 matchInterfaces:YES error:&err]) {
      fprintf(stderr, "CONFIGURE failed: %s\n", err.description.UTF8String);
      return 3;
    }
    printf("CONFIGURE value=1 ok\n");

    io_service_t iservice = 0;
    for (int attempt = 0; attempt < 20 && !iservice; attempt++) {
      io_iterator_t iter = 0;
      if (IORegistryEntryCreateIterator(service, kIOServicePlane,
                                        kIORegistryIterateRecursively,
                                        &iter) == KERN_SUCCESS) {
        io_service_t child;
        while ((child = IOIteratorNext(iter))) {
          if (IOObjectConformsTo(child, "IOUSBHostInterface")) {
            CFTypeRef num = IORegistryEntryCreateCFProperty(
                child, CFSTR("bInterfaceNumber"), kCFAllocatorDefault, 0);
            int ifnum = -1;
            if (num) {
              CFNumberGetValue((CFNumberRef)num, kCFNumberIntType, &ifnum);
              CFRelease(num);
            }
            if (ifnum == 0) {
              iservice = child;
              break;
            }
          }
          IOObjectRelease(child);
        }
        IOObjectRelease(iter);
      }
      if (!iservice) usleep(100000);
    }
    if (!iservice) { fprintf(stderr, "INTERFACE 0 not found\n"); return 4; }
    IOUSBHostInterface *intf = [[IOUSBHostInterface alloc] initWithIOService:iservice
        options:0 queue:nil error:&err interestHandler:nil];
    if (!intf) { fprintf(stderr, "CLAIM failed: %s\n", err.description.UTF8String); return 5; }
    printf("CLAIM interface=0 ok\n");
    gIntf = intf;

    uint8_t inAddr = 0x82, outAddr = 0x02;
    IOUSBHostPipe *inPipe = [intf copyPipeWithAddress:inAddr error:&err];
    IOUSBHostPipe *outPipe = [intf copyPipeWithAddress:outAddr error:&err];
    if (!inPipe || !outPipe) {
      inAddr = 0x81; outAddr = 0x01;
      inPipe = [intf copyPipeWithAddress:inAddr error:&err];
      outPipe = [intf copyPipeWithAddress:outAddr error:&err];
    }
    if (!inPipe || !outPipe) {
      fprintf(stderr, "PIPES failed: %s\n", err.description.UTF8String);
      return 6;
    }
    printf("PIPES in=0x%02x out=0x%02x ok\n", inAddr, outAddr);

    // Startup sequence, sequence numbers as OJD sends them (1-based).
    uint8_t powerOn[] = {0x05, 0x20, 0x01, 0x01, 0x00};
    uint8_t ledOn[]   = {0x0a, 0x20, 0x02, 0x03, 0x00, 0x01, 0x14};
    uint8_t authDone[] = {0x06, 0x20, 0x03, 0x02, 0x01, 0x00};
    sendPacket(outPipe, powerOn, sizeof powerOn, "powerOn");
    sendPacket(outPipe, ledOn, sizeof ledOn, "ledOn");
    sendPacket(outPipe, authDone, sizeof authDone, "authDone");
    printf("HANDSHAKE complete — press buttons now\n");
    fflush(stdout);

    NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + seconds;
    int rumbled = 0;
    uint64_t total = 0, inputReports = 0;
    uint8_t prev[64] = {0};
    NSUInteger prevLen = 0;

    while ([NSDate timeIntervalSinceReferenceDate] < deadline) {
      NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
      if (rumbled == 0 && now - t0 > seconds / 2) {
        uint8_t rb[] = {0x09, 0x00, 0x10, 0x09, 0x00, 0x0f, 0x00, 0x00,
                        0x1d, 0x1d, 0xff, 0x00, 0x00};
        sendPacket(outPipe, rb, sizeof rb, "rumbleBegin");
        rumbled = 1;
      }
      if (rumbled == 1 && now - t0 > seconds / 2 + 2.0 && rumbled != 2) {
        uint8_t re[] = {0x09, 0x00, 0x11, 0x09, 0x00, 0x0f, 0x00, 0x00,
                        0x00, 0x00, 0x00, 0x00, 0x00};
        sendPacket(outPipe, re, sizeof re, "rumbleEnd");
        rumbled = 2;
      }
      NSMutableData *buf = [intf ioDataWithCapacity:64 error:nil];
      NSUInteger got = 0;
      NSError *rerr = nil;
      BOOL ok = [inPipe sendIORequestWithData:buf bytesTransferred:&got
                            completionTimeout:0 error:&rerr];
      if (!ok || got == 0) continue;
      total++;
      const uint8_t *b = buf.bytes;
      if (b[0] == 0x20) inputReports++;
      // Dedupe: skip if identical to previous ignoring the sequence byte [2].
      uint8_t cur[64];
      memcpy(cur, b, got);
      if (got > 2) cur[2] = 0;
      if (got == prevLen && memcmp(cur, prev, got) == 0) continue;
      memcpy(prev, cur, got);
      prevLen = got;
      const char *tag = b[0] == 0x20   ? "RX input "
                        : b[0] == 0x07 ? "RX xbox-btn"
                        : b[0] == 0x02 ? "RX announce"
                        : b[0] == 0x03 ? "RX keepalive"
                                       : "RX other";
      hexdump(tag, b, got);
    }
    printf("SUMMARY packets=%llu input_reports=%llu\n", total, inputReports);
    return inputReports > 0 ? 0 : 7;
  }
}
```
</details>
