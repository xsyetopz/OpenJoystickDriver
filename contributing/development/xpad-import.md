# Import Controller Identities From Linux xpad

The runtime catalog is generated from the exact Linux and SDL revisions and source hashes in ControllerSources.lock.json. Moving branches such as master are not runtime inputs.

## Reproduce The Catalog

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

- `XTYPE_XBOX` becomes `xbox.xid:gamepad` (original Xbox USB).
- `XTYPE_XBOX360` becomes `xbox.xusb:wired` (wired Krypton).
- `XTYPE_XBOX360W` becomes `xbox.xusb:receiver` (Argon adapter/receiver).
- `XTYPE_XBOXONE` becomes `xbox.gip`; the transport decides its variant, so none is stored.
- xpad rows carry no transport field: every `xbox.*` family is reached through raw USB.
- `MAP_SHARE_OFFSET` becomes the `xbox.gip` quirk `share-offset`; a row needing a quirk its family does not declare is skipped and counted.
- `MAP_TRIGGERS_TO_BUTTONS` and `MAP_STICKS_TO_NULL` become `capabilities.absent` entries (`left-trigger`/`right-trigger` and the four stick axes). Buttons and stick clicks stay; no trigger buttons are added because the XID, XUSB and GIP parsers emit none.
- `MAP_DPAD_TO_BUTTONS` is dropped: it changes only how Linux reports the D-pad, not the wire bits OJD parsers decode.
- Supported PlayStation, Sony, Nintendo, and Steam HID registrations become IOHID records from their driver tables and hid-ids.h (`sony.sixaxis`, `sony.dualshock4`, `sony.dualsense`, `nintendo.switch1`, `valve.steam-controller:wired`, and `valve.steam-controller:dongle` for the Steam wireless receiver).
- Non-default `xboxone_init_packets` become ordered `protocol.initialization` action IDs (`xbox.gip/power-on`, `xbox.gip/s-init`, `xbox.gip/enable-extra-input`, `xbox.gip/hori-ack`, `xbox.gip/led-on`, `xbox.gip/auth-done`, `xbox.gip/rumble-begin`, `xbox.gip/rumble-end`); the GIP driver owns their bytes.

Protocol-default endpoints and the default initialization sequence are omitted. The pinned source revision and hashes remain in `ControllerSources.lock.json`; generated runtime records contain only operational controller facts. Unknown types, quirks, mappings, or startup macros are skipped with an explicit count. Linux xpad's `0xFFFF:0xFFFF` catch-all row is skipped; it is not a USB identity. Partial source-table parsing fails generation.

## SDL Controller List

SDL's `src/joystick/controller_list.h` is the second pinned upstream (currently `release-3.4.16`). Its `arrControllers` rows are `{ MAKE_CONTROLLER_ID( vid, pid ), k_eControllerType_<type>, name }`; commented rows are ignored and any other unparsed row inside the table fails generation. Each row is identity evidence only, admitted through the source lock; the record carries no source field.

| SDL type | Record |
| --- | --- |
| `PS3Controller` (Sony vendor ID only) | `sony.sixaxis` |
| `PS4Controller` | `sony.dualshock4` |
| `PS5Controller` | `sony.dualsense` |
| `SwitchProController` | `nintendo.switch1` |
| `SwitchJoyConLeft`, `SwitchJoyConRight` | `nintendo.switch1` with the `joy-con-left` or `joy-con-right` quirk |
| `XBox360Controller` | `xbox.xusb:wired` |
| `XBoxOneController` | `xbox.gip` |
| `SteamController`, `SteamControllerV2` | `valve.steam-controller` with the variant from `STEAM_VARIANTS` |
| `SteamControllerNeptune` | `valve.steam-controller:wired` with the `neptune` quirk |
| `SwitchInputOnlyController` | `nintendo.switch1` with the `input-only` quirk |
| `SteamControllerTriton` | `valve.steam-controller` with the `triton` quirk and the variant from `STEAM_VARIANTS` |

One SDL Steam type covers wired pads, dongles and Bluetooth LE links, so the type alone does not give the variant. The generator takes it from `STEAM_VARIANTS` in `Scripts/Catalog/generate_controller_catalog.py`, which follows the per-row comments in SDL `controller_list.h` and `IsProteusDongle` in `SDL_hidapi_steam_triton.c`. The Bluetooth LE rows (`1105`, `1106`, `1202`, `1303`) store `bluetooth-le`, the dongles (`1142`, `1304`, `1305`) store `dongle`, and the rest store `wired`. A Steam row that `STEAM_VARIANTS` does not list fails generation.

The Switch 2 identities in `SWITCH_2_IDENTITIES` (`057e:2066`, `2067`, `2069`) also get the `switch-2` quirk first, which selects `Switch2Driver` instead of the Switch 1 driver. The GameCube controller `057e:2073` is only in SDL `usb_ids.h`, so an add override gives it `switch-2` and `gamecube`.

