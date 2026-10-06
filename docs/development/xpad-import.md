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

- `XTYPE_XBOX` becomes `xbox.xid:gamepad` (original Xbox USB).
- `XTYPE_XBOX360` becomes `xbox.xusb:wired` (wired Krypton).
- `XTYPE_XBOX360W` becomes `xbox.xusb:receiver` (Argon adapter/receiver).
- `XTYPE_XBOXONE` becomes `xbox.gip`; the transport decides its variant, so none is stored.
- xpad rows carry no transport field: every `xbox.*` family is reached through raw USB.
- `MAP_SHARE_OFFSET` becomes the `xbox.gip` quirk `share-offset`; a row needing a quirk its family does not declare is skipped and counted.
- `MAP_TRIGGERS_TO_BUTTONS` and `MAP_STICKS_TO_NULL` become `capabilities.absent` entries (`left-trigger`/`right-trigger` and the four stick axes). Buttons and stick clicks stay; no trigger buttons are added because the XID, XUSB and GIP parsers emit none.
- `MAP_DPAD_TO_BUTTONS` is dropped: it changes only how Linux reports the D-pad, not the wire bits OJD parsers decode.
- Supported PlayStation, Sony, Nintendo, and Steam HID registrations become IOHID records from their driver tables and hid-ids.h (`sony.sixaxis`, `sony.dualshock4`, `sony.dualsense`, `nintendo.switch1`, `valve.steam-controller:wired`, and `valve.steam-controller:dongle` for the Steam wireless receiver).
- `FLAG_DELAY_INIT` on an `XTYPE_XBOXONE` row is not a skip reason: `DRIVER_HANDLED_DEVICE_FLAGS` in `generate_xpad_records.py` lists it, because `GIPDriver` already resends its startup sequence on the announce packets before the first input. Any other device flag still skips the row as `unsupported_device_flags`.
- Non-default `xboxone_init_packets` become ordered `protocol.initialization` action IDs (`xbox.gip/power-on`, `xbox.gip/s-init`, `xbox.gip/enable-extra-input`, `xbox.gip/hori-ack`, `xbox.gip/led-on`, `xbox.gip/auth-done`, `xbox.gip/rumble-begin`, `xbox.gip/rumble-end`); the GIP driver owns their bytes.

Protocol-default endpoints and the default initialization sequence are omitted. The pinned source revision and hashes remain in `ControllerSources.lock.json`; generated runtime records contain only operational controller facts. Unknown types, quirks, mappings, or startup macros are skipped with an explicit count. Linux xpad's `0xFFFF:0xFFFF` catch-all row is skipped; it is not a USB identity. Partial source-table parsing fails generation.

## SDL Controller List

SDL's `src/joystick/controller_list.h` is the second pinned upstream (currently `release-3.4.16`). Its `arrControllers` rows are `{ MAKE_CONTROLLER_ID( vid, pid ), k_eControllerType_<type>, name }`; commented rows are ignored and any other unparsed row inside the table fails generation. Each row is identity evidence only, admitted through the source lock; the record carries no source field.

| SDL type | Record |
| --- | --- |
| `PS3Controller`, Sony vendor ID | `sony.sixaxis` |
| `PS3Controller`, other vendor IDs | `vendor.ps3-third-party`, which probes for SDL's `PS3ThirdParty` report format |
| `PS4Controller` | `sony.dualshock4` |
| `PS5Controller` | `sony.dualsense`, with the `third-party` quirk for a non-Sony vendor ID; the driver probes such controllers for their features as SDL does |
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

A few identities use a different SDL driver than their type implies. `SDL_IDENTITY_FAMILIES` in `generate_controller_catalog.py` gives each one the family of the driver that claims it: SDL's Sixaxis driver claims the ShanWan DS3 (`2563:0523`), so it gets `sony.sixaxis`, and `controller_list.h` marks HORI `0f0d:0086` as the Xbox 360 protocol, so it gets `xbox.xusb`. SDL's PS5 driver rejects the Backbone One PlayStation Edition Gen 2 (`358a:0304`), so it gets `hid.descriptor`. DragonRise `0079:0006`, SDL's "Generic USB PCB", is a standard HID gamepad, so it gets `hid.descriptor`. SDL's Xbox 360 driver rejects the NVIDIA SHIELD controller `0955:7210` because it does not speak the Xbox protocol (`SDL_hidapi_shield.c` drives it), so it gets `vendor.nvidia-shield`; generation fails on any other NVIDIA row that is neither catalogued nor listed. The Microsoft Bluetooth Xbox identities that SDL's `SDL_IsJoystickBluetoothXboxOne` lists (`045e:02e0`, `02fd`, `0b05`, `0b0c`, `0b13`, `0b20`, `0b21`, `0b22`) are HID over Bluetooth, not GIP, so they get `hid.descriptor`; `HIDDescriptorDriver` picks the layout from the report descriptor, covering the Linux and Windows firmware modes that xpadneo documents in `docs/descriptors/`. A listed identity must still appear with its expected type, so a lock bump forces a review.

