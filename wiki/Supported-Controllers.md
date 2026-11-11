# Supported Controllers

This page lists the controllers that people tested with OpenJoystickDriver (OJD), explains what each tier means, and describes how OJD treats clone controllers and generic HID controllers.

Xbox and PlayStation names in the UI are trademarks of Microsoft and Sony. This project is not affiliated with either.

## Contents

- [Supported Controllers](#supported-controllers-1)
- [Clone and Fake Controllers](#clone-and-fake-controllers)
- [Generic HID Controllers](#generic-hid-controllers)
- [Further Reading](#further-reading)

## Supported Controllers

This section sorts controllers into three tiers. The tiers are a documentation classification. The app shows no tier and no warning. A tier records how much hardware testing confirms a controller. Official and Community-verified mean that people tested the controller on real hardware and it worked. Unverified means that nobody confirmed the controller yet. Somebody verified a controller only in the connection mode that they tested. The other modes have no verification and may work. A controller that works over USB may not work over Bluetooth or a dongle. For more information, see [Connection types](Connecting-Controllers.md#connection-types).

### Official

The maintainer owns and tests these controllers.

| Controller | Connection mode tested |
| --- | --- |
| Sony DUALSHOCK 4 (v2) | Not recorded here |
| Sony DUALSHOCK 3 (CECHZC2) | USB |
| Sony DUALSHOCK 3 (CECHZC1) | USB |
| GameSir G7 SE | USB |
| Razer Wolverine (V1) Tournament Edition | USB |

The maintainer says that a few more controllers belong in this tier. This list names only the ones that the maintainer confirmed.

The DUALSHOCK 3 does not connect over Bluetooth on macOS 27.0. The test stored the Mac's Bluetooth address in the controller over USB, and the controller then reached the Mac. macOS requires authentication before it accepts a Bluetooth HID connection. It asks for a passcode, which the DUALSHOCK 3 cannot answer, and pairing times out. Use the DUALSHOCK 3 with a USB cable.

### Community-Verified

A tester used the controller on real hardware, and it worked. The table names the mode that the tester used.

| Controller | VID:PID | Mode tested | What works | Not tested |
| --- | --- | --- | --- | --- |
| 8BitDo Ultimate 2C Wireless | `2DC8:310A` | 2.4 GHz dongle, XInput mode | Buttons, sticks, triggers at rest, D-pad, stick clicks, rumble | Not recorded |
| ZD Ultimate Legend | `413D:2204` | 2.4 GHz dongle, XInput mode | Input, OJD rumble, back-button keyboard bindings, mode switching | Not recorded |
| Xbox Nano Controller | `045E:0B4F` | Bluetooth LE, `game-controller-compatible` profile | Buttons, sticks, triggers, D-pad, stick clicks. The Xbox button and Share do not work | Rumble, Steam |

Two testers tested the 8BitDo Ultimate 2C Wireless on tester build `1.5.71`. One tester (gornobatov) tested the ZD Ultimate Legend on macOS 26.7.1. For the 8BitDo details, see [the test record](../docs/testing/8bitdo-ultimate-2c.md).

One tester tested the Xbox Nano Controller on macOS 26.5.2. For the details, see [the test record](../docs/testing/xbox-nano.md).

The 8BitDo Ultimate 2C Wireless has a different VID:PID in each mode. The Bluetooth mode `2DC8:301B` and the wired DInput mode `2DC8:301D` have no verification. They may work; the rear buttons repeat L3 and R3 and map no paddle. The HID receiver `2DC8:301C` is idle while its product string is `IDLE`, with no pad linked: OJD sends it no data and creates no gamepad. With a pad linked it serves the HID descriptor, which maps no named control yet. The USB adapter `2DC8:3109` stays an `XboxXUSB` wired record, also unverified.

The 8BitDo Ultimate 2 in DInput mode (`2DC8:6012`, cable and 2.4 GHz dongle) has an unverified record that uses the Ultimate 2C layout and maps no rear button. Its receiver `2DC8:6013` and dongle `2DC8:3107` are idle identities: OJD sends them no data and creates no gamepad. For the details, see [the Ultimate 2 test record](../docs/testing/8bitdo-ultimate-2.md).

The 8BitDo bootloader identities `2DC8:3208` and `2DC8:5750` are never served. Their bundled records idle with the reason `Bootloader`, and no user or package file adds or patches them. OJD sends them no data, because a write to a pad in bootloader state risks a bad firmware image. The Controllers page lists such a pad as unserved with the reason `BootloaderIdentity`. For the rule, see [the test record](../docs/testing/8bitdo-ultimate-2c.md#bootloader-identities).

Every 8BitDo `2DC8` identity that has a record. Only `2DC8:310A` is Community-Verified; every other row is Unverified.

| VID:PID | Model and mode | Protocol |
| --- | --- | --- |
| `2DC8:2000`, `2DC8:2002` | No source names the model | `XboxGIP` |
| `2DC8:200F` | No source names the model | `XboxGIP`, with the Share button read from the end of the report |
| `2DC8:3106`, `2DC8:6001` | No source names the model | `XboxXUSB`, wired |
| `2DC8:3107` | Ultimate 2 dongle | Idle |
| `2DC8:3109` | Ultimate 2C USB adapter | `XboxXUSB`, wired |
| `2DC8:310A` | Ultimate 2C, 2.4 GHz dongle, XInput | `XboxXUSB`, wired |
| `2DC8:310B` | Ultimate 2 and Pro 3 may share this identity; no capture confirms it or shows how the host tells them apart | `XboxXUSB`, wired |
| `2DC8:301B` | Ultimate 2C, Bluetooth LE | `HIDDescriptor` |
| `2DC8:301C` | Ultimate 2C HID receiver | Idle while the product string is `IDLE`, else `HIDDescriptor` |
| `2DC8:301D` | Ultimate 2C, wired, DInput | `HIDDescriptor` |
| `2DC8:6012` | Ultimate 2, DInput, cable and 2.4 GHz dongle | `HIDDescriptor` |
| `2DC8:6013` | Ultimate 2 receiver | Idle |
| `2DC8:901B` | Ultimate 3-mode, Bluetooth, Xbox mode | `HIDDescriptor`, Xbox button order |

The Ultimate 3-mode record (`2DC8:901B`) has no capture; see [the Ultimate 2 test record](../docs/testing/8bitdo-ultimate-2.md).

### Unverified

The Wii Remote (`057E:0306` and `057E:0330`) has bundled records and no hardware test. For what OJD reads from it, see [Wii Remote](Wii-Remote.md).

OJD includes a built-in catalog of 707 controller records. The Unverified tier is every catalog controller that this page does not list as Official or Community-verified. A record does not prove that the controller works. Nobody tested these controllers on real hardware. The catalog includes the NVIDIA SHIELD controllers of 2015 (`0955:7210`) and 2017 (`0955:7214`). On macOS the 2017 controller sends input only, with no rumble.

An unverified controller may work, may partly work, or may not work. The tier does not mean that the controller is broken or fake.

### Flydigi Records

These Flydigi records are source-derived and unverified. The files a tester sends decide what each record maps; the checks are in [Flydigi tester checks](../docs/testing/flydigi-tester-checks.md).

| Controller | VID:PID | Mode | Tier | Test record |
| --- | --- | --- | --- | --- |
| Flydigi Vader 4 Pro | `D7D7:0041` | Bluetooth LE | Unverified | [Vader 4 Pro](../docs/testing/flydigi-vader-4-pro.md) |
| Flydigi Vader 5S | `37D7:2801` | USB; GIP, or XUSB when the pad shows interface `FF/5D/01` | Unverified | [Vader 5S](../docs/testing/flydigi-vader-5s.md) |
| Flydigi Vader 5 Pro dongle | `37D7:2401` | 2.4 GHz USB; HID extended report after startup writes | Unverified | [Vader 5 Pro](../docs/testing/flydigi-vader-5-pro.md) |
| Flydigi Apex 4 | `04B4:2412` | DInput; the XInput mode is the Microsoft `045E:028E` record | Unverified | [Apex 4](../docs/testing/flydigi-apex-4.md) |

### SteelSeries Nimbus Record

The SteelSeries Nimbus (`1038:1420`, USB) has a source-derived, unverified record. The record maps its eight pressure-sensitive buttons, its pressure D-pad and its Menu button, and it reads the left and right sticks and the L2 and R2 triggers. The record sets no `server`, so macOS serves the Nimbus as its own game controller and OJD only reads its input. The Nimbus has four player LEDs on an output report that records cannot yet describe, so OJD does not drive them. Bluetooth identity `0111:1420` appears only in SDL's database and has no record. The Menu button, the trigger threshold and the axis directions wait for a capture from the pad.

To find out whether your controller is in the catalog:

1. Connect the controller.
2. Open the **Controllers** area of the app window.
3. Look for your controller in the list.

You can also run this command:

```shell
ojd controller list
```

If the controller appears, OJD has a record for it or reads it as a generic HID controller. If it does not appear, see [Controller not detected](Troubleshooting.md). A controller without a record may still work as a generic HID controller. For more information, see [Generic HID controllers](#generic-hid-controllers).

OJD leaves some gamepads to macOS. OJD does not publish a virtual controller for them.

### Report a Result

If you test a controller, tell the maintainer which mode you used and what worked. For more information, see [Reporting a bug](Reporting-a-Bug.md).

## Clone and Fake Controllers

Some controllers look like a Sony or Microsoft controller but use a different chip and a different identity. OJD identifies a controller by its VID:PID, not by its shape or its name on the box. A clone with a different VID:PID is a different device to OJD. For more information, see [Finding your controller ID](Connecting-Controllers.md#finding-your-controller-id).

Clones often send data in a different format, so the driver for the original controller may read them wrongly. Do not report a clone under the name of the original controller.

### Known Clones

| Controller | Copies | Notes |
| --- | --- | --- |
| Zhongqing ZQDZ-P3-BT-3D-FZ-V2.0 | PS3 controller | The maintainer owns this fake. The chip is not identified. |
| Ant Esports GP100 | PS3 controller | A Shanwan PS3 clone. VID:PID `2563:0575` in PS3/PC mode. |

The Ant Esports GP100 starts in XInput mode. In that mode macOS sees no input. To switch it to PS3/PC mode, hold **Select** and **B** while you connect it. One tester reports **Start** and **B** instead. For more information, see [the Shanwan test record](../docs/testing/ps3-third-party.md).

## Generic HID Controllers

OJD can read some HID gamepads that are not in its catalog. It reads the report descriptor that the controller sends. Generic HID support is not a fallback for a known controller. A controller with a record always uses its own driver, and OJD does not retry a failing known controller as generic HID.

### What Works

Generic HID support reads these controls:

- Buttons 1 to 11 only. These map to south, east, west, north, LB, RB, view, menu, L3, R3, and guide.
- Two sticks.
- Two triggers.
- One eight-position D-pad hat.

Generic HID support has no rumble and no lighting. Buttons above 11 do not map. Paddles and other extra controls need a controller record.

### When OJD Refuses a Controller

OJD accepts a controller as generic HID only if its descriptor passes strict checks:

- The descriptor has a Joystick, Game Pad, or Multi-axis Controller collection.
- That collection has a stick or hat input and a button input.
- The descriptor has no unsupported or inconsistent items.

If a controller fails a check, OJD does not use it. The `status` command lists the controller as unbound, gives the reason, and prints a sentence that says why and a sentence that says what to do, in your language. The Controllers page shows the same two sentences. Run it with this command:

```shell
ojd status
```

For more information about `ojd`, see [Using the command line](Command-Line.md).

Some controllers are not standard. Their descriptor may put sticks or triggers on unusual axes. These controllers need a record.

### Mapping Source

A controller without a record that passes the descriptor checks gets its mapping from one of two places. OJD ships the Mac lines of [SDL_GameControllerDB](https://github.com/mdqinc/SDL_GameControllerDB). When a line matches the controller, OJD applies it to the controller's elements, and `ojd controller show` reads "mapped from SDL_GameControllerDB" with the GUID and the match tier. The tiers, in order, are:

1. `ExactGUID`: the version and the name hash match.
2. `GUIDWithoutNameCRC`: the version matches and the line has no name hash.
3. `GUIDWithoutVersion`: the name hash matches and the version does not.
4. `GUIDWithoutVersionAndNameCRC`: only the vendor and product match.

When a GUID has several lines, the last one wins. An axis that stands for a button presses it when it moves past half of its range from the center. A line can name controls OJD cannot express, such as a D-pad direction on a button. `ojd controller show` lists them as unmapped and the other controls still work.

When no line matches, the controller keeps the standard map described under What Works and the row reads "standard HID usage map". When a line matches but names an element the controller lacks, OJD rejects the whole line, keeps the standard map, and the row says why. A controller whose descriptor fails the checks stays unbound whatever the database holds, and `ojd controller show` says a line exists. A controller with a record never reads the database.

## Further Reading

- [Finding your controller ID](Connecting-Controllers.md#finding-your-controller-id)
- [Connection types](Connecting-Controllers.md#connection-types)
- [Game and app compatibility](Playing-Games.md)
- [Reporting a bug](Reporting-a-Bug.md)
