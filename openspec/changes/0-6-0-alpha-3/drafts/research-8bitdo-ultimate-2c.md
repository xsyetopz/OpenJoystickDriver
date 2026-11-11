# Research: 8BitDo Ultimate 2C from public sources

Draft, research only. No code was changed, built, pushed or posted. Read on 2026-11-11 with `gh api` (read-only) and WebFetch.

Licence handling: GPL and unlicensed sources were read in full to learn behaviour. Every fact below is restated in my own words; no code or code structure is copied. The licence column in each source heading is the repo's own (`gh api repos/<o>/<r>/license`, or the tree listing when the API returned 404).

Our records and docs, cited as `file:line`:

- `docs/testing/8bitdo-ultimate-2c.md` is `DOC`.
- `Resources/Controllers/2DC8/2dc8-<pid>.plist` is `REC-<pid>`.
- `Sources/OpenJoystickDriverKit/Resources/Controllers/2dc8/2dc8-3109.plist` and `2dc8-310a.plist` are `REC-3109` and `REC-310a`. These two are not under `Resources/Controllers/2DC8/`.
- `openspec/changes/0-6-0-alpha-3/tasks.md` is `TASKS`.
- `Tests/OpenJoystickDriverKitTests/Protocol/Drivers/Generic/EightBitDoUltimate2CTests.swift` is `TESTS`.

## 1. Sources and how they were read

| # | Source | Licence | Read? | Relevance to the 2C |
| --- | --- | --- | --- | --- |
| S1 | https://github.com/fwupd/8bitdo-firmware | no licence file; README "Legal Notice" says files are distributed with 8BitDo's permission and LVFS metadata is Richard Hughes's copyright; `8bitdo-firmware.py:4` is GPL-3.0-or-later | read (README, script, tree) | Low. The tree holds only legacy NES30/SNES30/SN30/M30/USB_RR releases (`gh api .../git/trees/HEAD?recursive=1`). No 2C image. |
| S2 | https://github.com/Thoxy67/8bitult | MIT | read (READMEs) | None. It targets the 8BitDo Micro over BLE (advertises as `80EL`): README.md:5, :61. |
| S3 | https://github.com/pastaq/evdev-keepalive | MIT | read (README, rules) | Indirect (watchdog theory). The udev rules name only `2dc8:6009` and `2dc8:310b`: `10-evdev-keepalive.rules:8-14`. |
| S4 | https://github.com/TheJayMann/8bitdo-spec | Unlicense | read (READMEs) | None for the 2C. It covers the Pro 2, SN30 Pro+ and a Switch-mode escape (`SwitchMode/README.md:4-15`). |
| S5 | https://github.com/s8n/ultimatecontroller-rs | no licence file, treat as all rights reserved | read (`docs/protocol.md`, README) | Low. The 2C is not listed. It is useful for the XInput command shapes and the `3109` IDLE id. |
| S6 | https://github.com/clach04/8bitdo_manual | Apache-2.0 | read (README, `firmware.md` grep) | None. It covers NES30/SN30-era pads. Pairing and sleep timings there are not 2C data. |
| S7 | https://github.com/jasonewall/8bitdo-sleep-fix | MIT | read (README, `detect.sh`) | Medium. Dongle active-to-idle re-enumeration and suspend/wake. |
| S8 | https://github.com/ascendedent/8bitdo-Linux-Software | no licence file, treat as all rights reserved | read (README, `docs/device-ids.md`, `docs/firmware.md`, `docs/sdl-channel.md`, `docs/capture-log.md` and `docs/field-notes.md` by grep) | Highest. It has bench captures and a firmware disassembly of the 2C. |
| S9 | https://github.com/aeromodes/8cryptdo | MIT | read (README, header of `cryptdo8.py`) | Low. Firmware cipher notes only. |
| S10 | https://github.com/philipp-schwarz/8bd-u2cw | GPL-3.0 | read (README, `8bd-u2cw.c` in full for the input and output paths) | High for `310A`. It is a Linux driver for the 2C over USB and 2.4 GHz. |
| S11 | https://github.com/leandrosalgado/8bitdo-ultimate-macos-remapper | MIT | read (README) | Analogy only. It targets the Ultimate 3-mode Xbox (`2dc8:901b`) over BLE on macOS. |
| S12 | https://gist.github.com/ammuench/0dcf14faf4e3b000020992612a2711e2?permalink_comment_id=5882798 | no licence shown | read. The page fetch did not render comment 5882798, so I read it through `gh api gists/<id>/comments` (read-only): it is by AnonUser-25, 2025-11-27. I also read the visible zkeng comment. | Medium. Mode-switch behaviour and ids. |
| S13 | https://github.com/libsdl-org/SDL/issues/15658 | issue text; SDL itself is Zlib | read (WebFetch). The fix commit `3fe72d2` was read through `gh api repos/libsdl-org/SDL/commits/3fe72d2`. PR #16364 is open and unmerged per `gh api`. | Highest. It has a 301C input decode. |
| S14 | https://github.com/ublue-os/bazzite/issues/2176 | issue text | read (WebFetch) | Medium. User reports on modes. |
| S15 | https://github.com/ndeadly/MissionControl/issues/851 | issue text | read (WebFetch) | Low. BLE only; no VID:PID, no descriptor. |
| S16 | https://github.com/ValveSoftware/steam-for-linux/issues/13158 | issue text | read (WebFetch) | None. It is about the 8BitDo Pro 3 being identified as an Ultimate 2. It has no 2C data, no gyro, rumble or VID:PID. |
| S17 | https://gist.github.com/barraIhsan/783a82bcf32bed896c85d27dbb8018a5 | no licence shown | read (WebFetch) | Low. It is about the Ultimate 2 Wireless (`6012`), not the 2C. Used only for contrast. |

