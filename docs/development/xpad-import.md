# Import Controller Identities From Linux xpad

The runtime catalog is generated from the exact Linux and SDL revisions and source hashes in ControllerSources.lock.json. Moving branches such as master are not runtime inputs.

## Reproduce the Catalog

Verify committed output:

```bash
./Scripts/ojd catalog regenerate --check
```

Rewrite it after an intentional lock or override change:

```bash
./Scripts/ojd catalog regenerate --write
./Scripts/ojd check profiles
```

The generator downloads every locked Linux and SDL source and verifies each SHA-256. It parses the complete xpad device/initialization tables and supported HID registration tables, normalizes supported rows, applies explicit local overrides, and writes deterministic VID/PID paths.

## Translation

Supported Linux input mappings:

- `XTYPE_XBOX` becomes `XboxXID:Gamepad` (original Xbox USB).
- `XTYPE_XBOX360` becomes `XboxXUSB:Wired` (wired Krypton).
- `XTYPE_XBOX360W` becomes `XboxXUSB:Receiver` (Argon adapter/receiver).
- `XTYPE_XBOXONE` becomes `XboxGIP`; the transport decides its variant, so none is stored.
- xpad rows carry no transport field: every `xbox.*` family is reached through raw USB.
- `MAP_SHARE_BUTTON` becomes the `XboxGIP` parameter `shareButton` with `fromEnd` 18, and `fromEnd` 26 with `MAP_SHARE_OFFSET`, as xpad reads `data[len - 18]` or `data[len - 26]`; a row needing a parameter its family does not declare fails generation. A GIP pad with no `shareButton` has no Share.
- `MAP_TRIGGERS_TO_BUTTONS` and `MAP_STICKS_TO_NULL` become `capabilities.absent` entries (`left-trigger`/`right-trigger` and the four stick axes). Buttons and stick clicks stay; no trigger buttons are added because the XID, XUSB and GIP parsers emit none.
- `MAP_DPAD_TO_BUTTONS` is dropped: it changes only how Linux reports the D-pad, not the wire bits OJD parsers decode.
- Supported PlayStation, Sony, Nintendo, and Steam HID registrations become IOHID records from their driver tables and hid-ids.h (`SonySixaxis`, `SonyDualShock4`, `SonyDualSense`, `NintendoSwitch1`, `ValveSteamController:Wired`, and `ValveSteamController:Dongle` for the Steam wireless receiver).
- `FLAG_DELAY_INIT` on an `XTYPE_XBOXONE` row is not a skip reason: `DRIVER_HANDLED_DEVICE_FLAGS` in `generate_xpad_records.py` lists it, because `GIPDriver` already resends its startup sequence on the announce packets before the first input. Any other device flag still skips the row as `unsupported_device_flags`.
- Non-default `xboxone_init_packets` become ordered `protocol.initialization` action IDs (`XboxGIP/power-on`, `XboxGIP/s-init`, `XboxGIP/enable-extra-input`, `XboxGIP/hori-ack`, `XboxGIP/led-on`, `XboxGIP/auth-done`, `XboxGIP/rumble-begin`, `XboxGIP/rumble-end`); the bytes of each are in `defaults.session.namedPackets` of `Resources/Protocols/xbox-gip.plist`.

Protocol-default endpoints and the default initialization sequence are omitted. The pinned source revision and hashes remain in `ControllerSources.lock.json`; generated runtime records contain only operational controller facts. Unknown types, quirks, mappings, or startup macros are skipped with an explicit count. Linux xpad's `0xFFFF:0xFFFF` catch-all row is skipped; it is not a USB identity. Partial source-table parsing fails generation.

## SDL_GameControllerDB

`mdqinc/SDL_GameControllerDB` is the third pinned upstream: the `sdlGameControllerDB` entry of `ControllerSources.lock.json` names the repository, the commit and the SHA-256 of `gamecontrollerdb.txt` and of its license. `regenerate` downloads the file, verifies the hash and writes `Sources/OpenJoystickDriverKit/Resources/SDLGameControllerDB/sdl-gamecontrollerdb.txt`, which starts with the upstream zlib license text and a line naming the pin. The resource is generated: never edit it by hand.

