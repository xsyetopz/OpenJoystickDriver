# Controller Configuration Plan

Status: proposed for 0.5.0-beta.5. Breaking changes are allowed, with no migration of old files or schema shapes.

## Goal

Testers and users can add or fix a controller without a new OJD build. Most per-model behavior moves from Swift identity checks into validated data. Everyone can see where each configuration file lives.

## Where configuration lives

| Layer | Location | Owner | Format |
| --- | --- | --- | --- |
| Bundled controller records | app bundle resources, generated from `Resources/ControllerOverrides/` and pinned sources | OJD release, signed, read-only | `controller.schema.json` |
| User controller records | `~/Library/Application Support/OpenJoystickDriver/Controllers/<vvvv>-<pppp>.json` | user | `controller-override.schema.json`, `add` or `patch` |
| Remapping profiles | `~/Library/Application Support/OpenJoystickDriver/Profiles/<uuid>.json` | user | remapping profile, one file per profile |
| Active profile selections | `~/Library/Application Support/OpenJoystickDriver/ActiveProfiles.json` | user | selection list |
| App preferences | `UserDefaults` for the app's bundle identifier | app | unchanged |

This follows Apple's file-system layout: shipped data stays in the signed bundle, and user-owned data goes in Application Support under the app's name. User records use the same override schema as the repository, so a user record that works can be copied into `Resources/ControllerOverrides/` in a pull request without changes.

Profiles move from the single `RemappingProfiles.json` to one file per profile, so a profile can be shared as a file. Old libraries are not read. Users recreate their profiles.

## What a record can express

Today a record holds identity, protocol family, variant, quirks, USB settings, and capability corrections. The schema grows by three sections. Each is data a small set of generic Swift interpreters executes.

### Input layout

A fixed-report layout for pads whose reports are not decoded by a protocol driver:

- report ID and minimum length;
- buttons as byte offset and bit mask;
- axes as byte offset, bit width, signedness, range, and inversion;
- hat switch as byte offset, mask, and encoding (8-way, 4-bit, or pressure-only);
- triggers as analog bytes or buttons.

A new family, `hid.report-layout`, uses it. SDL's `gamecontrollerdb` mapping strings are the prior art for describing inputs as data, but they map HID elements and cannot describe raw bytes. `hid.descriptor` stays for pads whose descriptor is correct.

### Output templates

Per output feature (rumble, player indicator, lighting): report kind (output or feature), report ID, length, fixed bytes, and the byte position and scale of each value. The GP100 rumble becomes:

```json
{
  "rumble": {
    "report": { "kind": "output", "id": 2, "length": 8 },
    "leftMain": { "byte": 3 },
    "rightMain": { "byte": 2 }
  }
}
```

The write executors accept only reports a template produces, on the record's own device. This bound replaces the separate report-ID allowlist.

### Ownership

`ownership` is `macos` or `ojd`, with a default per protocol family.

- `macos`: macOS serves the pad, OJD publishes no virtual pad, and OJD sends only the output templates the record declares. This replaces the `NativeGamepadWrites` table: the Sixaxis and GP100 entries become data in their records or family defaults.
- `ojd`: OJD seizes the pad and publishes its virtual pad.

A seize macOS refuses leaves the pad with macOS and is reported, as today.

### Startup writes

An ordered list of fixed output or feature writes with delays, for pads that need a fixed enable sequence and nothing else.

## What stays in Swift

- Stateful protocols: GIP handshakes, Switch subcommands, DualShock 4 and DualSense checksums and Bluetooth framing, Steam Controller sessions, keep-alives. These stay protocol-family drivers. Records select them and carry their quirks.
- USB interfaces claimed through the `XboxUSB` personality of the `com.openjoystickdriver.VirtualHIDDevice` extension. Its USB entitlement is a product list Apple signs, so a user record cannot make it claim a new product. A user record with a raw-USB family works only through direct IOUSBHost access, when macOS allows it. `validate` reports this.
- Virtual pad identities, which are limited by what games accept.

## Mode-switching pads

A pad with several modes (the GP100 has PS3/PC and XInput) enumerates as a different identity in each mode, so each mode is its own record. The GP100's XInput mode reports `045E:028E`, Microsoft's Xbox 360 identity that many clones share. A record keyed by VID and PID cannot tell those clones apart. Whether records need an extra match key, such as the product string, is an open question. It depends on which driver owns `045E:028E` on the tester's Mac, which is not known yet.

## Runtime behavior