Nothing was unreadable. The partial reads are:

- S12: comment 5882798 was read through the gist API, as above.
- S1: the firmware images were not downloaded.
- S8: `spec/protocol.md` and `docs/cable-inventory.md` were not read line by line. I read the firmware, device-id, README and capture-log files that carry the 2C facts.
- S6, S4 and S2 were read to confirm they hold no 2C data.

## 2. Facts

Each fact has an id, the claim, the source URL with file and line, the source's licence, and the comparison with our records. Verdicts are AGREES, EXTENDS or CONTRADICTS. Line numbers for S8 are file lines at HEAD (2026-11-11).

### 2.1 Identities (VID:PID per mode and transport)

**F1. `2DC8:310A` is the 2C in XInput mode, on the 2.4 GHz receiver and on a USB cable.**
- Details: bcdDevice 1.14. Three interfaces:
  - interface 0 is XInput (class `ff/5d/01`);
  - interface 1 is HID with a keyboard, consumer and mouse descriptor (166 bytes);
  - interface 2 is HID on vendor usage page `0xFF7A`, with a 63-byte input report `02` and a 63-byte output report `81`.
- Source: https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/device-ids.md#L9 and https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/README.md#L11-L17 (unlicensed). The firmware-side descriptors are at https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/firmware.md#L54. Independent: S10 binds only `2dc8:310a` (`8bd-u2cw.c:53`, GPL-3.0) and S14 shows `2DC8:310A` with a keyboard, mouse and generic HID in the kernel log (https://github.com/ublue-os/bazzite/issues/2176).
- Comparison: AGREES with `DOC:9`. It EXTENDS the row: the receiver row's route is only the XInput interface, and interfaces 1 and 2 also exist, so a macOS HID matcher could see a keyboard or vendor interface under the same VID:PID. `REC-310a` is `xbox-xusb`, as `DOC:9` says.

