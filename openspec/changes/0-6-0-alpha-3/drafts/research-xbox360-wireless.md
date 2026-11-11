# Research: Xbox 360 wireless receiver and RF module (issue #9)

Research only. No code changed, nothing built, nothing posted. Read on 2026-11-11 against repo HEAD `1d69a2981`.

Every fact below is in my own words. GPL and unlicensed sources were read in full to learn behaviour; none of their code or structure is reproduced. The "Verdict" column compares the fact with our code: **agrees**, **extends** (we lack it, no conflict) or **contradicts**.

## 1. Sources and licenses

| Id | Source | License (from `gh api repos/.../license`, or file header) | Read? |
| --- | --- | --- | --- |
| XP | Linux `drivers/input/joystick/xpad.c`, blob at commit `2e6f2e5799f3` (last commit touching the file; matches master on 2026-11-11). <https://github.com/torvalds/linux/blob/2e6f2e5799f328ca0879dad14d7f3709c7f7496b/drivers/input/joystick/xpad.c> | GPL-2.0-or-later (SPDX line 1 of the file) | Yes, relevant parts |
| 360C | 360Controller (macOS kext), commit `d6290c7969dd`. <https://github.com/360Controller/360Controller>, folders `WirelessGamingReceiver/` and `Wireless360Controller/` | GPL-2.0 (file headers: v2 or later) | Yes |
| BR | nabekhan/X360MacOSReceiverBridge, commit `38d28d84a6cd`, the repo linked in issue #9. <https://github.com/nabekhan/X360MacOSReceiverBridge> | GPL-2.0 | Yes: `src/protocol.cpp`, `include/x360bridge/protocol.hpp`, `src/receiver.cpp`, `docs/RESEARCH.md` |
| X36 | zeromiyi/x360w (cited by PR #54). <https://github.com/zeromiyi/x360w>, `src/x360w.c`, `README.md` | MIT | Yes |
| XR | agarmash/Xreceiver (fat console RF). <https://github.com/agarmash/Xreceiver>, `Xreceiver13.c`, `README.md` | None declared (license API returns 404): all rights reserved. Behaviour only | Yes (source, README). Blog <https://agarmash.com/posts/xbox-360-controller-receiver/> read through a summarising fetch only |
| RB | robot9706/Xbox360RFController (RF over a serial port). <https://github.com/robot9706/Xbox360RFController>, `README.md`, `ATTiny85_Code/ATTiny85_Code.ino`, `Xbox360RFModuleSerial/MainForm.cs` | `LICENSE.md`: free use, but the author's name must be included (GitHub reports NOASSERTION). Behaviour only | Yes |
| SL | ginokgx/xbox360slimRF (slim RF). <https://github.com/ginokgx/xbox360slimRF>, `README.md`, `XboxSlimRfReceiver.ino` | None declared. Behaviour only | Source and README yes; `Scheme.png` and `Sync.gif` (pin diagram, sync animation) **not read** |
| OG | orsinium-labs/gamepad. <https://github.com/orsinium-labs/gamepad> | MIT | Yes, but irrelevant: it is a Go wrapper over the OS joystick API (`/dev/input/js*`, Windows joystick), so it holds no USB, receiver or RF facts. Its button order is the Linux `js` mapping, not the wire format |
| ISS | Issue #9 and its comments, <https://github.com/xsyetopz/OpenJoystickDriver/issues/9>; PR #54, <https://github.com/xsyetopz/OpenJoystickDriver/pull/54> | Project's own | Yes |

**Could not read:** the tkkrlab RF module wiki (the page the RB UI links; `http://tkkrlab.nl/wiki/XBOX_360_RF_Module` redirects to tkkrlab.com, which returned 404); the blog's pin diagram and the astrorats posts it cites; Microsoft's receiver USB descriptors and the Windows `xusb` INF; any real descriptor dump of a receiver or RF module. So the interface numbering per slot and the RF module's own VID/PID are unverified.

## 2. Our code, as read

- Driver: `Sources/OpenJoystickDriverKit/Protocol/Drivers/Xbox/XUSBDriver.swift`. Receiver decode at `:274-286`; wired decode at `:300-322`; length check at `:302`.
- Description: `Resources/Protocols/xbox-xusb.plist`. Presence inquiry `:20-35`, receiver rumble `:43-70`, signatures `:110-132`. It has no `receiverPowerOff`. The tests say this is deliberate until hardware checks pass (`Tests/OpenJoystickDriverKitTests/Protocol/Drivers/Xbox/XUSBDriverTests+PowerOff.swift:7-8`).
- Receiver variant and slots: `Sources/OpenJoystickDriverKit/Protocol/Catalog/ProtocolDriverRegistry.swift:251-271` and `ProtocolDriverRegistry+InterfaceContract.swift:5-57`.
- Records: `Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-0291.plist`, `045e-02a9.plist`, `045e-0719.plist`. Each is `XboxXUSB` / `Receiver`, with no overrides. (`Resources/Controllers/` has no `045E/` folder; the 045e records live under `Sources/.../Resources/Controllers/045e/`.)
- Fixture: `Tests/ProtocolPacketFixtures/ProtocolPacketFixtures.swift:331-352`.

## 3. Facts

### 3.1 Receiver identity

| # | Fact | Source (URL, file:line) | Verdict vs ours |
| --- | --- | --- | --- |
| F1 | Three Microsoft-VID receiver PIDs are known: 0x0291 "Xbox 360 Wireless Receiver (XBOX)", 0x02A9 "Unofficial" (the clone), 0x0719 "Xbox 360 Wireless Receiver" (the later official). All are the wireless-receiver type. | XP `xpad.c:125,126,131` (GPL-2.0+); 360C `WirelessGamingReceiver/Info.plist` (decimal 1817=0719 "ForWindows", 657=0291 "Alternate", 681=02A9 "AlternateAlternate") (GPL-2.0); BR `src/receiver.cpp:216-219` (GPL-2.0); X36 `src/x360w.c:20` (MIT) | **Agrees**: `045e-0719.plist`, `045e-0291.plist`, `045e-02a9.plist` all bind `XboxXUSB:Receiver`. |
| F2 | Clones other than 02A9 exist: xpad matches the wireless interface signature for every listed vendor, not only 045E (for example a "BETOP wireless dongles" vendor entry). 360C and BR match 045E only. | XP `xpad.c:489-493` (macro adds proto 129 per vendor), `:555`; BR `src/receiver.cpp:216-219` | **Agrees**: the signature binding at `xbox-xusb.plist:122-131` catches an unknown VID with FF/5D/81. **Unverified:** a clone with a different wire protocol behind the same descriptor (BR lists this as a falsifier, `docs/RESEARCH.md`, "What would falsify the approach"). 02A9 is now hardware-tested twice (PR #54 body; issue comment by Presum0, which saw the same 29-byte packets), so 02A9 is the same protocol. |
| F3 | xpad invents the product ID 0x02A1 for the input device of a paired wireless pad ("controller and receiver have different ids"). That ID is not on the USB bus. | XP `xpad.c:1960-1963` | **Extends**, no action: do not add a 02A1 record. Useful only if a game keys on that ID for the virtual pad. |
| F4 | xpad also classifies an unlisted device as a receiver when its vendor-specific interface has protocol 129. | XP `xpad.c:2106` | **Agrees** with the signature binding (`xbox-xusb.plist:122-131`). |

### 3.2 Interfaces and endpoints per slot

| # | Fact | Source | Verdict |
| --- | --- | --- | --- |
| F5 | A receiver has four pad interfaces: class 0xFF, subclass 0x5D, protocol 0x81 (129). Each has one interrupt IN and one interrupt OUT endpoint, and each carries one slot. | XP `xpad.c:2137-2150` (takes the first two endpoints, one IN, one OUT); 360C `WirelessGamingReceiver.cpp:125-152`, `WIRELESS_CONNECTIONS` = 4 at `WirelessGamingReceiver.h:30`; BR `src/receiver.cpp:22-24,35-95` | **Agrees**: `ProtocolDriverRegistry+InterfaceContract.swift:5,11-13,45-57` (FF/5D/81, one IN and one OUT, four roles, ordered by interface number); `xbox-xusb.plist:122-131`. |
| F6 | A second family of interfaces, protocol 130 (0x82), sits beside the pad interfaces, one per slot. 360C opens them but never uses them (comment "a mystery"). It is presumably the headset/audio path. xpad and BR ignore them. | 360C `WirelessGamingReceiver.cpp:153-180` | **Agrees**: our contract admits only proto 129 (`InterfaceContract.swift:11`), so proto 130 is not claimed. **Unverified:** that 130 is the headset path; no source decodes it. |
| F7 | Measured on real hardware (0719 and 02A9): slot 0 is interface 0, IN 0x81, OUT 0x01. The endpoint addresses of slots 1-3 and the interface numbers (for example 0,2,4,6 against 0,1,2,3) are not in any source I could read. | ISS: jonasw8's `RECORD ... interface=0 in=0x81 out=0x1`; lzpfmh ("USB interface 0 / IN 0x81 / OUT 0x01"); PR #54 body ("interface 0, input endpoint 81, output endpoint 01") | **Agrees** for slot 0 (`xbox-xusb.plist:101-107`). Other slots: our code reads the endpoints from the observed descriptor (`InterfaceContract.swift:60-` `roleProfile`), so it needs no table. Dump `system_profiler SPUSBDataType` plus a descriptor dump once to record it. |
| F8 | Claiming order: the config is set once; claiming later interfaces after another SET_CONFIGURATION would drop the earlier ones. 360C sets configuration once, then opens all interfaces. | 360C `WirelessGamingReceiver.cpp:64-79` | **Agrees**: `InterfaceContract.swift:15-16` (roles after the first leave SET_CONFIGURATION out). |

### 3.3 Link, connect and disconnect packets

| # | Fact | Source | Verdict |
| --- | --- | --- | --- |
| F9 | Host sends a 12-byte "presence inquiry" to each slot's OUT endpoint at start: `08 00 0F C0` then zeros. It makes the receiver replay its connection state, which matters when the receiver was already plugged in with a paired pad. | XP `xpad.c:1464-1480` (bytes at `:1471-1474`), `:1860-1880` | **Agrees**: `xbox-xusb.plist:22-33`, sent from `XUSBDriver.swift:244-246,289-297`. Real run: `USB_TX ... 08 00 0f c0 ...` then `USB_RX len=2 08 80` (ISS, lzpfmh). |
| F10 | xpad arms the IN read first and then sends the inquiry, so no reply is missed. | XP `xpad.c:1860-1880` | **Differs mildly**: `XUSBDriver.swift:237-246` notes OJD sends during the handshake before its first read, so the reply can be lost. Harmless in practice, since a valid pad report also connects the slot (`:284`) and the real run showed `08 80` arriving. |
| F11 | Presence/status packet is 2 bytes: byte 0 has bit 3 set (value 0x08); byte 1 bit 7 = pad present, bit 6 = headset present; byte 1 of 0x00 means gone. Observed on hardware: `08 80`. | XP `xpad.c:1013-1026` (comment `:1003-1011`); BR `src/protocol.cpp:45-50`; X36 `src/x360w.c:131-133`; 360C `WirelessGamingReceiver.cpp:441-443` | **Agrees**: `XUSBDriver.swift:278-281`. |
| F12 | 360C treats `08 xx` with any non-zero byte 1 as connected. xpad, BR and X36 test bit 7. So a headset-only `08 40` is "connected" to 360C and "disconnected" to the others. | 360C `:441-443`; XP `:1018-1020` | **Contradicts** 360C only; ours is with xpad (`XUSBDriver.swift:279`). Our fixture `presenceConnectedWithHeadset` = `08 C0` (`ProtocolPacketFixtures.swift:337-338`) covers pad+headset only. Headset-only is untested. |
| F13 | Connect also arrives as other packet types. 360C publishes the pad only after it sees a packet whose byte 1 is 0x0F (the "initial info" packet), not on presence alone. | 360C `WirelessGamingReceiver.cpp:466-483,500-513` | **Extends**: we connect on a presence packet or the first valid pad packet (`XUSBDriver.swift:278-285`). Not a conflict; our rule is the xpad rule. |
| F14 | The "initial info" packet (29 bytes, byte 1 = 0x0F) carries a 4-byte pad serial at bytes 10-13 and, when byte 16 is 0x13, a battery value at byte 17. A type-0 packet whose byte 3 is 0x13 carries the battery value at byte 4. | 360C `Wireless360Controller` base `WirelessHIDDevice.cpp:183-231` (cases at `:192-194,207-212,226`) | **Extends**: we read neither serial nor battery. A serial would give a stable per-pad identity for slot naming. Unverified on any capture we hold. |
| F15 | Real traffic holds idle packets too: lzpfmh counted 127 non-input reports starting `00 00 00 F0 00 00` among 1,171 state reports. Byte 1 = 0 routes them to 360C's "info update" handler (keyed on byte 3 = 0xF0, unhandled there). Meaning is unknown. | ISS lzpfmh comment 2; 360C `WirelessHIDDevice.cpp:212-214` | **Agrees**: ours drops them (`XUSBDriver.swift:282`, byte 1 is not 0x01) without a connect. Needs a test with the real bytes so it stays that way. |

### 3.4 Input report layout

| # | Fact | Source | Verdict |
| --- | --- | --- | --- |
| F16 | Pad data packet = 4-byte envelope (`00 01 00 F0` observed), then the Xbox 360 report. Byte 1 = 0x01 marks pad data; 360C also requires byte 3 = 0xF0. The report starts at envelope byte 4. | XP `xpad.c:1028-1037`; BR `src/protocol.cpp:52-62`; 360C `WirelessHIDDevice.cpp:207-209`; capture in ISS (lzpfmh): `00 01 00 F0 00 13 00 00 00 00 2C E2 EC FC B4 EB CA 05 00 ...` (29 bytes) | **Agrees** on envelope and offset (`XUSBDriver.swift:282-283`). |
| F17 | **The inner length byte of a wireless report is 0x13, not the wired 0x14.** Only byte 0 (= 0x00) is checked by xpad's shared decoder, so xpad, BR and X36 accept it. 360C reads byte 5 as the report length (0x13) and passes it on. The wired path in xpad does not check a length byte either. | XP `xpad.c:887-888` (only `data[0]` checked); BR `src/protocol.cpp:60`; 360C `WirelessHIDDevice.cpp:208-209`; hardware: ISS lzpfmh (0719: 1,171 of 1,171 state packets have `00 13`), PR #54 body (02A9: "inner header `00 13`"), Presum0 (02A9, 29-byte packets, no state) | **Contradicts** our code: `XUSBDriver.swift:283` passes the stripped payload to `decodeWired`, whose `:302` demands byte 1 == 0x14. Every real receiver report is rejected before decode. Still true at HEAD. Our fixture hides it: `ProtocolPacketFixtures.swift:346` sets the receiver pad report's length byte to 0x14 (invented from the wired layout), so `XUSBDriverTests+Receiver.swift` never saw a real packet. |
| F18 | Field layout after the envelope matches wired: buttons in two bytes (low: D-pad bits 0-3, Start 4, Back 5, L3 6, R3 7; high: LB 0, RB 1, Guide 2, A 4, B 5, X 6, Y 7), triggers at bytes 4-5, sticks as four little-endian signed words from byte 6. Hardware masks observed: A/B/X/Y `1000/2000/4000/8000`, LB/RB `0100/0200`, Back/Start `0020/0010`, L3/R3 `0040/0080`, Guide `0400`, D-pad `1,2,4,8` and diagonals, sticks +-32768 / 32767, triggers 0-255. | XP `xpad.c:895-955`; BR `src/protocol.cpp:64-91`; ISS lzpfmh table | **Agrees**: `XUSBDriver.swift:58-79,300-329`. |
| F19 | Packets are 29 bytes on the bus but the state fields end at envelope byte 17; BR requires only 18 bytes. | BR `src/protocol.cpp:55-57`; `docs/RESEARCH.md` "Receiver protocol research" | **Differs mildly**: we require 24 (`XUSBDriver.swift:282`). Fine for real 29-byte packets; PR #54 lowers it to 18. |
| F20 | The y-axis is up-positive in the device report. | XP `xpad.c:~942-950` (negates with a bitwise not) | **Agrees**: `XUSBDriver.swift:318-319`. |

### 3.5 LED, rumble, power-off

| # | Fact | Source | Verdict |
| --- | --- | --- | --- |
| F21 | Ring LED on a paired pad: 12-byte write `00 00 08 (0x40 + pattern)`, rest zero. Patterns 0-15: off, all blink, flash-then-hold for players 1-4, steady players 1-4 (6-9), rotate, blink, slow blink, two-light rotate, slow all-blink, blink once then restore. | XP `xpad.c:1655-1700` (comment `:1655-1672`, bytes `:1695-1696`); BR `src/protocol.cpp:141-145`; X36 `src/x360w.c:76`; 360C `WirelessHIDDevice.cpp:52` | **Agrees**: `XUSBDriver.swift:14-48,369-372`. Hardware: none yet; lzpfmh tested rumble only. |
| F22 | 360C takes the pattern modulo 14, so pattern 14 becomes 0 and 15 becomes 1. The others use the low nibble or the full range. | 360C `WirelessHIDDevice.cpp:52` | **Differs**: ours uses the raw value (`:371`) and only ever sends 0 or 6-9 (`:387-394`). No impact. |
| F23 | After an LED change, and once at start, 360C sends one extra 12-byte packet `00 00 00 40 ...` ("weird start", purpose unknown). xpad does not. | 360C `WirelessHIDDevice.cpp:35,53-57,152` | **Extends**: we send none. Test on hardware whether the LED needs it. Not needed on the three captures that worked. |
| F24 | Rumble: 12-byte write `00 01 0F C0 00 <large motor> <small motor>` and zeros. Byte 5 = strong/low-frequency, byte 6 = weak/high-frequency. | XP `xpad.c:1583-1597`; BR `src/protocol.cpp:147-151`; 360C `Wireless360Controller.cpp:341` | **Agrees**: `xbox-xusb.plist:49-60` (low byte 5, high byte 6). **Hardware-verified** by lzpfmh on 0719: left 160 gave `00 01 0F C0 00 A0 ...`, right gave `... 00 00 A0`; both felt and both stopped. |
| F25 | Power-off: 12-byte write `00 00 08 C0` and zeros. xpad sends it on Guide held 5 s, and on suspend/unplug unless disabled. 360C sends it after 15 minutes without input, and on a host output report with id 0x02. Pads otherwise stay on and flash. | XP `xpad.c:66,957-969,1833-1853,2267-2282`; BR `src/protocol.cpp:153-156`; 360C `WirelessHIDDevice.cpp:29,43,70,87-92` | **Agrees** on the bytes with the code path (`XUSBDriver.swift:218-227`), but the bundled description carries none, so nothing is sent (`xbox-xusb.plist` has no `receiverPowerOff`; `XUSBDriverTests+PowerOff.swift:7-8`). **Extends** with the two idle/Guide policies, which we lack. Not yet hardware-tested by anyone. |
| F26 | The inquiry and power-off share a `?? 0F C0` / `?? C0` tail; the pad slot ignores writes while no pad is present. | XP `xpad.c:1471-1474,1842-1843` (same tail) | **Agrees**: we hold output until a pad connects (`XUSBDriver.swift:199-206`, `requiresInputConnectionBeforeOutput`). |

### 3.6 Headset and chatpad

| # | Fact | Source | Verdict |
| --- | --- | --- | --- |
| F27 | Headset presence is only a flag in the status byte (bit 6). No source decodes the audio stream. The wireless chatpad is not handled by any of the macOS or Linux sources. 360C's `ChatPad.cpp` serves wired pads over a serial port, not the receiver. | XP `xpad.c:1003-1011`; BR `include/x360bridge/protocol.hpp:44-50`; X36 `src/x360w.c:50,133`; 360C `360Controller/ChatPad.cpp` (GPL-2.0) | **Extends**: we ignore the headset bit, but our fixture treats `08 C0` as connected (`ProtocolPacketFixtures.swift:337-338`). No need to claim proto-130 interfaces. |

### 3.7 RF module: bus, sync, LEDs, what a DIY board shows on USB

| # | Fact | Source | Verdict |
| --- | --- | --- | --- |
| F28 | The console RF module has two interfaces: USB for pad traffic and a separate low-speed clocked control line for its own ring LED and for sync. USB needs 3.3 V, ground and the data pair. Connected to a PC it "works exactly like the official wireless receiver"; the blog says its PID differs from the official one but gives no value (**not read**). Previously synced pads reconnect with the control line left unconnected (the author did not test this). | <https://agarmash.com/posts/xbox-360-controller-receiver/> (summarising fetch; unlicensed prose) | **Extends / unverified**: nothing in our code is needed for a DIY board beyond the three PIDs of F1, provided it enumerates as FF/5D/81. Open: the real PID and descriptors. |
| F29 | Fat module: pin 5 power button/sync, pin 6 data (host writes), pin 7 clock (module drives, about 340 Hz). 3.3 V logic. Common ground needed. A plain 12 V RS-232 port can destroy it. | RB `README.md:8-20`; SL `XboxSlimRfReceiver.ino:1-3` (same pin numbers for slim) | **Extends**: out of scope for the driver. |
| F30 | Command framing (fat): idle data line high; host pulls data low to start, then puts one bit on the line after each clock edge; 2 leading zero bits then an 8-bit command, MSB first; line released high at the end. Xreceiver clocks 11 cycles (the 11th a zero), robot9706 clocks 10. | XR `Xreceiver13.c:20-49`; RB `ATTiny85_Code.ino:25-37`, `MainForm.cs:113-148` | **Extends**. |
| F31 | Command bytes (after the 2 zero bits): 0x84 = init module and light the centre LED; 0x04 = start sync; 0x09 = tell all pads to turn off; 0x80 = LED off; 0x85 = boot animation; 0x88/0x89 = init/animation without power LED; 0x8C/0x8D = same with blinking power LED; 0xA0\|g = green LEDs 1-4 as a 4-bit mask; 0xB0\|r = red LEDs; 0xC0 = clear error; 0xC1-0xC5 = red blink (all, 1-4); 0xD1-0xD5 = fast red blink; 0xEF = all amber. Wait about 2 s (RB) to 3.5 s (XR) after power-up before the first command. Sync = short press (under 0.8 s) of the button; long press = turn pads off. | RB `MainForm.cs:155-276` (command comments), `ATTiny85_Code.ino:8-9`; XR `Xreceiver13.c:61-96` | **Extends**. This is the ring on the module itself; it is not the pad's ring (F21), which goes over USB. |
| F32 | Slim module: same bus and pins, but sync only works if the host sends an 11-bit frame with a final 1, waits about 1 ms after each clock edge before driving data, and sends a start command first (0x12) and the boot animation (0x85) so the sync animation shows. USB side is said to "need the wireless receiver driver" like old modules. | SL `README.md:11-15`, `XboxSlimRfReceiver.ino:5-27,48-53,66-75`; blog states slim and E modules use a different bus | **Extends**. Same open point as F28: presents as a receiver. |

## 4. What blocks issue #9

1. **The decoder bug (F17), still unfixed on `main` and the alpha.2 build.** Real receiver reports carry inner length 0x13; our receiver path passes them through the wired decoder that demands 0x14 (`XUSBDriver.swift:283,302`). All three reporters see no input (Presum0 on beta.4, lzpfmh on alpha.2, jonasw8's silent crash path). Fix exists in open PR #54 (drops the length check for the receiver, accepts 18 bytes, connects on valid input); lzpfmh posted an independent equivalent patch with 1,171/1,171 reports accepted. Task `8.7` is open, the PR is not rebased, and the fixture `ProtocolPacketFixtures.swift:346` still uses 0x14.
2. **Publication to games needs the HID virtual-device entitlement.** PR #54's hardware run got "Missing entitlement: com.apple.developer.hid.virtual.device". Tester builds need a provisioned profile; the maintainer wrote on the issue that this waits on Apple provisioning. Input decode and rumble are not blocked by it.
3. **Reporter retest.** `dispositions.md:12` says "Waiting on reporter". The 0719 report (lzpfmh) and 02A9 report (bdidier) both hold real captures, so no further capture is needed for decode.
4. **jonasw8's diagnostic crash** (`./scripts/ojd diagnose record ... --seconds 45`): a null-ish dereference inside libusb's `usbi_log` called from `libusb_open`, reached via `USBDevice.getStringDescriptor` (SwiftUSB) from `ControllerRecordProbeRunner.swift:56` per the pasted trace; an Intel Mac using a Homebrew libusb built for a newer macOS. Not in decode path, but it blocks that reporter's self-service capture. Read from the issue; I did not reproduce it.

Not blocking: the lack of a receiver on the maintainer's desk. The decode fix, the connect/disconnect state and the output bytes can all be tested without one (section 5).

## 5. What a maintainer without a receiver can still test

| Option | Covers | Limits |
| --- | --- | --- |
| **Replay of real captures** into `XUSBDriver` (a unit test with the 29-byte packet from lzpfmh and the `08 80` presence packet), and, end to end, `ojd virtual feed` as lzpfmh did (450 frames, GameController saw 1 controller, 407 input changes) | Decode (F16-F18), connect, disconnect, idle packets (F15), headset-only presence (F12), the slot cap of four, empty-slot hiding (task 8.7) | Cannot test USB claim order, hot-plug, the inquiry reply, rumble or LED effects |
| **A scripted fake receiver** in the existing USB transport test doubles (`Tests/OpenJoystickDriverKitTests/Device/Support/ReceiverSlotDispatcher.swift`, `RecoveryUSBTransport.swift`) that serves four interfaces and plays the captured sequence: inquiry in, `08 80`, 1 s of pad data, `08 00` | Session lifecycle, four slots, replug | Still synthetic |
| **Buy a clone receiver** (the maintainer already ordered one from eBay, per the issue; the cheap ones are the 02A9 "unofficial" type, F1). A 02A9 shares the protocol with 0719 on two third-party captures. | Real USB claim, enumeration, the inquiry, pairing, rumble, LED, power-off, sync with the maintainer's own 2010 pad | A clone does not prove 0719 or 0291 behaviour; the genuine pad needs its pair button pressed after the receiver's sync button |
| **A DIY RF board** (fat module and a microcontroller, or a Wemos for slim) | Same USB view as a receiver (F28), plus the module's LED ring and sync by the control line (F29-F32) | Needs soldering, 3.3 V care, and a spare console module; PID and descriptors unverified; gives nothing the clone does not, except testing sync/pairing from our side, which we do not do |
| **Reporters' captures** via `ojd diagnose record` | The slots 1-3 interface/endpoint table (F7), the proto-130 interfaces, battery and serial packets (F14), LED and power-off effects | jonasw8's tool crash (section 4, item 4) |

My pick: do the replay and fake-receiver tests now, since they hold the one bug that blocks #9, and wait for the clone for the hardware-only rows.

## 6. Facts mapped to open task numbers

Open tasks read from `openspec/changes/0-6-0-alpha-3/tasks.md`. Proposals only; nothing here edits tasks.

| Open task | Facts | Proposal |
| --- | --- | --- |
| `8.7` (rebase PR #54, verify wireless decode and empty-slot hiding for 02A9; line 103) | F16, F17, F19, F15, F12 | Write the failing test first with the real 29-byte packet (`00 01 00 F0 00 13 ...`) in `XUSBDriverTests+Receiver.swift`. Fix the fixture at `ProtocolPacketFixtures.swift:343-351` so the receiver pad report uses the real header and add the real capture as a second fixture. In `XUSBDriver.swift`, check a receiver report by: byte 1 is 0x01, at least 18 bytes, payload byte 0 is 0x00; keep the 0x14 length check for the wired path only (xpad checks neither). Add negative cases: byte 1 of 0x00 (the `00 00 00 F0 00 00` idle packet) gives no event and no connect; a truncated packet gives nothing. |
| `8.7` (same, hardware line) | F7, F9-F11 | Ask bdidier or lzpfmh for the descriptor dump so slots 1-3 get recorded (endpoint table), and a replug trace with `08 00` then `08 80`. |
| New (proposed `8.7a`, in 8.x) | F12 | Decide headset-only presence (`08 40`): keep xpad's rule (disconnected), and say so in a test. |
| New (proposed `8.7b`) | F14, F23 | Optional, after 8.7: read the serial and battery from the initial-info packet, and try the extra `00 00 00 40` packet after an LED write on hardware. Both extend the driver; neither is needed for decode. |
| New (proposed `8.7c`) | F25 | Leave `receiverPowerOff` out of `Resources/Protocols/xbox-xusb.plist` until a receiver run confirms it; the bytes agree with three sources. Then choose a policy: on deliberate stop (present), or also Guide held 5 s (xpad) or 15 minutes idle (360C). |
| New (proposed `8.7d`) | section 4, item 4 | Guard the probe runner's string-descriptor reads (`ControllerRecordProbeRunner.swift:56`) so a failed `libusb_open` skips the string instead of crashing the process. Separate from #9. |
| `9.1`, `9.2` (done) | F2, F4 | No change; the signature binding already covers unknown VIDs with FF/5D/81. Add a clone-VID row to the binding tests only if a real clone VID is captured. |
| `9.18` (read why the classifier stops at an interface contract mismatch) | F5, F6 | A receiver whose descriptor lacks FF/5D/81 with one IN and one OUT endpoint would stop at the contract; the proto-130 interfaces must keep being ignored. |
| `2.x`, `19.3` | none | Unrelated (8BitDo). Listed only to show the 360 receiver has no hardware task of its own yet; add one beside `19.3` once a receiver arrives: slots, rumble, LED, power-off on the release build. |

## 7. Summary of verdicts

- Contradicts: F17 (inner length byte), F12 against 360C only.
- Extends: F13, F14, F22, F23, F25 (idle and Guide policies), F27, F28-F32.
- Agrees: F1, F2, F4, F5, F6, F8, F9, F11, F15, F16, F18, F20, F21, F24, F26.
- Not read: tkkrlab wiki, blog diagrams, slim `Scheme.png` and `Sync.gif`, receiver USB descriptors.
