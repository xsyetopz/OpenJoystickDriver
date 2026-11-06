# Proposal

## Why

Each reader of a document file parses it its own way. A Controller file is read by `JSONSerialization`, then by `OrderedJSON`, then decoded through a second `JSONSerialization` and `JSONDecoder` pass. `ojd diagnose record` decodes it with `JSONDecoder` alone, so it accepts a byte order mark and a member named twice, which the catalog refuses. Virtual-device files are decoded by hand from `[String: Any]`. A user who writes a record or a patch should get the same verdict from every command that reads it, and the rules should live in one place.

## What Changes

- Controller and ControllerPatch files are read by one reader, `OrderedJSON.parse`, in the catalog loader, the user and package loaders, `OJDRepositoryTool validate controllers` and `apply-patches`, `all.patch.json`, the mod package kind check, and the record probe (`ojd diagnose record`). The `JSONSerialization` pre-pass is removed.
- **BREAKING:** `ojd diagnose record` refuses a record that is not plain UTF-8 or that names a member twice, with E5007, as the catalog does.
- The system gamepad support audit reads the bundled models from `ControllerRecordSet.bundled` instead of scanning and decoding the bundle a second time.
- Virtual-device files are decoded by a strict `Decodable` that refuses unknown members, in place of the hand decoder. The codes stay E5001 and E5007.
- Documents stay JSON. Property lists and JavaScriptCore were considered and rejected (design D1).
- Users keep adding their own Controller files and patching bundled ones in `~/Library/Application Support/OpenJoystickDriver/Controllers/` and mod packages, without changing source.

## Capabilities

### New Capabilities
- `document-decoding`: how OJD reads Controller, ControllerPatch and VirtualDevice files. One reader per kind, and the same verdict from every command that reads a file.

### Modified Capabilities

## Impact

- Code: `Sources/OpenJoystickDriverKit/Protocol/Catalog/` (`ControllerRecordSet`, `+Patches`, `RepositoryValidation+Patches`, `ControllerDefaults`), `Packages/ModPackageStore+Validation.swift`, `Diagnostics/ControllerRecordProbePlan.swift`, `Diagnostics/SystemGamepadSupportAudit.swift`, `Output/Profiles/VirtualDevice+Decoding.swift`.
- Tests: Kit catalog and virtual-device tests, record probe tests, SchemaRejections (no case changes expected).
- Docs: wiki/Controller-Records.md (who reads a file), CHANGELOG.
- No new dependency. No schema change.