The generator keeps lines whose `platform` field is `Mac OS X` and counts every other line. It also drops a line whose vendor and product are in the pinned `controller_list.h` rows (SDL's HIDAPI drivers read those pads with another report format, so the `b#`, `a#` and `h#.#` indexes mean something else) or in a catalog record (a pad with a record never consults the database). A line that does not parse fails generation. `regenerate` prints the counts: kept, other platform, unparsable, skipped controller list, skipped catalog record and duplicate GUIDs. The Kit converts a line against the pad's element list at connect; see [architecture](architecture.md).

## SDL Controller List

SDL's `src/joystick/controller_list.h` is the second pinned upstream (currently `release-3.4.16`). Its `arrControllers` rows are `{ MAKE_CONTROLLER_ID( vid, pid ), k_eControllerType_<type>, name }`; commented rows are ignored and any other unparsed row inside the table fails generation. Each row is identity evidence only, admitted through the source lock; the record carries no source field.

| SDL type | Record |
| --- | --- |
| `PS3Controller`, Sony vendor ID | `SonySixaxis` |
| `PS3Controller`, other vendor IDs | `VendorPS3ThirdParty`, which probes for SDL's `PS3ThirdParty` report format |
| `PS4Controller` | `SonyDualShock4` |
| `PS5Controller` | `SonyDualSense`, with the `maker` parameter `ThirdParty` for a non-Sony vendor ID; the driver probes such controllers for their features as SDL does |
| `SwitchProController` | `NintendoSwitch1` |
| `SwitchJoyConLeft`, `SwitchJoyConRight` | `NintendoSwitch1` with the `layout` parameter `JoyConLeft` or `JoyConRight` |
| `XBox360Controller` | `XboxXUSB:Wired` |
| `XBoxOneController` | `XboxGIP` |
| `SteamController`, `SteamControllerV2` | `ValveSteamController` with the variant from `STEAM_VARIANTS` |
| `SteamControllerNeptune` | `ValveSteamDeck` |
| `SwitchInputOnlyController` | `NintendoSwitchInputOnly` |
| `SteamControllerTriton` | `ValveSteamTriton` with the variant from `STEAM_VARIANTS` |

One SDL Steam type covers wired pads, dongles and Bluetooth LE links, so the type alone does not give the variant. The generator takes it from `STEAM_VARIANTS` in `Scripts/Catalog/generate_controller_catalog.py`, which follows the per-row comments in SDL `controller_list.h` and `IsProteusDongle` in `SDL_hidapi_steam_triton.c`. The Bluetooth LE rows (`1105`, `1106`, `1202`, `1303`) store `bluetooth-le`, the dongles (`1142`, `1304`, `1305`) store `dongle`, and the rest store `wired`. A Steam row that `STEAM_VARIANTS` does not list fails generation.

The Switch 2 identities in `SWITCH_2_IDENTITIES` (`057e:2066`, `2067`, `2069`) get the `NintendoSwitch2` family, which selects `Switch2Driver` instead of the Switch 1 driver. The GameCube controller `057e:2073` is only in SDL `usb_ids.h`, so an add override gives it `NintendoSwitch2` and the `gamecube` quirk.

A few identities use a different SDL driver than their type implies. `SDL_IDENTITY_FAMILIES` in `generate_controller_catalog.py` gives each one the family of the driver that claims it: SDL's Sixaxis driver claims the ShanWan DS3 (`2563:0523`), so it gets `SonySixaxis`, and `controller_list.h` marks HORI `0f0d:0086` as the Xbox 360 protocol, so it gets `XboxXUSB`. SDL's PS5 driver rejects the Backbone One PlayStation Edition Gen 2 (`358a:0304`), so it gets `HIDDescriptor`. DragonRise `0079:0006`, SDL's "Generic USB PCB", is a standard HID gamepad, so it gets `HIDDescriptor`. SDL's Xbox 360 driver rejects the NVIDIA SHIELD controller `0955:7210` because it does not speak the Xbox protocol (`SDL_hidapi_shield.c` drives it), so it gets `VendorNVIDIAShield`; generation fails on any other NVIDIA row that is neither catalogued nor listed. The Microsoft Bluetooth Xbox identities that SDL's `SDL_IsJoystickBluetoothXboxOne` lists (`045e:02e0`, `02fd`, `0b05`, `0b0c`, `0b13`, `0b20`, `0b21`, `0b22`) are HID over Bluetooth, not GIP, so they get `HIDDescriptor`; `HIDDescriptorDriver` picks the layout from the report descriptor, covering the Linux and Windows firmware modes that xpadneo documents in `docs/descriptors/`. A listed identity must still appear with its expected type, so a lock bump forces a review.

Some rows get no record because `ProtocolClassifier` binds an identity without a record by its USB interface signature, XUSB or GIP, before it falls back to `HIDDescriptor`. A record would pin one protocol on a pad whose firmware mode chooses it. `regenerate` counts these rows as bound by interface signature, not as skipped:

- `XInputPS4Controller` and `XInputSwitchController` rows: pads that switch to Xbox 360 mode on a PC. Their console mode has no Xbox interface and reaches `HIDDescriptor`.
- `XBoxOneController` rows whose product ID is a Microsoft Xbox 360 ID (`028e`, `0291`, `02a0`, `02a1`, `02a9`, `0719`) under another vendor: the ID says XUSB and the type says GIP. Linux xpad rows with such IDs (PDP `0e6f:02a0`/`02a1` are GIP) still win.
- An identity SDL lists under two Xbox USB types, such as HORI `0f0d:00ed` as both `XInputPS4Controller` and `XBoxOneController`.
- `SDL_EXCLUSIONS` rows in the `interface-signature` bucket: `045e:02a0` (the Xbox 360 Big Button IR receiver), `045e:0867` (an unnamed Microsoft ID SDL lists as "Unknown Controller") and `1038:b360` (SteelSeries Nimbus/Stratus XL). Nothing beyond SDL's type says which protocol they speak.

Every other unmapped type (mobile touch, unknown) is skipped with a per-type count.

Linux rows and authored add overrides win. An SDL identity already present with the same family is a duplicate; one with a different family is a conflict. Both are skipped and counted, as is an identity SDL lists under two types that are not both Xbox USB types. Identities are decided after grouping, so row order does not change the output.

SDL's own drivers at the pinned commit show that some typed rows do not use the wire protocol of an implemented variant. The generator skips them by rule or by the `SDL_EXCLUSIONS` identity list in `generate_controller_catalog.py`. A listed identity must still appear with its expected type, must not be catalogued, and must not already be covered by a rule, so a lock bump forces a review. Generation also fails on any Microsoft (`045e`) `XBoxOneController` row that is neither catalogued nor listed, so a new Bluetooth or driver identity cannot reach the USB-only GIP driver unreviewed.

- `virtual-identity`: rows that name no USB device a host enumerates. These are Apple's generic MFi identities `05ac:0001` and `05ac:0002`, the Joy-Con pair `057e:2008` and `057e:2068` (OJD pairs two Joy-Con records itself), Steam's virtual gamepad `28de:11ff`, and NVIDIA's streaming controller `0955:b400`.
- `045e:02a1` and `045e:02ff`: identities of the Windows XUSB and XBOXGIP drivers, not USB devices (`windows-driver-identity`).
- Vendor ID `0x0000`: not a USB identity.

`0e6f:0186` (PDP Afterglow Wireless) and `0f0d:00f6` (HORI Wireless Switch Pad) get a `NintendoSwitch1` record with the `usbProtocol` parameter `ChargingOnly`. Their USB link only charges the pad, so the driver binds only the Bluetooth Classic link. The DualShock 4 USB wireless adapter `054c:0ba0`, the STRIKEPAD PS4 grip add-on `054c:05c5` and the Access Controller `054c:0e5f` are catalogued from their SDL types (`SonyDualShock4` for the first two, `SonyDualSense` for the Access Controller).

Admitted third-party DualShock 4 rows keep the nominal motion scale: like SDL, OJD installs the factory calibration report only for Sony's vendor ID. SDL's own list flags `0079:181b` (Venom Arcade Stick) as possibly a PS3-protocol pad; it is admitted as `SonyDualShock4` as listed.

`regenerate` prints the parsed, mapped, added, duplicate, conflict, and interface-signature counts and every skip bucket.

## Generator Rule Tables

The generators read their family lists, flag sets, name maps and exclusions from `Resources/CatalogRules/` (`linux-xpad.plist`, `linux-hid.plist`, `sdl.plist`). Each file carries `apiVersion` and `kind`, and the loader rejects missing or unexpected keys. Change these files, not generator code, to adjust a table; then run `./Scripts/ojd catalog regenerate --write`.

Facts behind single entries:

- `sdl.plist` `identityFamilies`:
  - `0F0D:0086` uses the Xbox 360 protocol but has PS3 buttons (SDL `controller_list.h`).
  - `2563:0523` is the DualShock 3 of Shanwan; it comes from SDL's `HIDAPI_DriverPS3_IsSupportedDevice`, which claims `USB_VENDOR_SHANWAN` / `USB_PRODUCT_SHANWAN_DS3`; its `is_shanwan` flag only skips the one-byte `0xF5` echo write, which OJD does not send.
  - `358A:0304` is the Backbone One PS5 V2: `HIDAPI_DriverPS5_IsSupportedDevice` rejects `USB_PRODUCT_BACKBONE_ONE_PS5_V2`: "This product doesn't appear to use the DualSense protocol".
  - Xbox One S, Elite 2 and Series pads over Bluetooth (`SDL_IsJoystickBluetoothXboxOne`) send standard HID reports, not GIP; the descriptor driver maps both firmware layouts (xpadneo `docs/descriptors/xb1s_linux.md`, `xb1s_windows.md`, `xbxs.md`). The `045E` entries `02E0`, `02FD`, `0B05`, `0B0C`, `0B13`, `0B20`, `0B21` and `0B22` are of this kind.
  - `0079:0006` is "DragonRise Generic USB PCB" in `controller_list.h`, a standard HID gamepad whose layout `HIDDescriptorDriver` recognizes.
  - `0955:7210` is the NVIDIA Shield controller, which `HIDAPI_DriverXbox360_IsSupportedDevice` says "doesn't talk Xbox controller protocol"; `SDL_hidapi_shield.c` drives it.
- `sdl.plist` `steamVariants`: `28DE:1101` is the legacy Steam Controller (CHELL); `1102` is the wired (D0G), `1105` and `1106` the Bluetooth (D0G); `1142` is the wireless Steam Controller dongle; `1201` is the wired (HEADCRAB) and `1202` the Bluetooth (HEADCRAB); `1302` is the Steam Triton Controller and `1303` its BLE form; `1304` is the Steam Proteus Dongle and `1305` the Steam Nereid Dongle.
- `linux-xpad.plist` `driverHandledDeviceFlags`: `FLAG_DELAY_INIT` holds the GIP init sequence until the pad's announce packet; `GIPDriver` resends its startup sequence on the announces before the first input.

## Local Source Overrides

Override inputs live at:

```text
Resources/Controllers/<vid>/<vid>-<pid>.plist
```

A `Controller` file supplies a complete canonical record missing from the pinned source. A `ControllerPatch` file in `Resources/ControllerPatches/<vid>/<vid>-<pid>.patch.plist` merges a patch into an existing imported record. `OJDRepositoryTool apply-patches` applies the patches, so the merge rules are Swift's, a number keeps the text of the file that writes it, and a patch file below the vendor directory is refused; `OJDRepositoryTool validate records` then checks every record, including its stored variant. The generator rejects:

- `Controller` files that collide with upstream;
- patches without an upstream record;
- duplicate authored identities;
- redundant patches;
- malformed or misplaced authored files.

Review evidence belongs in the controller's testing document, upstream issue, and Git history. Do not copy it into runtime controller records.

Linux recognition proves numeric identity and Linux driver classification. It does not prove macOS permissions, physical USB descriptors, Apple framework mapping or successful input/output. Those require runtime descriptor discovery and hardware evidence.
