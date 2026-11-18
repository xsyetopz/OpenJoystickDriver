# Import Controller Identities From Linux xpad

The generator reads the exact Linux and SDL revisions and source hashes in `ControllerSources.lock.json`. Moving branches such as master are not inputs.

## Reproduce the Catalog

Verify committed output:

```bash
just catalog-regenerate --check
```

Rewrite it after an intentional lock or override change:

```bash
just catalog-regenerate --write
just check-profiles
```

The generator downloads each locked source, checks its SHA-256, parses the full xpad device and initialization tables and the supported HID registration tables, applies local overrides, and writes records to fixed VID/PID paths.

## Translation

Linux input mappings:

| Linux | Becomes |
| --- | --- |
| `XTYPE_XBOX` | `XboxXID:Gamepad` |
| `XTYPE_XBOX360` | `XboxXUSB:Wired` |
| `XTYPE_XBOX360W` | `XboxXUSB:Receiver` |
| `XTYPE_XBOXONE` | XboxGIP, no stored variant (the transport decides). xpad rows carry no transport field, so every `xbox.*` family is reached through raw USB. |
| `MAP_SHARE_BUTTON` | XboxGIP parameter `shareButton` with `fromEnd` 18 (26 with `MAP_SHARE_OFFSET`), as xpad reads `data[len - 18]` or `data[len - 26]`. A row needing a parameter its family does not declare fails generation. A GIP pad with no `shareButton` has no Share. |
| `MAP_TRIGGERS_TO_BUTTONS`, `MAP_STICKS_TO_NULL` | `capabilities.absent` entries (`left-trigger`/`right-trigger`, the four stick axes). No trigger buttons added: the XID, XUSB and GIP parsers emit none. |
| `MAP_DPAD_TO_BUTTONS` | Dropped: it changes how Linux reports the D-pad, not the wire bits. |
| Supported PlayStation, Sony, Nintendo, Steam HID registrations | IOHID records from driver tables and hid-ids.h: SonySixaxis, SonyDualShock4, SonyDualSense, NintendoSwitch1, `ValveSteamController:Wired`, `ValveSteamController:Dongle` (Steam wireless receiver). |
| `FLAG_DELAY_INIT` on an `XTYPE_XBOXONE` row | Not a skip reason: `DRIVER_HANDLED_DEVICE_FLAGS` in `generate_xpad_records.py` lists it, because GIPDriver resends its startup sequence on the announce packets before the first input. Any other device flag skips the row as `unsupported_device_flags`. |
| Non-default `xboxone_init_packets` | Ordered `protocol.initialization` action IDs: `XboxGIP/power-on`, `XboxGIP/s-init`, `XboxGIP/enable-extra-input`, `XboxGIP/hori-ack`, `XboxGIP/led-on`, `XboxGIP/auth-done`, `XboxGIP/rumble-begin`, `XboxGIP/rumble-end`. Bytes: `defaults.session.namedPackets` of `Resources/Protocols/xbox-gip.plist`. |

Records omit protocol-default endpoints and the default initialization sequence. Unknown types, quirks, mappings, and startup macros are skipped with a count. The `0xFFFF:0xFFFF` catch-all row is skipped: it is no USB identity. Partial source-table parsing fails generation.

## SDL_GameControllerDB

`mdqinc/SDL_GameControllerDB` is the third pinned upstream. The `sdlGameControllerDB` entry of `ControllerSources.lock.json` names the repository, the commit, and the SHA-256 of `gamecontrollerdb.txt` and its license. `regenerate` verifies the download and writes `Sources/OpenJoystickDriverKit/Resources/SDLGameControllerDB/sdl-gamecontrollerdb.txt`, which starts with the upstream zlib license and a line naming the pin. Never edit it by hand.

