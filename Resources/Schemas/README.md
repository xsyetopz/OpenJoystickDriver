# Machine-Readable Contracts

`Resources/Schemas/` is the sole registry for OpenJoystickDriver-authored JSON. Its Draft 2020-12 schemas are resolved locally; runtime code never fetches them.

## Live Contracts

- `controller.schema.json`: generated runtime controller records.
- `controller-override.schema.json`: authored additions and factual patches.
- `report.schema.json`: the CloudEvents 1.0 support-report envelope and payload.

Each artifact class has one current, unversioned contract. OJD-owned property names use lowerCamelCase, including `vendorID`, `profileID`, `initialization`, `keepAlive`, and `postHandshakeSettleMs`. JSON Schema keywords, CloudEvents context attributes, external API fields, and dynamic map keys retain their standards' or sources' spelling. Do not recase values: enums, protocol identifiers, hashes, URLs, or user text.

Change a schema atomically with every producer, consumer, authored input, generated output, and test. Do not add versioned schemas, aliases, migrations, upcasters, fallback readers, crosswalks, or dual writers. Git history preserves obsolete contracts.

## Boundaries

Controller records contain only facts consumed at runtime. Keep:

1. the protocol binding in `protocol.family` (a `PhysicalProtocolID` such as `xbox.xusb`) and `protocol.variant`. `variant` is required for the families whose variant the transport cannot decide (`xbox.xid` `gamepad`; `xbox.xusb` `wired` or `receiver`; `valve.steam-controller` `wired`, `dongle` or `bluetooth-le`; `vendor.gamesir` `usb` or `enhanced-hid`) and forbidden for every other family, whose variant classification derives from the observed transport. Records carry no transport: the family and variant fix the access path (`xbox.*` and `vendor.gamesir:usb` use raw USB, every other binding IOHID), and a `usb` block is accepted only on raw-USB bindings;
1. driver-declared quirks scoped by family in `protocol.quirks`: `xbox.gip` `share-offset`, `nintendo.switch1` `joy-con-left`, `joy-con-right`, `input-only` or `bluetooth-only` (at most one; `input-only` selects the fixed wired-pad report with no subcommand channel; `bluetooth-only` binds only the Bluetooth Classic link of a pad whose USB link only charges it), `valve.steam-controller` `triton` (the 2026 Steam Controller and its dongles: Triton reports, settings and repeated rumble) or `neptune` (the Steam Deck built-in controller, `wired` only: Deck reports, settings watchdog and rumble), at most one, and `vendor.gamesir` `inner-grips` (enhanced HID extras report the inner grips) and `lighting-slots` (enhanced HID lighting memory is slot-based: the driver reads, tracks and writes the active slot). Every other family declares none;
1. named driver-owned initialization actions in `protocol.initialization` (`xbox.gip` only, for example `xbox.gip/power-on`), plus `keepAlive` and USB overrides. Rows never carry raw packet bytes; omit the driver's default sequence;
1. a named driver-owned assembly policy in `protocol.assembly`, which assembles one logical controller from several protocol roles of one device. Discovery consumes it (`ProtocolDriverRegistry.assemblyPolicy(for:)`), but its vocabulary is empty (`"enum": []`, the Swift `ControllerAssemblyPolicy` has no cases), so every value is rejected: no row has multi-interface evidence yet, and until a row adds the first policy each protocol role is its own logical controller;
1. evidenced capability corrections in the top-level `capabilities` object; and
1. packet-mapped controls in parser events.

`capabilities` holds only deltas against the bound parser's declared controls: `absent` and `present` are disjoint, nonempty lists of `controlID` values from the normalized controller model, and `rumble: "absent"` declares that the model has no rumble channel. Rumble is a separate key because rumble channel IDs such as `left-trigger` collide with control IDs; it is accepted only for GIP, the one driver that consumes it. A `present` control must be one the configured parser emits (for example the DualSense Edge paddles and function buttons). Quirks, capability values initialization actions, families and stored variants are Swift enums (`PhysicalProtocolID`, `PhysicalProtocolVariantID`), and a test keeps their schema enums equal to the Swift cases. Every implemented family has catalog rows, so the schema lists all of them.

Do not add provenance, confidence, verification, review state, test plans, or per-controller schemas. Pin source revisions in `ControllerSources.lock.json`. Record accepted hardware observations in the stable pages under `contributing/testing/`. Support reports contain observed diagnostic state only.

CloudEvents owns `specversion`, `id`, `source`, `type`, `time`, `datacontenttype`, and `dataschema`; OJD owns the typed `data` payload. Do not invent another report shape without a live producer and consumer.

## Validation

```bash
./Scripts/ojd catalog regenerate --check
./Scripts/ojd check profiles
./Scripts/ojd check schemas
git diff --check
```

`check schemas` validates all schemas, every generated controller record, every override, OJD-owned Swift `CodingKeys`, and one live support report. Generate an intentional catalog change only through:

```bash
./Scripts/ojd catalog regenerate --write
```
