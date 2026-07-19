# #9: Xbox 360 wireless not work

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/9
- **State:** OPEN
- **Author:** jonasw8
- **Created:** 2026-06-09T07:59:30Z
- **Updated:** 2026-07-19T07:11:36Z
- **Closed:** —
- **Labels:** enhancement, help wanted

## Report

Hi Sir!

I have a Xbox360 wireless joystick. This app doesn't work with it.
Would it bepossible add support for this?

## Comments

### xsyetopz — 2026-06-09T08:58:33Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/9#issuecomment-4658127909)

> Hi Sir!
>
> I have a Xbox360 wireless joystick. This app doesn't work with it. Would it bepossible add support for this?

If you could capture the data needed for wireless connectivity, let alone the Xbox Wireless Adapter (which X360 controllers need AFAIK), I could give it a try on the next incoming alpha build, so that y'could test it out.

I can try to dig out as much as there is for both by the linux kernel, but that's mostly about as far as I can go without a physical adapter myself. I do own a legitimate X360 controller from 2010, though...

### xsyetopz — 2026-06-09T09:18:25Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/9#issuecomment-4658291712)

UPDATE: I'm going to order a wireless receiver from eBay China, which's going to take a while before I can try myself. In the meantime, I need y'to follow the documentation for how to retrieve the necessary feed needed to support your device.

### xsyetopz — 2026-07-12T16:59:47Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/9#issuecomment-4952011304)

> UPDATE: I'm going to order a wireless receiver from eBay China, which's going to take a while before I can try myself. In the meantime, I need y'to follow the documentation for how to retrieve the necessary feed needed to support your device.

The receiver still hasn't arrived to me... Yikes...

### jonasw8 — 2026-07-19T00:43:07Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/9#issuecomment-5013552916)

jonas@192 OpenJoystickDriver-main % ./scripts/ojd diagnose record   Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-0719.json   --validate-only
[1/1] Planning build
Building for debugging...
ld: warning: building for macOS-10.15, but linking with dylib '/usr/local/opt/libusb/lib/libusb-1.0.0.dylib' which was built for newer version 14.0
[107/107] Applying OpenJoystickDriverHIDTool
Build of product 'OpenJoystickDriverHIDTool' complete! (14.52s)
RECORD identity="Controller 045e:0719" vid=1118 pid=1817 driver=Xbox360 interface=0 in=0x81 out=0x1 configuration=current startup=none
RECORD_VALIDATION result=valid
jonas@192 OpenJoystickDriver-main %

### jonasw8 — 2026-07-19T00:45:58Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/9#issuecomment-5013561880)

jonas@192 OpenJoystickDriver-main % ./scripts/ojd diagnose record   Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-0719.json   --seconds 45
[1/1] Planning build
Building for debugging...
[1/1] Write swift-version--58304C5D6DBC2206.txt
Build of product 'OpenJoystickDriverHIDTool' complete! (1.24s)
RECORD identity="Controller 045e:0719" vid=1118 pid=1817 driver=Xbox360 interface=0 in=0x81 out=0x1 configuration=current startup=none
USB_MATCHES count=1
USB_DEVICE bus=20 address=4 class=0xff subclass=0xff protocol=0xff

💣 Program crashed: Bad pointer dereference at 0x000000000000007f

Thread 1 crashed:

0 0x000000010535c3fb usbi_log + 161 in libusb-1.0.0.dylib
1 0x000000010535d258 libusb_open + 63 in libusb-1.0.0.dylib
2 USBDevice.getStringDescriptor(index:langID:) + 264 in OpenJoystickDriverHIDTool at /Users/jonas/Desktop/OpenJoystickDriver-main/.build/checkouts/SwiftUSB/Sources/SwiftUSB/USBDevice.swift:145:22

   143│   public func getStringDescriptor(index: Int, langID: UInt16? = nil) throws -> String {
   144│     var handle: OpaquePointer?
   145│     let openResult = libusb_open(device, &handle)
      │                      ▲
   146│     try USBError.check(openResult)
   147│     guard let h = handle else {

3 USBDevice.getManufacturer() + 80 in OpenJoystickDriverHIDTool at /Users/jonas/Desktop/OpenJoystickDriver-main/.build/checkouts/SwiftUSB/Sources/SwiftUSB/USBDevice.swift:168:16

   166│   public func getManufacturer() throws -> String {
   167│     guard iManufacturer > 0 else { throw USBError(message: "No manufacturer string descriptor") }
   168│     return try getStringDescriptor(index: Int(iManufacturer))
      │                ▲
   169│   }
   170│

4 closure #1 in runControllerRecordProbe(recordPath:seconds:detachKernel:validateOnly:) + 3851 in OpenJoystickDriverHIDTool at /Users/jonas/Desktop/OpenJoystickDriver-main/Sources/OpenJoystickDriverHIDTool/ControllerRecordProbeRunner.swift:56:41

    54│           + " protocol=\(hex(device.deviceProtocol))"
    55│       )
    56│       if let manufacturer = try? device.getManufacturer() {
      │                                         ▲
    57│         print("USB_STRING manufacturer=\(manufacturer)")
    58│       }

Backtrace took 1.10s

zsh: segmentation fault  ./scripts/ojd diagnose record  --seconds 45
jonas@192 OpenJoystickDriver-main %

### xsyetopz — 2026-07-19T07:11:36Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/9#issuecomment-5014818761)

> jonas@192 OpenJoystickDriver-main % ./scripts/ojd diagnose record Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-0719.json --validate-only [1/1] Planning build Building for debugging... ld: warning: building for macOS-10.15, but linking with dylib '/usr/local/opt/libusb/lib/libusb-1.0.0.dylib' which was built for newer version 14.0 [107/107] Applying OpenJoystickDriverHIDTool Build of product 'OpenJoystickDriverHIDTool' complete! (14.52s) RECORD identity="Controller 045e:0719" vid=1118 pid=1817 driver=Xbox360 interface=0 in=0x81 out=0x1 configuration=current startup=none RECORD_VALIDATION result=valid jonas@192 OpenJoystickDriver-main %

Interesting...