The generator keeps lines whose `platform` is `Mac OS X` and counts the rest. It drops a line whose vendor and product appear in the pinned `controller_list.h` rows (SDL's HIDAPI drivers read those pads with another report format, so the `b#`, `a#` and `h#.#` indexes differ) or in a catalog record (a pad with a record never consults the database). An unparsable line fails generation. `regenerate` prints the counts: kept, other platform, unparsable, skipped controller list, skipped catalog record, duplicate GUIDs. The Kit converts a line against the pad's element list at connect; see [architecture](architecture.md).

## SDL Controller List

SDL's `src/joystick/controller_list.h` is the second pinned upstream (currently `release-3.4.16`). Its `arrControllers` rows are `{ MAKE_CONTROLLER_ID( vid, pid ), k_eControllerType_<type>, name }`. Commented rows are ignored; any other unparsed row inside the table fails generation. A row is identity evidence only, admitted through the source lock. The record has no source field.

| SDL type | Record |
| --- | --- |
| PS3Controller, Sony vendor ID | SonySixaxis |
| PS3Controller, other vendor IDs | VendorPS3ThirdParty, which probes for SDL's `PS3ThirdParty` report format |
| PS4Controller | SonyDualShock4 |
| PS5Controller | SonyDualSense, with the `maker` parameter `ThirdParty` for a non-Sony vendor ID; the driver probes such controllers for features as SDL does |
| SwitchProController | NintendoSwitch1 |
| SwitchJoyConLeft, SwitchJoyConRight | NintendoSwitch1 with the `layout` parameter `JoyConLeft` or `JoyConRight` |
| XBox360Controller | `XboxXUSB:Wired` |
| XBoxOneController | XboxGIP |
| SteamController, SteamControllerV2 | ValveSteamController, variant from `STEAM_VARIANTS` |
| SteamControllerNeptune | ValveSteamDeck |
| SwitchInputOnlyController | NintendoSwitchInputOnly |
| SteamControllerTriton | ValveSteamTriton, variant from `STEAM_VARIANTS` |

One SDL Steam type covers wired pads, dongles and Bluetooth LE links, so the variant comes from `STEAM_VARIANTS` in `Scripts/Catalog/generate_controller_catalog.py`, which follows the per-row comments in `controller_list.h` and `IsProteusDongle` in `SDL_hidapi_steam_triton.c`. An unlisted Steam row fails generation. In `sdl.plist` `steamVariants`, `28DE:1101` is the legacy Steam Controller (CHELL). Bluetooth LE rows (`1105`, `1106`, `1202`, `1303`) store `bluetooth-le`, dongles (`1142`, `1304`, `1305`) store `dongle`, the rest `wired`.

| Product ID | Identity |
| --- | --- |
| `1102` | Wired (D0G) |
| `1105`, `1106` | Bluetooth (D0G) |
| `1142` | Wireless dongle |
| `1201` | Wired (HEADCRAB) |
| `1202` | Bluetooth (HEADCRAB) |
| `1302` | Steam Triton Controller |
| `1303` | Triton BLE form |
| `1304` | Steam Proteus Dongle |
| `1305` | Steam Nereid Dongle |

The Switch 2 identities in `SWITCH_2_IDENTITIES` (`057e:2066`, `2067`, `2069`) get NintendoSwitch2, which selects Switch2Driver. The GameCube controller `057e:2073` is only in SDL `usb_ids.h`, so an add override gives it NintendoSwitch2 and the `gamecube` quirk.

`SDL_IDENTITY_FAMILIES` in `generate_controller_catalog.py` (`sdl.plist` `identityFamilies`) gives an identity the family of the SDL driver that claims it, where that differs from its type:

| Identity | Family | Reason |
| --- | --- | --- |
| ShanWan DS3 `2563:0523` | SonySixaxis | Claimed by SDL's `HIDAPI_DriverPS3_IsSupportedDevice` (`USB_VENDOR_SHANWAN` / `USB_PRODUCT_SHANWAN_DS3`). Its `is_shanwan` flag only skips the one-byte `0xF5` echo write, which OJD does not send. |
| HORI `0f0d:0086` | XboxXUSB | Xbox 360 protocol with PS3 buttons. |
| Backbone One PlayStation Edition Gen 2 `358a:0304` | HIDDescriptor | `HIDAPI_DriverPS5_IsSupportedDevice` rejects it: "This product doesn't appear to use the DualSense protocol". |
| DragonRise `0079:0006` ("DragonRise Generic USB PCB") | HIDDescriptor | Standard HID gamepad. |
| NVIDIA SHIELD `0955:7210` | VendorNVIDIAShield | `SDL_hidapi_shield.c` drives it; `HIDAPI_DriverXbox360_IsSupportedDevice` says it "doesn't talk Xbox controller protocol". Generation fails on any other NVIDIA row neither catalogued nor listed. |
| Microsoft Bluetooth Xbox identities in `SDL_IsJoystickBluetoothXboxOne` (`045e:02e0`, `02fd`, `0b05`, `0b0c`, `0b13`, `0b20`, `0b21`, `0b22`; Xbox One S, Elite 2, Series pads) | HIDDescriptor | HID over Bluetooth, not GIP. HIDDescriptorDriver picks the layout from the report descriptor, covering the Linux and Windows firmware modes in xpadneo `docs/descriptors/xb1s_linux.md`, `xb1s_windows.md`, `xbxs.md`. |

Some rows get no record: `ProtocolClassifier` binds an identity without one by its USB interface signature (XUSB or GIP) before falling back to HIDDescriptor, and a record would pin one protocol on a pad whose firmware mode chooses it. `regenerate` counts these as bound by interface signature, not skipped:

| Rows | Detail |
| --- | --- |
| XInputPS4Controller, XInputSwitchController | Pads that switch to Xbox 360 mode on a PC. Console mode has no Xbox interface and reaches HIDDescriptor. |
| XBoxOneController with a Microsoft Xbox 360 product ID (`028e`, `0291`, `02a0`, `02a1`, `02a9`, `0719`) under another vendor | Linux xpad rows with such IDs (PDP `0e6f:02a0`/`02a1` are GIP) still win. |
| Identity SDL lists under two Xbox USB types | HORI `0f0d:00ed` is both XInputPS4Controller and XBoxOneController. |
| `SDL_EXCLUSIONS` in the `interface-signature` bucket | `045e:02a0` (Xbox 360 Big Button IR receiver), `045e:0867` (unnamed Microsoft ID SDL lists as "Unknown Controller"), `1038:b360` (SteelSeries Nimbus/Stratus XL). |

Every other unmapped type (mobile touch, unknown) is skipped with a per-type count.

Linux rows and authored add overrides win. An SDL identity already present with the same family is a duplicate; with a different family, a conflict. Both are skipped and counted, as is an identity SDL lists under two types that are not both Xbox USB types. Identities are decided after grouping, so row order never changes the output.

Typed rows that do not use the wire protocol of an implemented variant are skipped by rule or by `SDL_EXCLUSIONS` in `generate_controller_catalog.py`. A listed identity must still appear with its expected type, be uncatalogued, and not be covered by a rule, so a lock bump forces a review. Generation also fails on any Microsoft (`045e`) `XBoxOneController` row neither catalogued nor listed, so no Bluetooth or driver identity reaches the USB-only GIP driver unreviewed.

| Bucket | Rows |
| --- | --- |
| `virtual-identity` | Name no USB device a host enumerates: Apple's generic MFi identities `05ac:0001`, `05ac:0002`; Joy-Con pair `057e:2008`, `057e:2068` (OJD pairs two Joy-Con records itself); Steam's virtual gamepad `28de:11ff`; NVIDIA's streaming controller `0955:b400` |
| `windows-driver-identity` | `045e:02a1`, `045e:02ff`: identities of the Windows XUSB and XBOXGIP drivers |
| Vendor ID `0x0000` | Skipped |

`0e6f:0186` (PDP Afterglow Wireless) and `0f0d:00f6` (HORI Wireless Switch Pad) get a NintendoSwitch1 record with the `usbProtocol` parameter `ChargingOnly`: their USB link only charges the pad, so the driver binds only the Bluetooth Classic link. Catalogued from their SDL types: the DualShock 4 USB wireless adapter `054c:0ba0` and the STRIKEPAD PS4 grip add-on `054c:05c5` (SonyDualShock4), the Access Controller `054c:0e5f` (SonyDualSense).

Admitted third-party DualShock 4 rows keep the nominal motion scale: like SDL, OJD installs the factory calibration report only for Sony's vendor ID. `0079:181b` (Venom Arcade Stick), flagged by SDL as possibly a PS3-protocol pad, is admitted as SonyDualShock4, as listed.

`regenerate` prints the parsed, mapped, added, duplicate, conflict, and interface-signature counts and every skip bucket.

## Generator Rule Tables

The generators read family lists, flag sets, name maps and exclusions from `Resources/CatalogRules/` (`linux-xpad.plist`, `linux-hid.plist`, `sdl.plist`). Each file carries `apiVersion` and `kind`; the loader rejects missing or unexpected keys. Change these files, not generator code, then run `just catalog-regenerate --write`. `linux-xpad.plist` `driverHandledDeviceFlags`: see `FLAG_DELAY_INIT` under Translation.

## Local Source Overrides

Override inputs:

```text
Resources/Controllers/<vid>/<vid>-<pid>.plist
```

A `Controller` file supplies a complete record missing from the pinned source. A `ControllerPatch` file in `Resources/ControllerPatches/<vid>/<vid>-<pid>.patch.plist` merges a patch into an existing imported record. `OJDRepositoryTool apply-patches` applies patches under Swift's merge rules (a number keeps the text of the file that writes it; a patch file below the vendor directory is refused). `OJDRepositoryTool validate records` checks every record, including its stored variant. The generator rejects:

| Rejected |
| --- |
| `Controller` files that collide with upstream |
| Patches without an upstream record |
| Duplicate authored identities |
| Redundant patches |
| Malformed or misplaced authored files |

Review evidence belongs in the controller's testing document, upstream issue, and Git history, not in runtime records. Linux recognition proves numeric identity and Linux driver classification. Not proven: macOS permissions, physical USB descriptors, Apple framework mapping, working input and output; those need runtime descriptor discovery and hardware evidence.