- The service loads the bundled catalog, then applies user records in filename order: `add` for a new identity, `patch` for a bundled one. A user `add` for a bundled identity is an error.
- A user record that fails schema or cross-field validation is skipped and reported with its path and reason in the app, in `status`, and in `diagnose`. The bundled catalog stays fatal on error, because a release must not ship a broken record.
- The service watches the user directory. On a change it reloads the user layer and re-admits only connected devices whose identity changed.
- The effective record for a connected pad, and which layer supplied each part, is shown in the app and in `controller list --json`. That source is runtime state, not a record field.

## API and SDK

The API is the schemas plus the CLI.

- The JSON schemas in `Resources/Schemas/` are the file contract. Their `$id` names the contract; a breaking change edits it in place, and the release notes say so.
- CLI commands, in the grammar of the [CLI Redesign Plan](cli-redesign-plan.md):
  - `ojd record list`: user and bundled records. `--bundled` lists the catalog.
  - `ojd record validate FILE|-`: schema, cross-field checks, and whether the family needs the USB extension.
  - `ojd record install FILE|-` and `ojd record remove VVVV:PPPP`: write or delete the user file. `remove` prompts on a terminal, needs `--force` otherwise, and supports `--dry-run`.
  - `ojd record show VVVV:PPPP`: the effective record and each part's layer.
  - `ojd record draft CONTROLLER`: a starting record from a connected pad's identity, descriptor, and captured reports, reusing the existing packet capture.
  - Every command supports `--json`.
- The local RPC socket stays private. The server accepts only OJD's own signing identity. Opening it to third-party tools is a separate security decision, outside this plan.
- No in-process plugins. The hardened runtime's library validation refuses third-party libraries, and a plugin ABI would freeze OJD's internal Swift types.
- No scripting language in this plan. A later scripting layer would need a sandbox, execution limits, and the same template-bounded writes. Linux HID-BPF shows those limits are the cost of scripting report fixups.

## Slices

Each slice is one change with its tests, docs, and checks.

1. **User record layer.** Load, merge, validate without failing the service, report errors, and reload on change. CLI `validate`, `install`, `remove`, and `show`. User page: where OJD keeps its files.
1. **Output templates and ownership.** Schema, template interpreter, and write-executor bound. Delete `NativeGamepadWrites`. Move the GP100 rumble into its record and the Sixaxis native writes into its family default. Regenerate the catalog.
1. **Input layouts.** `hid.report-layout` family and its interpreter. Move the GP100, Chillstream, and Cyborg V3 out of `PS3ThirdPartyDriver` and delete their identity checks. Regenerate the catalog. Landed with one change: the Cyborg V3 stays in `vendor.ps3-third-party`, because SDL admits it only after the feature probe, and its record sets the `dpad-pressure` quirk instead of an identity check. The hat takes a list of sources (8-way bits, or one bit per direction) instead of a pressure-only encoding.
1. **Startup writes.** Schema and executor for fixed sequences. Move drivers whose startup is only a fixed sequence. Landed as `output.startup` before the hardware checks, at the maintainer's request. No driver's startup was only a fixed sequence, so none was removed. The Sixaxis Bluetooth enable report `F4 42 03 00 00` moved into the `054c-0268` and `2563-0523` records, limited to `bluetooth-classic`, and `SixaxisDriver.activationWrites()` is gone. Record writes run only for controllers OJD opens, after the driver's activation writes.
1. **Record drafts.** `ojd record draft` from a connected pad. Landed as `ojd record draft CONTROLLER [--duration SECONDS]`: it reads the HID report descriptor and captures input reports through the packet log, maps byte-aligned standard buttons, sticks, triggers, and hat into a `hid.report-layout` record, falls back to `hid.descriptor` for a new model when nothing maps, and lists the bytes that changed. It refuses a bundled model when nothing maps.
1. **Profiles as files.** One file per profile and `ActiveProfiles.json`. The old library is not read.

Slices 1 to 3 make the GP100 a pure-data controller, which is the test that the format works. Slices 4 to 6 follow in beta.5 if time allows. Slices 1 to 5 have landed; the hardware checks below are still open. Slice 6 stops reading the old profile library. Existing users' profiles are discarded, not migrated, because no one used them yet (maintainer decision, 2026-10-01).

## Checks

Every slice runs the repository checks in `CLAUDE.md`, including `./Scripts/ojd catalog regenerate --check`, `./Scripts/ojd check schemas`, and `swift test`. Slices 2 and 3 also run `./Scripts/ojd test parsers-macos14`. Slice 3 compares each moved pad's parsed input for recorded reports before and after the move. Hardware checks: GP100 rumble and input in both modes, Sixaxis native LED and rumble.

## Open questions

- Match keys beyond VID and PID for shared identities such as `045E:028E`.
- Whether the app gets a structured record editor. The [GUI Redesign Plan](gui-redesign-plan.md) starts with the minimum: show the effective record and its path, validate and install files, and open them in the user's editor.
