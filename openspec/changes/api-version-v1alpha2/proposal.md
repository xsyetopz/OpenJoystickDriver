## Why

The alpha.2 changes alter the shape of profiles (`multiTap`, macros, system actions), controller records and protocol descriptions (declarative input layouts), and the error catalog. A file with the alpha.1 shape still says `apiVersion: openjoystickdriver/v1alpha1`, so it would fail on a field-level error instead of on its version. The user decided on 2026-10-25 that the schemas move to `v1alpha2` in 0.6.0-alpha.2.

## What Changes

- **BREAKING:** `OpenJoystickDriverAPI.version` is `openjoystickdriver/v1alpha2` and `OpenJoystickDriverAPI.schemaBase` ends in `/schemas/v1alpha2/`. Every document OJD reads, writes or prints carries the one version: Controller, ControllerPatch, Profile, VirtualDevice, ModPackage, ErrorCatalog, AccessGrants, Settings, SupportDiagnostic data, CLI output and endpoint messages.
- All 17 files in `Resources/Schemas/` get the `v1alpha2` `$id` and `apiVersion` const together; no schema keeps `v1alpha1`.
- A `v1alpha1` file is refused with `E5001` like any unsupported version. There is no reader, alias or migration for it.
- `wiki/Updating-and-Uninstalling.md` gains an "Update from 0.6.0-alpha.1" section: which stored files are refused, what the app and `ojd` show, and how to bring each back (edit the `apiVersion` line when the shape is unchanged, or reset, re-grant or re-export it).
- `./Scripts/ojd catalog regenerate --write` writes the bundled copies of `Resources/Protocols` and `Resources/VirtualDevices` before it validates records, and builds `OJDRepositoryTool` again after them. Loading the catalog rules at import builds the tool with the earlier copies, so a changed protocol description failed validation against its own stale copy.
- The `ci.yml` checkout comment names the real reason for `fetch-depth: 0`. It claims a release-tag schema compare that no script runs; `Scripts/Release/bundle_version.py:79` counts commits with `git rev-list --count HEAD`.

## Capabilities

### New Capabilities

- `api-version`: the current version string, the schema `$id` base, and how a stored `v1alpha1` file is refused and brought back.

### Modified Capabilities

None under `openspec/specs/`. The `schema-versioning` requirements live in the active change `platform-neutral-redesign`; task 1.3 replaces the two literal `v1alpha1` strings there so both changes state one version.

## Impact

- Code: one constant in `Sources/OpenJoystickDriverKit/ApplicationService/Payloads/OpenJoystickDriverAPI.swift:7,10`. Swift readers and the Python generators (`Scripts/Catalog/schema_header.py:37`, `catalog_rules.py:33`, `validate_schemas.py:90,110`) read it, so they change with it.
- Authored data: 103 files under `Resources` (Schemas, Controllers, ControllerPatches, Protocols, VirtualDevices, CatalogRules, Vocabulary, `ErrorCodes.json`).
- Generated data: 696 controller records and the Kit copies of Protocols and VirtualDevices, through `./Scripts/ojd catalog regenerate --write`, plus `errors regenerate` and `vocabulary regenerate`.
- Hand-written clients outside the Kit: `Scripts/SDK/reference_client.py:26`, `Tools/BridgeCore/Sources/BridgeCore/EndpointSession.swift:6`, and two WebRTCBridge tests.
- Tests (30 files), `docs` (7), `wiki` (5), and four `platform-neutral-redesign` artifacts that quote the version.
- Users: every stored file from 0.6.0-alpha.1 (`Settings.json`, `AccessGrants.json`, profiles, virtual-device overrides, installed mods) is refused until updated.
- Order: this change lands first, so every other alpha.2 change writes `v1alpha2` documents.
