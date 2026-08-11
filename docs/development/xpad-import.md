# Import controller identities from Linux xpad

The runtime catalog is generated from the exact Linux revision and source hash in
ControllerSources.lock.json. Moving branches such as master are not runtime
inputs.

## Reproduce the catalog

Verify committed output:

    ./scripts/ojd catalog regenerate --check

Rewrite it after an intentional lock or override change:

    ./scripts/ojd catalog regenerate --write
    ./scripts/ojd check profiles

The generator downloads every locked Linux source and verifies each SHA-256. It parses the complete xpad device/initialization tables and supported HID registration tables, normalizes supported rows, applies explicit local overrides, and writes deterministic VID/PID paths.

## Translation

Supported Linux inputs map as follows:

- XTYPE_XBOX360 becomes Xbox360/xbox360.
- XTYPE_XBOX360W becomes Xbox360/xbox360Wireless.
- XTYPE_XBOXONE becomes GIP/xboxOne.
- Known mapping macros become protocol.flags.
- Supported PlayStation, Sony, Nintendo, and Steam HID registrations become HID records from their driver tables and hid-ids.h.
- Non-default xboxone_init_packets become protocol.startup_packets.

Protocol-default endpoints and startup packets are omitted. Imported records use
linux-xpad.c provenance and verified=false. Unknown types, flags, mappings, or
startup macros are skipped with an explicit count. Partial source-table parsing
fails generation.

## Local source overrides

Override inputs live at:

    Resources/ControllerOverrides/<vid>/<vid>-<pid>.json

An add operation supplies a complete canonical record missing from the pinned
source. A patch operation changes only selected top-level sections of an
existing imported record and must carry local-hardware or tester-packets
provenance. The generator rejects:

- add operations that collide with upstream;
- patch operations without an upstream record;
- duplicate override identities;
- redundant patches;
- patches without local evidence;
- malformed or misplaced override files.

## Review-only source inspection

The lower-level importer remains available for inspecting another exact Linux
revision without changing runtime data:

    ./scripts/ojd catalog xpad --github-ref <full-commit> \
      --vid 0x1532 --pid 0x0a29 --output-dir /tmp/ojd-xpad

Its manifest belongs only to the temporary inspection output. The runtime tree
is reproduced from ControllerSources.lock.json.

Linux recognition proves numeric identity and Linux driver classification. It
does not prove macOS permissions, physical USB descriptors, Apple framework
mapping or successful input/output. Those require runtime
descriptor discovery and hardware evidence.
