# 8BitDo Ultimate C Wired (2DC8:2027): Linux usbmon against the OJD GIP session start

Task 3.1. The capture is from issue #59 (reporter `nightmare2122`): `ultimate_c_2dc8_2027_linux_usbmon.zip`, Fedora 43, kernel 7.2.11, `xpad`. It was fetched on 2026-11-11 from `https://github.com/user-attachments/files/34325373/ultimate_c_2dc8_2027_linux_usbmon.zip` (40,681 bytes, sha256 `c7e8ba2a2e0cc8dc1f29f71fcfc80e79b98c327349134ade4afed3dbb198abee`) into `/tmp/ojd-59-usbmon/`, unpacked there, and read only as data with a script that parses the pcap bytes (no tool or file from the archive was executed). The pcap is copied beside this file: `ultimate_c_xpad_linux.pcap` (313,323 bytes, sha256 `1f6788f1217263b61ea9a0ad8aefe84e07c4248d952a650b12a906b61a481afd`, link type 220 `USB_LINUX_MMAPPED`, 3,206 packets, bus 3: the root hub, address 0 during enumeration, and the controller at address 5).

Source of each fact: **observed** = parsed from the pcap in this session; **read** = source line in this worktree; **reported** = the issue text; **inferred** = a reading that no capture shows.

## 1. What Linux sends before the first input packet (observed)

The first input-side packet from the pad is frame 56, `03 20 01 04 80 00 00 00` (a status packet, 7.0 ms after the first OUT is submitted). Times are seconds from the first packet of the capture (frame 18); `S` is a submission and `C` a completion.

Control transfers to the controller (address 5) that are OUT (host to device):

| Frame | Time | Transfer | Bytes |
| --- | --- | --- | --- |
| 46 | 0.1613 | SET_CONFIGURATION, `bmRequestType 00`, `bRequest 09`, `wValue 1` | setup `00 09 01 00 00 00 00 00` |
| 49 | 0.1628 | SET_INTERFACE, `bmRequestType 01`, `bRequest 0B`, `wValue 0` (alternate 0), `wIndex 1` (interface 1) | setup `01 0b 00 00 01 00 00 00` |

Interrupt OUT transfers on endpoint 0x02 (all three are submitted before the pad answers; the first IN data completes at frame 56 while the third OUT is still in flight):

| Frame | Time | Length | Bytes | Gap from the one before |
| --- | --- | --- | --- | --- |
| 51 | 0.1643 | 5 | `05 20 00 01 00` (power on) | 1.5 ms after SET_INTERFACE |
| 53 | 0.1673 | 7 | `0a 20 01 03 00 01 14` (LED on) | 3.0 ms |
| 55 | 0.1713 | 6 | `06 20 02 02 01 00` (auth done) | 4.0 ms |

Other facts of the same stretch (observed):

