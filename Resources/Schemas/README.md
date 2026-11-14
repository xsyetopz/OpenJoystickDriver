# Machine-Readable Contracts

`Resources/Schemas/` is the sole registry for the contracts of OpenJoystickDriver-authored documents and messages. The schemas are JSON (Draft 2020-12) and are resolved locally; runtime code never fetches them. A stored document is an XML property list (`.plist`), and a validator checks the objects read from it. A message (`--json` output, the endpoint lines, a support report) is JSON.

## Property Lists

A stored document is a file that carries `apiVersion` and `kind`. Each is an XML property list in UTF-8 with the extension `.plist`.

- A bundled document is written exactly as `PropertyListSerialization` writes it: sorted keys, no comment. A repository test compares each one with that output. A user file may hold XML comments; OJD drops them when it rewrites the file.
- A binary property list, JSON text, a `date`, and a `data` value are refused with a named error and the key path. A property list has no `null`: leave a key out to state that a value has no equivalent, and delete a key of a controller record through the `remove` list of a `ControllerPatch`.
- An integer stays an `integer` and a real stays a `real`, so write `1` for a count and `1.0` for a fraction.
- `plutil -lint` checks a file. `swift run OJDRepositoryTool to-plist <file.json>` writes the property list beside a JSON file, and `swift run OJDRepositoryTool format-plist <file.plist>` rewrites a property list in the canonical form.
- The schema files stay JSON, and so do the messages: `--json` output, the endpoint lines, and report files.

## Live Contracts

- `controller.schema.json`: generated runtime controller records.
- `controller-patch.schema.json`: a `ControllerPatch`: dotted key paths to `remove`, then a merge patch of a controller record chosen by a `selector` (`model`, `vendorID` and `productID`, or `all`). The authored patches in `Resources/ControllerPatches/` and the user and package files `Controllers/*.patch.plist` use it, and `Controllers/all.patch.plist` gives the `tuning` defaults for every controller. It checks the patch shape only; the merged record is checked against `controller.schema.json`.
- `virtual-device.schema.json`: a virtual device file, which defines a persona (`Generic`, `SDLCompatible` or `GameControllerCompatible`) or, with `match`, selects one for a controller and gives the HID identity its virtual gamepad publishes.
- `mod-package.schema.json`: the `mod.plist` manifest of a mod package folder, which lists controller, patch, profile, virtual device, and protocol description files.
- `protocol-description.schema.json`: the authored protocol descriptions `Resources/Protocols/<file stem>.plist`, which hold what is true of every device of a family. The file stem is the lowercase kebab-case family, split at every case boundary like every other `ojd` value (`XboxGIP` is `xbox-gip.plist`, `SonyDualShock4` is `sony-dual-shock4.plist`, `VendorGameSir` is `vendor-game-sir.plist`); `ojd` prints and accepts the same token. A description holds:
  - `displayName`: the display name of a documented family, one that no built-in name covers. Its file is `FamilyName.plist` in the user's `Protocols` folder or in a mod package, and it sets `defaults.input.layouts`.
  - `variants` and `storesVariant`: the variants the family implements (absent when it has one contract), and `true` when catalog records store the variant because the observed transport cannot decide it. `PhysicalProtocolID.variants` and `storesVariant` in Swift and the Python tools read these two members; a record's `protocol.variant`, `rawUSB`, `defaults.variants` and every `variants` list name only these.
  - `endpoints`: the USB endpoint addresses (`in`, `out`) the driver uses.
  - `interfaceSignatures`: the USB interface signatures (class, subclass, protocol, and the data interface number when the family pins one) that bind a device of that family without a record. Each signature's `variant` must be one of the description's `variants`; a family with no variants has no signatures.
  - `rawUSB`: `true` when the family always talks raw USB, or the list of variants that do.
  - `recordSections`: the sections (`input`, `rumble`, `output`, and so on) of a record that the driver reads.
  - `tuningKeys` and `rawUSBTuningKeys`: the `tuning` keys a record may set. `tuningKeys` applies to HID variants; `rawUSBTuningKeys` applies to raw-USB variants, which read no HID timing. A description that is always raw USB takes only `rawUSBTuningKeys`.
  - `macOSOwnedOutput`: the output macOS itself leaves undone for the family and OJD still sends.
  - `inputStart`: the `action` that starts a controller's input (`PressGuide`, a press of the home button) and the `variants` it is limited to.
  - `controls`: the set of controls the family's driver reports, and `recordCapabilities`: the control deltas a record may declare (`present`, `rumbleAbsent`).
  - `defaults`: the family's `session.keepAlive` (the keep-alive `intervalMilliseconds` and its fixed `writes`), the Switch 1 `session.subcommands` (the report id, the counter modulus and the startup `requests`), the GIP `session.namedPackets` (the `id`, `bytes` and `sessionByte` of each packet a record can name in `protocol.initialization`), the startup writes of `session.startup`, which may refer to a named packet with `{"packet": "<id>"}` (all HID reports, all raw-USB packets or all references, never a mix), the default `tuning` (for example the Switch 1 recovery values, and the command timeouts, resend intervals and handshake pacing of the other drivers), and `defaults.variants.<variant>.tuning`, which layers over it for a transport that needs another value, such as the Switch 1 `hidStartupIntervalMs` of Bluetooth and USB. A default key must be one the variant reads, and a variant must be the family's (E5004).

  `just catalog-regenerate` copies them into the Kit bundle.