**F2. `2DC8:301C` has two personalities, told apart by product string and descriptor.**
- Idle (controller off): product string `IDLE`, bcdDevice 2.00, one HID interface, 42-byte descriptor on vendor page `0xFFA0`, reports `02` in and `81` out. It shows for about 6 s after plug-in, then becomes `310A` once the pad connects.
- Linked in DInput: a 145-byte descriptor, with gamepad report `01` plus vendor reports `02` and `81`.
- Source: https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/device-ids.md#L12, https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/capture-log.md#L65 and https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/firmware.md#L132 (unlicensed).
- Also: S12 zkeng comment: dongles show `2dc8:301c` "8BitDo IDLE" when the controllers are off and `310a` when on (https://gist.github.com/ammuench/0dcf14faf4e3b000020992612a2711e2, no licence). S13: HIDAPI log lists `0x2DC8:0x301C`, interface 0, usage page 1, usage 5 (https://github.com/libsdl-org/SDL/issues/15658).
- Comparison: AGREES with `REC-301c:21-32` (mode `unlinked`, `idle: NoControllerLinked`, product match `IDLE`) and `DOC:13`. EXTENDS: the idle personality is a vendor-page `0xFFA0` device with no gamepad usage, so a descriptor test (no usage page 1 / usage 5) is a second discriminator beside the product string.

**F3. `2DC8:301B` is the Bluetooth id, with an 11-byte input report.**
- Evidence:
  - The 1.09 firmware image plants `301b` in the identify reply and in the Bluetooth PnP record.
  - SDL's driver (before the fix) said the 2C Wireless has an 11-byte report with no sensor or rumble: https://github.com/libsdl-org/SDL/commit/3fe72d2, removed comment in `SDL_hidapi_8bitdo.c`, `usb_ids.h` line `ULTIMATE2C_WIRELESS 0x301b // mode switch to BT`.
  - MissionControl and Bazzite say the 2C uses Bluetooth LE.
  - Bazzite: "Bluetooth connection has no XInput mode" (sabrespectre, 2026-04-24).
- Source: https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/firmware.md#L68 (unlicensed); https://github.com/ndeadly/MissionControl/issues/851; https://github.com/ublue-os/bazzite/issues/2176.
- Comparison: AGREES with `DOC:10` (11 bytes, `DOC:66`) and with the "no rumble motor" decision at `DOC:86`.

**F4. `2DC8:301D` is the wired DInput personality of the pad.**
- It exists only while the DInput flag is set (hold B at power-on). The identify reply then reports `301d` instead of `301b`.
- It is one HID interface, with a 145-byte report descriptor: gamepad report `01` plus vendor reports `02` (63 bytes in) and `81` (63 bytes out), product string "8BitDo Ultimate 2C Wired Controller", EP 84 IN / 05 OUT, 64 bytes.
- The same 145-byte descriptor is byte for byte the receiver's DInput descriptor and the pad's.
- Source: https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/device-ids.md#L11, https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/firmware.md#L53 and #L141 (unlicensed). Not seen on the bench by that author.
- Comparison: EXTENDS `DOC:11` (which says "no capture ... shows which pad mode produces it"). It names the mode: B held at power-on. See also F5. A **probable contradiction** with `REC-301d` and `DOC:125`: those give `301D` the Bluetooth/GameSir button table (usage 1 to 15) and the Z/Rz stick, but the same 145-byte descriptor that F2 shows for the `301C` receiver was captured with sticks, hat and triggers laid out as in `DOC:43`. That is not the Z/Rz Bluetooth layout. See P1.

**F5. Mode choice by power-on combo.** The sources all describe a mode that persists.
- B held (with Home on the receiver path) selects DInput; X held (with Home) selects XInput.
- Sources: https://github.com/libsdl-org/SDL/issues/15658 (adapter firmware 1.0 needed for B+Home), https://github.com/ublue-os/bazzite/issues/2176 (HikariKnight 2025-02-07; SoRyTaki confirms; phamaralbr did not get it), https://gist.github.com/ammuench/0dcf14faf4e3b000020992612a2711e2 (AnonUser-25, 2025-11-27: wired, X while inserting the cable selects XInput and persists; B selects DInput).
- Firmware side: the pad stores the flag in a 26-byte settings record at flash `0x73000`, bytes 7 and 8: https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/firmware.md#L205 (unlicensed).
- The pad's "Y for Switch" combo is claimed only for the Ultimate 2 Wireless, not the 2C (https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/device-ids.md#L66-L69).
- Comparison: AGREES with `TASKS:23` (X + Guide gives XInput, B + Guide gives DInput) and with `docs/testing/8bitdo-tester-checks.md:T4` ("hold B while you switch the pad on, then connect the cable"). EXTENDS: the setting persists across power cycles and works with the cable (S12). The persistence matters to a tester who has forgotten the pad's last mode.

**F6. `2DC8:3109` is described as an idle/standby adapter personality, not a pad. This contradicts our record.**
- ascendedent: the V2 constant `PID_IDLE` is "the older idle receiver" (https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/device-ids.md#L34, unlicensed).
- s8n: `IDLE 0x3109 "Adapter standby / HID config mode"` (https://github.com/s8n/ultimatecontroller-rs/blob/HEAD/docs/protocol.md#L25, unlicensed).
- These are second-hand (names read from the vendor software); no capture of `3109` with a 2C exists in either repo. The 2.4 GHz 2C receiver's idle id has been observed to be `301C` (F2). This may be an older receiver revision or another adapter; the sources do not say.
- Comparison: **CONTRADICTS** `DOC:12` ("USB adapter, `XboxXUSB`"), `REC-3109` (family `xbox-xusb`, variant wired; see `Tests/EquivalenceSnapshots/catalog-index.txt:6858`) and `TESTS:13` (the `adapter` constant treats `3109` as a pad). It is closer to `docs/testing/8bitdo-tester-checks.md:68` (T3, "adapter in standby, then with the pad on"). Compare `REC-3107` and `REC-301c`, both `idle: NoControllerLinked`.

**F7. `2DC8:3107` is the idle id of the Ultimate 2 Wireless dongle (`USB2_IDLE`).**
- Product string `IDLE`. The descriptor size differs inside the source: 37 bytes in `device-ids.md` and 42 bytes in `firmware.md`.
- Source: https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/device-ids.md#L16 and https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/firmware.md#L247 (unlicensed).
- Comparison: AGREES with `REC-3107:14-15` (idle `NoControllerLinked`). It is not a 2C identity; keep it as is.

**F8. `2DC8:310B` is generic XInput, with the same three-interface layout as `310A`.** Applies to the Ultimate 2 Wireless (and the Pro 3 per S3). ascendedent: https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/device-ids.md#L13. S3's rules list it as "Pro 3 (2.4GHz mode)": https://github.com/pastaq/evdev-keepalive/blob/HEAD/10-evdev-keepalive.rules#L12-L14 (MIT). The sources disagree on which pad `310B` is. `REC` for `310B` is untouched by this research.

**F9. `2DC8:301A` is a different Bluetooth 2C id (`PID_UltimateBT2C`).**
- Update page only. Its 1.01 firmware image (update type 108) is encrypted end to end, so its report set is unknown. Not seen on hardware.
- Source: https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/device-ids.md#L31 and https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/firmware.md#L88 (unlicensed).
- Comparison: EXTENDS. We have no `301A` record, and the `301B` capture in `DOC:66` is from the maintainer's pad. A `301A` pad may exist.

**F10. `301B` is also the product-id string of a wired XInput personality inside the pad image.** The image has a second, "(WUKONG)" device descriptor with `301b`, one `ff/5d/01` interface and a different vendor descriptor; a flash value (`0x77000`, value 2) selects the WUKONG product strings. Source: https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/firmware.md#L55 and #L195 (unlicensed). Comparison: EXTENDS `DOC:10`. A wired pad could in principle enumerate as `301B` over USB with an XInput interface. No source saw it on a bench.

**F11. Bootloader ids `3208` and `5750`.** `3208` is the shared bootloader; `5750` is an older one, and it is "not known to be the 2C's bootloader". Both must receive no traffic; the udev rule in that repo excludes both. Source: https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/device-ids.md#L20-L21 and `README.md#L114` (unlicensed). Comparison: AGREES with `DOC:129` and `TASKS:120` (9.4).

### 2.2 Report layouts

**F12. `310A` input report is 20 bytes in the Xbox 360 style.**
- Byte 0 is `00`, byte 1 is `14`.
- Byte 2 bit mask: D-pad up `01`, down `02`, left `04`, right `08`, Start `10`, Back `20`, left stick click `40`, right stick click `80`.
- Byte 3: LB `01`, RB `02`, Guide `04`, A `10`, B `20`, X `40`, Y `80`.
- Byte 4 is the left trigger, byte 5 the right trigger. Bytes 6 to 13 are four little-endian signed 16-bit stick values, left X, left Y, right X, right Y. Vertical axes are inverted relative to the Linux convention.
- Source: https://github.com/philipp-schwarz/8bd-u2cw/blob/HEAD/8bd-u2cw.c (lines 369-409 in the HEAD I read; GPL-3.0). The driver does not decode the last six bytes.
- Comparison: AGREES with every row of `DOC:21-33`, including the constant tail `10 1C 30 64 00 10`, which no source explains (`DOC:21`).

**F13. `310A` has no separate rear-button bit; L4 and R4 are on-pad macros.**
- The driver says L4/R4 are not reported and are programmed on the pad: hold the rear button plus the target buttons, then press the square Mapping button. Its own workaround binds L4 to Back + both stick clicks and R4 to Start + both stick clicks, then decodes that combination.
- Firmware: the binds are four 32-bit masks in the settings record at `0x73000`, set only by the on-pad combo. No host command reads or writes them. Resetting the RF address wipes them.
- Defaults are not decoded in the sources, though the record resets an invalid slot to default masks `2` and `4`.
- Sources: https://github.com/philipp-schwarz/8bd-u2cw/blob/HEAD/README.md#L83-L100 (GPL-3.0) and https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/firmware.md#L206-L218 (unlicensed). The Ultimate 3-mode Xbox (`901b`, a different pad) reports its paddles as L3/R3 duplicates: https://github.com/leandrosalgado/8bitdo-ultimate-macos-remapper/blob/HEAD/README.md#L54-L59 (MIT).
- Comparison: AGREES with `DOC:37` (rear presses report only bits other controls own), `DOC:125` ("rear buttons default to L3 and R3"), and `TASKS:23` (2.1: L4 assigned/cleared). EXTENDS: it explains why `DOC:37` found no separate bit; the bit seen when "assigned" is the mapped control's own.

**F14. `301C` DInput report (this is the third-party decode of our own capture).**
- Report `01`: byte 1 holds A `01`, B `02`, L4 `04`, X `08`, Y `10`, R4 `20`, LB `40`, RB `80`. Byte 2 holds Back `04`, Start `08`, Guide `10`, left stick click `20`, right stick click `40`. Byte 3 is the hat: 0 up, then clockwise in steps of one to 7, anything else is centred. Bytes 4 to 7 are unsigned 8-bit sticks with rest `7F`. Byte 8 is the right trigger and byte 9 the left, 0 to `FF`.
- Source: https://github.com/libsdl-org/SDL/commit/3fe72d2 (diff of `src/joystick/hidapi/SDL_hidapi_8bitdo.c`, new 2C state handler; SDL is Zlib). The commit is on PR #16364 (open, not merged at read time). It treats the packet as 64 bytes because that is the HIDAPI read size; our capture shows the 10-byte report body.
- Comparison: AGREES with `DOC:43-54` on every control position. EXTENDS `DOC:58-60`: L4 is byte 1 bit 2 (`04`) and R4 is byte 1 bit 5 (`20`) on `301C`, the same bits as in the Bluetooth capture at `DOC:84`. This is a second source for the unassigned L4 that `DOC:92` lists as Unverified. The `DOC:13` note "no input map until the capture is mapped" can use this layout.
- Also: the SDL issue reporter saw the triggers as digital buttons 8 and 9 in DInput on Windows (https://github.com/libsdl-org/SDL/issues/15658). That matches the digital bits in byte 2 (`01`, `02`) beside the analog bytes 8 and 9 in `DOC:49`.

**F15. Bluetooth descriptor quirks (Simulation-page triggers, hat, paddles as L3/R3, `Z`/`Rz` right stick).** The `901b` remapper documents the same family of behaviour for the Ultimate 3-mode Xbox on macOS over BLE. The triggers rest at -1 on axes 3 and 4, the right stick Y is on axis 5, and the hat is one axis with a 2/7 step. The Xbox, Star and Profile buttons are taken by macOS's Game Controller framework and never reach the page. Source: https://github.com/leandrosalgado/8bitdo-ultimate-macos-remapper/blob/HEAD/README.md#L9-L67 and #L122-L127 (MIT). Comparison: it is a different pad; EXTENDS by analogy `DOC:103-125` and bears on `TASKS:33` (2.11, Guide/Home under GameController). `Resources/Controllers/2DC8/2dc8-901b.plist` exists already.

### 2.3 Output and rumble

**F16. `310A` / `3109`-style rumble is the 8-byte Xbox 360 frame `00 08 00 LL RR 00 00 00`.**
- Byte 3 drives the heavy (left) motor and byte 4 the light (right) motor, 0 to 255 each. A stop is the same frame with zeros.
- The driver allows one outstanding write and remembers a pending stop so the motor does not run on.
- The same frame appears in s8n's mode-switch sequence (https://github.com/s8n/ultimatecontroller-rs/blob/HEAD/docs/protocol.md#L64-L69 and #L82-L83, unlicensed).
- Source: https://github.com/philipp-schwarz/8bd-u2cw/blob/HEAD/8bd-u2cw.c (rumble message at lines 506-520; GPL-3.0). Receiver firmware accepts exactly this frame: https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/firmware.md#L141.
- Comparison: AGREES with the bytes in `DOC:39`. EXTENDS: our `rumble-6s.txt` write `00 08 00 00 C8 00 00 00` sets byte 4 only, the light motor. A tester may feel little. A write with byte 3 non-zero should be tried (P5). `DOC:39` says two testers felt rumble on `1.5.71`.

**F17. The 2C needs a host "hello" on the XInput out endpoint before it streams.**
- The driver sends the 3-byte LED frame `01 03 00` once at probe. Its author notes the pad has no programmable LED yet seems to want a host signal (author's guess, not firmware-confirmed).
- Firmware cross-check: the receiver sets its USB mode byte to 2 when it sees the LED frame `01 03 nn` or when the host reads the 42/145-byte descriptors; its report-`81` handlers are gated on that byte being 2 or 3.
- Sources: https://github.com/philipp-schwarz/8bd-u2cw/blob/HEAD/8bd-u2cw.c (welcome message at lines 561-571; GPL-3.0) and https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/firmware.md#L165 (unlicensed).
- Comparison: EXTENDS. Our `310A` captures stream without our sending it (`DOC:9`), so it may be unneeded on macOS where the OS XInput driver already sends it. The catalog line `usbStartupMs=0` for `REC-3109` and `REC-310a` (`Tests/EquivalenceSnapshots/catalog-index.txt:6858-6866`) means we send nothing. Unverified either way.

**F18. `301C` DInput rumble is a vendor report, not the report-`01` write we tried.**
- Receiver firmware (1.00 and 1.03) does not treat HID output report `01` (8 bytes, LED usage page) as rumble. It parses only the XInput frames `00 08 ..` and `01 03 nn`, plus report `81`.
- Report `81` rumble: a 64-byte report whose first byte is `81`, then `11 04 08`, then a 16-bit duration at bytes 5 and 6, left strength at byte 7 and right strength at byte 8 (0 to 255). The time unit is unverified (the XInput path uses 200 for its own auto-stop, probably milliseconds).
- The handler is gated by the same mode-2-or-3 byte (F17). On receiver firmware 1.00 a userspace write of that report to the hidraw node should rumble; the source says "nothing has been sent to test this".
- Source: https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/firmware.md#L123, #L141 and #L175 (unlicensed).
- Also: SDL says the 5-byte rumble `05 LL HH TL TR` is the common 8BitDo packet and, for the 2C, ifarbod says "the firmware gating is unexplained" (https://github.com/libsdl-org/SDL/issues/15658); reporter: DInput has no vibration.
- Comparison: EXPLAINS `DOC:62` and `TASKS:28` (2.6): the eight report-1 and report-5 writes returned `result=0` with no motion, consistent with the firmware ignoring both. EXTENDS `DOC:62` ("report `0x81` ... not tried") with the exact candidate bytes.

**F19. Bluetooth rumble is not available from the host.** SDL's pre-fix comment says the 11-byte-report 2C has no sensor or rumble support (https://github.com/libsdl-org/SDL/commit/3fe72d2). The firmware's report-`81` handler is reached only from USB endpoints, so the Bluetooth personality should not answer it: https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/README.md#L44 and `docs/firmware.md#L183` (unlicensed; the author calls silence "the expected result"). Comparison: AGREES with `DOC:86` and the `E2013` decision (`kIOReturnNotFound` for output report 5). It argues against spending more effort on the BLE half of `TASKS:28`.

**F20. Gyro and motion: none for the 2C.**
- SDL says the 2C has no sensor support: https://github.com/libsdl-org/SDL/commit/3fe72d2 (Zlib).
- The Ultimate 2 Wireless is different: its DInput exposes gyro and extra buttons (https://gist.github.com/barraIhsan/783a82bcf32bed896c85d27dbb8018a5, no licence). The 113-byte receiver descriptor for that pad has a 34-byte input report with sensors (https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/firmware.md#L252).
- MissionControl lists "Motion Controls" only as a wish for the 2C (https://github.com/ndeadly/MissionControl/issues/851).
- Comparison: no gyro field in `REC-301b`/`REC-301d`/`DOC`; AGREES by omission. `TASKS` has no gyro task for the 2C (the only gyro item is `TASKS:217`, 16.3, which is profile templates).

### 2.4 Receiver, keepalive, sleep, wake

**F21. Receiver idle and linked behaviour.**
- With the pad off, the dongle shows `301C` "IDLE". When the pad connects it re-enumerates as `310A`, or as `301C` DInput if the pad asked for DInput and the receiver firmware honours it.
- Receiver firmware 1.00 honours the pad's DInput request. Firmware 1.03 ignores it and always comes up XInput, though the DInput code remains in the image. This matches a Bazzite and SDL tester remark that Home+B "used to" give DInput.
- SDL issue: the reporter's adapter firmware is "1.0" and support said that version gives DInput (https://github.com/libsdl-org/SDL/issues/15658).
- Source: https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/firmware.md#L132-L139 (unlicensed).
- Comparison: EXTENDS `DOC:13`, `TASKS:23`. Our `301C` DInput capture works, so that receiver is probably 1.00. No evidence file records the receiver firmware version (`grep -rn -i firmware evidence/2c-*` finds none). Without it, "DInput over the receiver" cannot be told to a user.

**F22. The dongle changes identity when the pad turns off, which breaks suspend and wake on Linux.** The dongle re-registers as the idle device as the pad turns off. Enabling wake blindly at hub level wakes the machine at once. The fix unbinds first, waits for the idle id (or 20 s), then enables wake. Source: https://github.com/jasonewall/8bitdo-sleep-fix/blob/HEAD/README.md#L7-L19 (MIT). Bazzite: after reconnecting, extended inputs were seen only on the first connection (Mrufaihi, 2025-07-30) (https://github.com/ublue-os/bazzite/issues/2176). Comparison: EXTENDS. We have no sleep or wake handling for the 2C (`grep -n sleep DOC` finds only the bootloader paragraph, `DOC:129`). An OJD service that holds a device open over system sleep must expect a PID change from `310A` to `301C` and back.

**F23. Watchdog and keepalive: no 2C evidence.** The keepalive project says some 8BitDo firmware resets its USB device if it sees no host transfer for about a second, and the kernel polling on an open event node avoids this. Its rules list only `6009` and `310b`: https://github.com/pastaq/evdev-keepalive/blob/HEAD/README.md#L6-L11 and `10-evdev-keepalive.rules#L8-L14` (MIT). Nothing in S1 to S17 shows the 2C does this. S10, a driver for `310A`, has no keepalive: it sends one hello and then rumble only. Comparison: our `usbKeepAliveMs=-` for `310A` and `3109` (`Tests/EquivalenceSnapshots/catalog-index.txt:6858-6866`) is unchallenged. Our captures of 100 to 150 s show no resets (`DOC:9`, `DOC:13`).

**F24. Power-saving timers.** The manual-style data in S6 (sleep after 1 minute disconnected and 15 minutes connected) is for NES30/SN30-era pads, not the 2C (https://github.com/clach04/8bitdo_manual/blob/HEAD/README.md#L118-L122, Apache-2.0). Do not use it for the 2C.

### 2.5 Battery

**F25. No source gives the 2C battery byte.** SDL's Pro 2 style enhanced report is not used for `301B`. The firmware image (S8) lists no battery command. Bluetooth reports a real battery percentage only on the Ultimate 2 Wireless in Switch mode (https://gist.github.com/barraIhsan/783a82bcf32bed896c85d27dbb8018a5); the 2.4 GHz link reads a fixed 55 % there. Comparison: nothing contradicts `DOC:82` (byte 10 reads 0) or `TASKS:24` (2.2, a second charge level, and `TASKS:30` 2.8, drop the battery level if constant).

### 2.6 Firmware update

**F26. Firmware versions, update path, and cipher.**
- 2C pad: 1.06 (2024-07-05) and 1.09 (2025-03-13), 74,780 bytes each. Receiver ("Adapter"): 1.00 and 1.03. Bluetooth `301a`: 1.01. The V2 update server types are 75, 76 and 108.
- The images are a 28-byte header plus a plain Telink image (the `301a` one is encrypted end to end).
- The Windows and macOS Ultimate Software is the only supported updater. A user runs it in a Windows VM with USB passthrough in XInput mode (S12 AnonUser-25). The pad ships with 1.06; 1.09 is the newest at 2025-11.
- Also: SDL reporter had controller 1.06 and adapter 1.0.
- fwupd's repo holds no 2C image, and notes 8BitDo moved to an opaque API in 2020 (https://github.com/fwupd/8bitdo-firmware/blob/HEAD/README.md, no licence file; the script is GPL-3.0-or-later). The cipher notes in S9 say "most of the Ultimate/Pro line" uses a newer cipher (https://github.com/aeromodes/8cryptdo/blob/HEAD/README.md#L187-L188, MIT).
- Sources for the rest: https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/docs/firmware.md#L13-L23 and #L27 (unlicensed).
- Comparison: EXTENDS. We have no firmware-version field in records or evidence. OJD never flashes (`DOC:129` bootloader rule). Do not add an update path.

**F27. There is no host configuration channel on the 2C.** Interface 2 (vendor page `0xFF7A`) has report `81` with an updater, identify (`81 05 00 21 01`), rumble, RF-address get/set and a product-string selector, and nothing else. No settings read or write. V2 1.35 deliberately routes `310A` and `301C` to firmware only. The receiver answers `81` itself and does not relay it to the pad. Source: https://github.com/ascendedent/8bitdo-Linux-Software/blob/HEAD/README.md#L5-L40 and `docs/device-ids.md#L29-L47` (unlicensed). Warning: `81 ?? 66 aa 64 ...` rewrites the RF address and wipes the L4/R4 binds (`docs/firmware.md#L125`). Comparison: AGREES with our reading that a rear button is not host-configurable (`DOC:125`). EXTENDS: any probe of report `81` on `310A` must avoid `66 aa 64` and the updater class `05` commands (`81 05 00 51 00` reboots into the other boot mode: `docs/firmware.md#L171`).

### 2.7 Platform notes

**F28. Linux kernel support.** `310A` is in `xpad` since 6.12 (S8 `device-ids.md#L49`; S12 zkeng). Bazzite users saw a "Generic Controller" over Bluetooth and the dongle (https://github.com/ublue-os/bazzite/issues/2176). The 2C is "two Xbox 360 controllers in Steam" in one comment. Not about macOS; no change proposed.

**F29. `S16` (Steam #13158) is about the Pro 3 and gives no 2C data.** MissionControl #851 gives no VID:PID or descriptor.

## 3. Contradictions with our records and docs

1. **`3109` role (F6).** `DOC:12`, `REC-3109` and `TESTS:13` treat it as an XInput pad. Two sources name it the idle/standby adapter. This is second-hand (names inside vendor software), so label it "likely", not proven. The 2C receiver's observed idle is `301C`.
2. **`301D` button layout (F4).** `REC-301d` and `DOC:125` give it the Bluetooth usage table. The firmware reports it as the same 145-byte descriptor as the `301C` DInput receiver, whose captured report (`DOC:43`) is laid out differently from the 11-byte Bluetooth one (`DOC:66`). `TESTS` lines 83-90 test `301D` with the Bluetooth table.
3. **No other direct contradiction.** `310A` layout, `301C` layout, `301B` 11 bytes, no `301B` rumble, bootloader ids and idle `IDLE` all agree.

## 4. Mapping facts to open tasks

| Task | Facts | Note |
| --- | --- | --- |
| 2.1 (`TASKS:23`) receiver results, unassigned L4 on `301C`, both unassigned rear buttons on `310A` | F12, F13, F14, F21 | F14 predicts L4 = byte 1 bit 2 on `301C`. F13 predicts no new bit on `310A`. Record the receiver firmware version beside the captures (F21). |
| 2.2 (`TASKS:24`) battery at a second level | F25 | No source helps. |
| 2.3 (`TASKS:25`) rear buttons by cable | F4, F5, F13 | By cable the pad is `310A` (XInput) or `301D` (DInput, B held at power-on). Expect no own bit on `310A`. |
| 2.5 (`TASKS:27`) `301C` input map | F14, F2 | Third-party decode agrees with `DOC:43-54`. |
| 2.6 (`TASKS:28`) `rumbleTemplate` | F16, F18, F19 | For `301C`, the candidate is the 64-byte `81 11 04 08 dd dd ll rr` report. For `310A`, byte 3 as well as byte 4. For `301B`, deprioritise. |
| 2.7 (`TASKS:29`) find the modes of `301D` and `3109` | F4, F5, F6 | `301D` is B at power-on over a cable; `3109` is probably idle. |
| 2.8 (`TASKS:30`) rear buttons per mode | F13, F14 | Mapped bits exist only on `301B` and `301C`. |
| 2.11 (`TASKS:33`) `301B` server OJD, GameController Home | F15 | Analogy from the `901b` remapper. |
| 19.3 (`TASKS:245`) release procedure across cable, receiver, BLE with rumble | F5, F16, F18, F22 | Include a pad off/on step that watches the PID change. |
| 9.4 (`TASKS:120`) bootloader ids | F11 | Agrees. No change. |
| 2.4 (`TASKS:26`, done) idle mode for `301C` | F2 | Agrees; F2 offers a second discriminator. |
| 3.4 (`TASKS:40`) wired Xbox pads `2027`/`2019` | none | No source in this set covers them. |

## 5. Proposals only

These are not made. Each needs a decision first.

- **P1 (record + test, `301D`).** Do not treat `REC-301d`'s Bluetooth usage table as proven. Either keep it marked Unverified or switch it to the `301C` DInput decode once someone captures `301D`. A test could compare the `301D` descriptor-derived usage map to `301C`'s. Needs hardware (`TASKS:29`).
- **P2 (record + test, `3109`).** Reclassify `2DC8:3109` as an idle personality, or mark it Unverified in `DOC:12`, and align `TESTS:13`. `docs/testing/8bitdo-tester-checks.md:T3` already asks for the standby capture; its result decides.
- **P3 (record, `301C` input map).** Add `301C` input map from F14, which matches the capture in `DOC:43-54`. Include L4 `04` and R4 `20` in byte 1 only if the unassigned-L4 capture in `TASKS:23` agrees.
- **P4 (test).** An identity-transition test: a `301C` `IDLE` device is followed by a `310A` device on the same port. The service should drop the first and bind the second without a stale route. Source: F2, F22.
- **P5 (hardware check).** Rumble on `310A` with byte 3 non-zero (`00 08 00 C8 00 00 00 00`) and with both motors, to complete the felt-result gap in `DOC:39`.
- **P6 (hardware check, `TASKS:28`).** On `301C` DInput, one write of the 64-byte `81 11 04 08` report with a duration and strength (F18), from a device opened with the interface claimed by the hidtool. Skip report `81` subcommands other than rumble (F27).
- **P7 (evidence).** Record the receiver and pad firmware versions in the capture notes (F21, F26). They explain whether `301C` DInput is possible.
- **P8 (doc).** Add to `DOC`: the persistent mode setting (F5), the idle `0xFFA0` descriptor (F2), `301A` and `301B`-as-WUKONG as unseen identities (F9, F10), and the "no host config channel" statement (F27).
- **P9 (guard).** If a probe of vendor report `81` is ever added, refuse `66 aa 64`, the class `05` updater commands and `81 05 00 51 00` in code (F27), as the bootloader guard does for `3208` and `5750` (`DOC:129`).
- **P10 (no change).** No keepalive for the 2C (F23); no gyro (F20); no firmware tooling (F26).