Some rows get no record because `ProtocolClassifier` binds an identity without a record by its USB interface signature, XUSB or GIP, before it falls back to `hid.descriptor`. A record would pin one protocol on a pad whose firmware mode chooses it. `regenerate` counts these rows as bound by interface signature, not as skipped:

- `XInputPS4Controller` and `XInputSwitchController` rows: pads that switch to Xbox 360 mode on a PC. Their console mode has no Xbox interface and reaches `hid.descriptor`.
- `XBoxOneController` rows whose product ID is a Microsoft Xbox 360 ID (`028e`, `0291`, `02a0`, `02a1`, `02a9`, `0719`) under another vendor: the ID says XUSB and the type says GIP. Linux xpad rows with such IDs (PDP `0e6f:02a0`/`02a1` are GIP) still win.
- An identity SDL lists under two Xbox USB types, such as HORI `0f0d:00ed` as both `XInputPS4Controller` and `XBoxOneController`.
- `SDL_EXCLUSIONS` rows in the `interface-signature` bucket: `045e:02a0` (the Xbox 360 Big Button IR receiver), `045e:0867` (an unnamed Microsoft ID SDL lists as "Unknown Controller") and `1038:b360` (SteelSeries Nimbus/Stratus XL). Nothing beyond SDL's type says which protocol they speak.

Every other unmapped type (mobile touch, unknown) is skipped with a per-type count.

Linux rows and authored add overrides win. An SDL identity already present with the same family is a duplicate; one with a different family is a conflict. Both are skipped and counted, as is an identity SDL lists under two types that are not both Xbox USB types. Identities are decided after grouping, so row order does not change the output.

SDL's own drivers at the pinned commit show that some typed rows do not use the wire protocol of an implemented variant. The generator skips them by rule or by the `SDL_EXCLUSIONS` identity list in `generate_controller_catalog.py`. A listed identity must still appear with its expected type, must not be catalogued, and must not already be covered by a rule, so a lock bump forces a review. Generation also fails on any Microsoft (`045e`) `XBoxOneController` row that is neither catalogued nor listed, so a new Bluetooth or driver identity cannot reach the USB-only GIP driver unreviewed.

- `virtual-identity`: rows that name no USB device a host enumerates. These are Apple's generic MFi identities `05ac:0001` and `05ac:0002`, the Joy-Con pair `057e:2008` and `057e:2068` (OJD pairs two Joy-Con records itself), Steam's virtual gamepad `28de:11ff`, and NVIDIA's streaming controller `0955:b400`.
- `045e:02a1` and `045e:02ff`: identities of the Windows XUSB and XBOXGIP drivers, not USB devices (`windows-driver-identity`).
- Vendor ID `0x0000`: not a USB identity.

`0e6f:0186` (PDP Afterglow Wireless) and `0f0d:00f6` (HORI Wireless Switch Pad) get a `nintendo.switch1` record with the `bluetooth-only` quirk. Their USB link only charges the pad, so the driver binds only the Bluetooth Classic link. The DualShock 4 USB wireless adapter `054c:0ba0`, the STRIKEPAD PS4 grip add-on `054c:05c5` and the Access Controller `054c:0e5f` are catalogued from their SDL types (`sony.dualshock4` for the first two, `sony.dualsense` for the Access Controller).

Admitted third-party DualShock 4 rows keep the nominal motion scale: like SDL, OJD installs the factory calibration report only for Sony's vendor ID. SDL's own list flags `0079:181b` (Venom Arcade Stick) as possibly a PS3-protocol pad; it is admitted as `sony.dualshock4` as listed.

`regenerate` prints the parsed, mapped, added, duplicate, conflict, and interface-signature counts and every skip bucket.

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