- No other control OUT and no other interrupt OUT go to the controller in the whole capture (the three OUTs above are the only OUT interrupt submissions in 3,206 packets). No SET_FEATURE (remote wakeup) and no CLEAR_FEATURE go to the controller.
- Before SET_CONFIGURATION the host reads the device descriptor (18 bytes), asks for the device qualifier three times (each stalls, status -32), reads the configuration descriptor (9 then 64 bytes) and the string descriptors (language, product, vendor, serial). These are all IN transfers.
- One interrupt IN read on endpoint 0x81 (64 bytes) is already pending from frame 48, between SET_CONFIGURATION and SET_INTERFACE, before any OUT is written.
- The controller sends no announce packet (`02 20 ...`). Its first packets are `03 20 01 04 80 00 00 00` (frame 56), then `20 00 01 20 ...` input (frame 59, 36 bytes) and a second status `03 20 04 04 80 00 00 00` (frame 61). The capture holds 1,575 IN transfers with data in total.
- On the hub (address 1) the host does the usual port work (PORT_RESET `SET_FEATURE`, `CLEAR_FEATURE` of the change bits, `GET_STATUS`). These go to the hub, not the controller.
- `lsusb.txt` (in the reporter's archive): 1 configuration of 2 interfaces. Interface 0, class FF/47/D0, interrupt IN 0x81 and OUT 0x02, interval 4. Interface 1, alternate 0 has no endpoint and alternate 1 has isochronous 0x03 OUT and 0x83 IN. `bmAttributes 0xa0` (remote wakeup), `MaxPower 500mA`.

## 2. What OJD sends at GIP session start (read)

`2DC8:2027` has no bundled record (no `2dc8-2027*` file under `Sources/`). The report in #59 shows OJD listing it as Xbox One (GIP), so it binds by the family's interface signature FF/47/D0, interface 0 (`Resources/Protocols/xbox-gip.json:13-21`). Order of events:

1. **SET_CONFIGURATION 1**, only when the device is not already in configuration 1. A GIP signature binding sets `needsSetConfiguration: true` (`ProtocolDriverRegistry.swift:107-119`, comment at 110-112). `OpenOptions` carries configuration value 1 then (`USBTransport.swift:197-203`), and `setsConfiguration(current:)` skips it when `kUSBCurrentConfiguration` already equals 1 (`USBTransport.swift:214-217`; the read is at `IOUSBHostTransport.swift:205-215`). The send is `IOUSBHostDevice.__configure(withValue: 1, matchInterfaces: true)` (`IOUSBHostTransport.swift:217-228`).
2. **Interface claim**: wait up to 20 x 50 ms for the interface service (`IOUSBHostTransport.swift:230-241`, used at line 36), then open `IOUSBHostInterface` for `options.interfaceNumber`, 0 for this binding (`IOUSBHostTransport.swift:44-58`; the default profile is interface 0, alternate 0 at `TransportProfiles.swift:73-77`). The alternate setting is selected only when it is not 0 (`IOUSBHostTransport.swift:54-56`), so OJD sends **no SET_INTERFACE** here. Interface 1 is never opened.
3. **Record control transfers**: `performControlTransfers` runs the mode's vendor control transfers (`DevicePipeline+USBSession.swift:14-50`, called at `DevicePipeline+USBStartup.swift:222`). A recordless GIP binding has none, so none are sent.
4. **Three interrupt OUT writes** to endpoint 0x02 (`xbox-gip.json:6-9`, out 2), from `GIPDriver.startupWrites()` (`GIPDriver.swift:157-168`, startup chosen at `GIPDriver.swift:115-125`), sent by `sendUSBStartupOutputPackets` (`DevicePipeline+USBStartup.swift:297-331`) in the order of the description (`xbox-gip.json:49-59`), 50 ms apart (`usbStartupIntervalMs 50`, `xbox-gip.json:116`; the wait is at `DevicePipeline+USBStartup.swift:305-312`), each with a 2,000 ms timeout (`xbox-gip.json:118`):

   | Order | Packet id | Template bytes | Line in `xbox-gip.json` | Bytes after the sequence byte is stamped |
   | --- | --- | --- | --- | --- |
   | 1 | `XboxGIP/power-on` | `05 20 00 01 00` | 73-76 | `05 20 01 01 00` |
   | 2 | `XboxGIP/led-on` | `0A 20 00 03 00 01 14` | 93-96 | `0A 20 02 03 00 01 14` |
   | 3 | `XboxGIP/auth-done` | `06 20 00 02 01 00` | 98-101 | `06 20 01 02 01 00` |

   The stamped value is derived by reading `GIPSequencer.next` (`Sequencer.swift:24-29`, first value 1; system messages share counter 0, authenticate has its own counter, `Sequencer.swift:33-39`), and byte index 2 is replaced at `RecordStartupWrite.swift:216`. I did not run it.
5. **Player indicator**: `usbStartupWrites()` appends the assigned player indicator (`DevicePipeline+USBStartup.swift:270-275`), but `GIPDriver.encode` throws for every command except rumble (`GIPDriver.swift:353-365`), so `assignedPlayerIndicatorWrites()` returns nothing (`DevicePipeline+USBStartup.swift:280-288`). Nothing more is written.
6. **Handshake attempts**: up to 3 attempts of 2 to 5 (`handshakeAttempts 3`, `xbox-gip.json:60`; loop at `DevicePipeline+USBStartup.swift:217-242`, zero delay between attempts, `GIPDriver.swift:144-153`). A failed write retries the whole sequence; none failed in the report (the log in #59 says "Handshake complete").
7. **First IN read**: only after the handshake returns (`DevicePipeline+USBStartup.swift:144`, loop body `DevicePipeline+USBInputLoop.swift:25-40`), on endpoint 0x81 (`xbox-gip.json:7`, in 130).
8. **After that, still before any input if the pad is silent**: an announce packet (`02 20 ...`) makes OJD resend the three startup packets, on the first announce and every fourth after it, up to `announceResendLimit` 8 (`GIPDriver.swift:290-296, 322-332`; `xbox-gip.json:61`). A keep-alive `03 20 <seq> 03 00 00 00` goes out every 4,000 ms, first after one interval (`xbox-gip.json:62-70`; timer `DevicePipeline+USBInputLoop.swift:118-129`). Auth messages are answered in `GIPDriver.swift:313-316`.

## 3. Side by side

| Step | Linux `xpad` (observed) | OJD (read) | Same? |
| --- | --- | --- | --- |
| SET_CONFIGURATION 1 | Sent at 0.1613 | Sent only if `kUSBCurrentConfiguration` is not 1, through `IOUSBHostDevice` | Same request; conditional on OJD's side |
| SET_INTERFACE interface 1, alternate 0 | Sent 1.5 ms later | Never sent (alternate 0 is not selected, interface 1 is not opened) | **Differs** |
| Interfaces held open | Interface 0 bound to `xpad`; interface 1 is listed as `3-1:1.1 -> driver` (`lsusb.txt:106-107`), a name the file does not resolve. Which side issued the SET_INTERFACE is inferred, not shown | Interface 0 only | **Differs** for interface 1 |
| IN read pending before the OUTs | Yes, one 64-byte read on 0x81 from frame 48 | No; the first IN read starts after the three OUT writes | **Differs** |
| First OUT | `05 20 00 01 00` | `05 20 01 01 00` | Same except sequence byte (0 against 1) |
| Second OUT | `0a 20 01 03 00 01 14` | `0A 20 02 03 00 01 14` | Same except sequence byte (1 against 2) |
| Third OUT | `06 20 02 02 01 00` | `06 20 01 02 01 00` | Same except sequence byte (2 against 1) |
| Endpoint of the OUTs | 0x02 | 0x02 | Same |
| Spacing of the OUTs | 3.0 ms and 4.0 ms | 50 ms each | **Differs** |
| Time from SET_CONFIGURATION to the first OUT | 3.0 ms | Not measured here; includes waiting for the interface service (poll 50 ms, up to 1 s) and the open | Differs (inferred, the reporter tried 32 ms and still saw nothing) |
| Other control OUTs, SET_FEATURE | None | None for a recordless binding | Same |
| Pad's first packet | `03 20 01 04 80 00 00 00`, no announce | Not reported; "Frames in the window: 0" | n/a |
| Writes after the pad is silent | None in the capture | Resend of the three on an announce; keep-alive `03 20 ..` every 4 s | OJD sends more |

The three OUT payloads are the same except for the sequence byte, so the bytes are not what separates the two. What does separate them, as read: the missing SET_INTERFACE on interface 1, the order of the IN read against the OUT writes, and the 50 ms spacing. The reporter already tried the first on macOS with libusb (with and without SET_INTERFACE, packets sent 1 s or 10 s late, 32 ms after SET_CONFIGURATION), all with no data, so none of these three is shown to be the cause. The reporter's report that the light goes dark at SET_CONFIGURATION (before any packet) is a cause no OJD write explains (reported).

## 4. What this leaves for task 3.2 and 3.4

- A test of "a pad that sends input and no announce packet" cannot be failed by the bytes alone; it has to fail on what the session does first. Candidates from the table: IN read armed before the OUT writes; SET_INTERFACE for the alternate-0 interface that has no endpoint.
- Not shown by this capture (needs the Mac): what macOS itself sends during enumeration. The reporter notes that no USB capture is available on that Mac without turning off SIP (reported).
- The capture has no stick click and one change on byte 18 (README in the archive); it is no input-layout evidence for a record.