`XInputPS4Controller` and `XInputSwitchController` rows are pads in Xbox 360 mode. They get no record, because the XUSB interface signature binds them without one. Every other type (Joy-Con pair, Apple, mobile touch, unknown) is skipped with a per-type count.

Linux rows and authored add overrides win. An SDL identity already present with the same family is a duplicate; one with a different family is a conflict. Both are skipped and counted, as is an identity SDL lists under two types. Identities are decided after grouping, so row order does not change the output.

SDL's own drivers at the pinned commit show that some typed rows do not use the wire protocol of an implemented variant. The generator skips them by rule or by the `SDL_EXCLUSIONS` identity list in `generate_controller_catalog.py`. A listed identity must still appear with its expected type, must not be catalogued, and must not already be covered by a rule, so a lock bump forces a review. Generation also fails on any Microsoft (`045e`) `XBoxOneController` row that is neither catalogued nor listed, so a new Bluetooth or driver identity cannot reach the USB-only GIP driver unreviewed.

- Non-Sony `PS3Controller` rows: `SDL_hidapi_ps3.c` reads them through a separate third-party report format behind a feature-report probe. Its Sixaxis driver also claims the ShanWan DS3 (`2563:0523`) with ShanWan-specific handling that OJD's DS3 parser has not been checked against, so only Sony's vendor ID is admitted.
- Non-Sony `PS5Controller` rows: `SDL_hidapi_ps5.c` decodes third-party pads with the alternate `PS5StatePacketAlt_t` layout, which OJD's DualSense parser does not implement.
- `XBoxOneController` rows whose product ID is a Microsoft Xbox 360 ID (`028e`, `0291`, `02a0`, `02a1`, `02a9`, `0719`) under another vendor: the ID says XUSB, not GIP, and a catalog row would bypass interface-signature admission. Linux xpad rows with such IDs (PDP `0e6f:02a0`/`02a1` are GIP) still win.
- `XBox360Controller` rows with NVIDIA's vendor ID: `SDL_hidapi_xbox360.c` notes the Shield controller does not talk the Xbox protocol.
- Microsoft Bluetooth Xbox identities (`SDL_IsJoystickBluetoothXboxOne`): they are HID over Bluetooth, and OJD implements GIP only over USB. `045e:0867` is an unnamed Microsoft ID SDL lists as "Unknown Controller"; semantics unclear.
- `045e:02a1` and `045e:02ff`: identities of the Windows XUSB and XBOXGIP drivers, not USB devices. `045e:02a0`: the Xbox 360 Big Button IR receiver.
- `054c:0ba0` DualShock 4 USB wireless adapter: `SDL_hidapi_ps4.c` handles it with `is_dongle` and a deferred connect that OJD does not implement.
- `054c:05c5` STRIKEPAD PS4 grip add-on and `054c:0e5f` Access Controller: their report layout against OJD's parsers is unverified.
- `0f0d:00f6` HORI Wireless Switch Pad and `0e6f:0186` PDP Afterglow Wireless: SDL rejects the first over USB, and its list says the second uses USB for charging only (`no-usb-protocol`).
- `1038:b360` SteelSeries Nimbus/Stratus XL: semantics unclear; no pinned evidence that it speaks XUSB.
- Vendor ID `0x0000`: not a USB identity.

Admitted third-party DualShock 4 rows keep the nominal motion scale: like SDL, OJD installs the factory calibration report only for Sony's vendor ID. SDL's own list flags `0079:181b` (Venom Arcade Stick) as possibly a PS3-protocol pad; it is admitted as `sony.dualshock4` as listed.

`regenerate` prints the parsed, mapped, added, duplicate, and conflict counts and every skip bucket.

## Local Source Overrides

Override inputs live at:

```text
Resources/ControllerOverrides/<vid>/<vid>-<pid>.json
```

An add operation supplies a complete canonical record missing from the pinned source. A patch operation changes only selected top-level sections of an existing imported record. The generator rejects:

- add operations that collide with upstream;
- patch operations without an upstream record;
- duplicate override identities;
- redundant patches;
- malformed or misplaced override files.

Review evidence belongs in the controller's testing document, upstream issue, and Git history. Do not copy it into runtime controller records.

## Review-Only Source Inspection

Use the lower-level importer to inspect another exact Linux revision without changing runtime data:

```bash
./Scripts/ojd catalog xpad --github-ref 893e11787f78e43b534e252249ac3fff4d1333f8 \
  --vid 0x1532 --pid 0x0a29 --output-dir /tmp/ojd-xpad
```

Its manifest belongs only to the temporary inspection output. The runtime tree is reproduced from ControllerSources.lock.json.

Linux recognition proves numeric identity and Linux driver classification. It does not prove macOS permissions, physical USB descriptors, Apple framework mapping or successful input/output. Those require runtime descriptor discovery and hardware evidence.