- `report.schema.json`: the CloudEvents 1.0 support-report envelope and payload.
- `cli-output.schema.json`: the `--json` output of each `ojd` command. The CLI tests check every `--json` document they print against it.
- `profile.schema.json`: the remapping profile file that `ojd profile export` writes and `ojd profile import` reads. Cross-field rules stay in the strict decoder, and a test keeps the schema enums equal to the Swift cases.
- `access-grants.schema.json`: the `AccessGrants.plist` file in which the service keeps whether the endpoint is on and which signed clients may use it. Only the service writes it, through `ojd access`.
- `settings.schema.json`: the `Settings.plist` file, the user file that `ojd setting set` and the app write. Every setting is optional in the file; a setting it leaves out takes its built-in default.
- `service-listener-failure.schema.json`: the file beside the service's RPC socket (the socket path plus `.failure.plist`) that the service writes when its request listener stops on a fatal error (code `E2034`, the error number and the time). A successful listener start and an orderly stop delete it, and its `pid` and start time let readers report the failure only while that exact process runs. `ojd status` and `ojd diagnose` read it while the service cannot be reached.
- `controller-check.schema.json`: the document of a guided controller check (`ojd controller check`, and the Guided Check in Input Test). It embeds the `controller` facts of the support report, the app and macOS versions, and one step per declared control with its outcome (`Responded`, `OtherControl` naming the control that moved, or `Skipped`) and the range a stick or trigger showed. It holds no serial number, only whether one is present.
- `endpoint.schema.json`: the JSON lines that a granted client and the service exchange on the endpoint socket. The stream lines are the `ojd controller watch --all` events from `cli-output.schema.json`.
- `error-codes.schema.json`: the authored catalog `Resources/ErrorCodes.plist`, which gives every E#### error code its domain and name. `just errors-regenerate` copies the endpoint codes into `endpoint.schema.json` and the table into `wiki/Error-Codes.md`.
- `crosswalk.schema.json`: the authored table `Resources/Vocabulary/crosswalk.plist`, which maps each control id to its W3C, SDL, evdev, HID and Apple names and records the source of each column. It describes the shape of that file only; no schema accepts or maps a name in it.
- `vocabulary.schema.json`: only `$defs`, no `kind`. The one definition of the control ids (`$defs/control`) and the subsets other schemas `$ref`: D-pad ids, stick axes, axes, horizontal stick axes and triggers. The Swift enum `Control` mirrors it, and `Resources/Vocabulary/crosswalk.plist` documents the SDL, evdev, HID and Apple names of each id.

Each artifact class has one current contract, a flat `<kind>.schema.json` here. Its `$id` is `https://xsyetopz.github.io/OpenJoystickDriver/schemas/v1alpha3/<kind>.schema.json`; the ID is a name for the schema and nothing publishes or fetches it yet. A document declares `apiVersion: openjoystickdriver/v1alpha3` and its `kind`, and does not declare `$schema`. OJD rejects a missing or unknown `apiVersion`, and a `kind` that is not the one it reads. The error names the file, the version found, and the supported version.

| Schema | `kind` |
| --- | --- |
| `controller.schema.json` | `Controller` |
| `controller-patch.schema.json` | `ControllerPatch` |
| `virtual-device.schema.json` | `VirtualDevice` |
| `profile.schema.json` | `Profile` |
| `mod-package.schema.json` | `ModPackage` |
| `protocol-description.schema.json` | `ProtocolDescription` |
| `error-codes.schema.json` | `ErrorCatalog` |
| `crosswalk.schema.json` | `Crosswalk` |
| `access-grants.schema.json` | `AccessGrants` |
| `settings.schema.json` | `Settings` |
| `service-listener-failure.schema.json` | `ServiceListenerFailure` |
| `controller-check.schema.json` | `ControllerCheck` |
| `report.schema.json` | `SupportDiagnostic`, on the `data` payload; the CloudEvents envelope has none |

`cli-output.schema.json` and `endpoint.schema.json` give each message its own `kind` and share the `apiVersion`.

OJD-owned property names use lowerCamelCase, including `vendorID`, `profileID`, `initialization`, `keepAlive`, and `settleMilliseconds`. JSON Schema keywords, CloudEvents context attributes, external API fields, and dynamic map keys retain their standards' or sources' spelling. Do not recase values: enums, protocol identifiers, hashes, URLs, or user text.

Change a schema atomically with every producer, consumer, authored input, generated output, and test. Do not add a second live version, aliases, upcasters, fallback readers, crosswalks, or dual writers. Before `v1.0.0` any schema may change in any release, and a reader accepts only the current `apiVersion`. `ojd migrate` is the one explicit step that converts a stale user document (`DocumentMigrator`, in the Kit); a reader never converts.

## Boundaries

Controller records contain only facts consumed at runtime. Keep:

1. the protocol binding in `protocol.family` (a `PhysicalProtocolID` such as `XboxXUSB`) and `protocol.variant`. `variant` is required for the families whose protocol description sets `storesVariant` (`XboxXID` `Gamepad`; `XboxXUSB` `Wired` or `Receiver`; `ValveSteamController` and `ValveSteamTriton` `Wired`, `Dongle` or `BluetoothLE`; `VendorGameSir` `USB` or `EnhancedHID`) and forbidden for every other family, whose variant classification derives from the observed transport. The per-family variant, the `tuning` keys a family reads and the DualSense `present` controls come from the protocol descriptions; the Swift decoder and `ojd check profiles` check them, not the JSON schema. Records carry no transport: the family and variant fix the access path (`xbox.*` and `VendorGameSir:USB` use raw USB, every other binding IOHID), and a `usb` block is accepted only on raw-USB bindings;
2. driver-declared typed parameters scoped by family in `protocol.parameters`, an object whose keys and values each family declares and whose other keys the schema rejects: `XboxGIP` `shareButton` (`{"fromEnd": N}`), `NintendoSwitch1` `layout` (`Pro`, `JoyConLeft` or `JoyConRight`) or `usbProtocol` (`ChargingOnly`, which binds only the Bluetooth Classic link of a pad whose USB link only charges it and excludes `layout`), `NintendoSwitch2` `layout` (`Pro`, `JoyConLeft`, `JoyConRight` or `GameCube`), `VendorGameSir` `innerGrips` (enhanced HID extras report the inner grips) or `lightingMemory` (`ProfileSlots`: enhanced HID lighting memory is slot-based, and the driver reads, tracks and writes the active slot), exactly one of them on enhanced HID and none on USB, `VendorPS3ThirdParty` `hatSource`, `SonyDualShock4` `motionCalibration`, `role` and `motionScale` (`role` and `motionScale` exclude each other), `VendorNVIDIAShield` `reportRevision`, and `SonyDualSense` `maker` plus the third-party model parameters `unprobedSensors`, `unprobedTouchpad`, `forcedVibration` and `role`, which need `maker`. A flag parameter is `true` or absent. Every other family declares none;
3. named initialization actions in `protocol.initialization` (`XboxGIP` only, for example `XboxGIP/power-on`; each must be a `defaults.session.namedPackets` id of `Resources/Protocols/xbox-gip.plist`, which holds the bytes), plus `keepAlive` and USB overrides. Rows never carry raw packet bytes; omit the driver's default sequence;
4. a named driver-owned assembly policy in `protocol.assembly`, which assembles one logical controller from several protocol roles of one device. Discovery consumes it (`ProtocolDriverRegistry.assemblyPolicy(for:)`), but its vocabulary is empty (`"enum": []`, the Swift `ControllerAssemblyPolicy` has no cases), so every value is rejected: no row has multi-interface evidence yet, and until a row adds the first policy each protocol role is its own logical controller;
5. evidenced capability corrections in the top-level `capabilities` object; and
6. packet-mapped controls in parser events.

`capabilities` holds only deltas against the bound parser's declared controls: `absent` and `present` are disjoint, nonempty lists of `controlID` values from the normalized controller model, and `rumble: "Absent"` declares that the model has no rumble channel. Rumble is a separate key because rumble channel names such as `LeftTrigger` collide with control IDs; it is accepted only for GIP, the one driver that consumes it. A `present` control must be one the configured parser emits (for example the DualSense Edge paddles and function buttons). Protocol parameters, capability values, initialization actions, families and stored variants are Swift enums (`PhysicalProtocolID`, `PhysicalProtocolVariantID`), and a test keeps their schema enums equal to the Swift cases. Every implemented family has catalog rows, so the schema lists all of them.

Do not add provenance, confidence, verification, review state, test plans, or per-controller schemas. Pin source revisions in `ControllerSources.lock.json`. Record accepted hardware observations in the stable pages under `docs/testing/`. Support reports contain observed diagnostic state only.

CloudEvents owns `specversion`, `id`, `source`, `type`, `time`, `datacontenttype`, and `dataschema`; OJD owns the typed `data` payload. Do not invent another report shape without a live producer and consumer.

## Validation

```bash
just catalog-regenerate --check
just check-profiles
just check-schemas
git diff --check
```

`check schemas` validates all schemas, every generated controller record, every override, every protocol description, the sample mod package, the access grant fixtures, the error code catalog, and one live support report. It checks each `$id`, `apiVersion` const, and `kind` const against `Scripts/Catalog/schema_header.py`.
It also compares `cli-output.schema.json` with its copy at the last release tag, and fails when a change would break a program that reads that release's `--json` output; see [Using the command line](../../wiki/Command-Line.md). Generate an intentional catalog change only through:

```bash
just catalog-regenerate --write
```
