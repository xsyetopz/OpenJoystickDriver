# Tasks: declarative input layouts

Status: proposal. No task is started. Target release: alpha.2.

## Working agreements

- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`. Change authored inputs, then run `./Scripts/ojd catalog regenerate --write`.
- No compatibility reader for `byte`, `mask` or `bits`: replace them everywhere in this change.
- Docs state current behavior; no history words. History goes only in `CHANGELOG.md`.
- Order of work: write all code for a group, build once, test the changed area, run `just check` once; rerun only failures.
- Archive after `platform-neutral-redesign` is archived, so `controller-records` exists in `openspec/specs/`.

## 1. Tests first

Owns: failing tests that fix the behavior in `specs/controller-records/spec.md`.
Depends: none.

- [x] 1.1 Add `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/BitAddressedFieldTests.swift`: 12-bit field across a byte, 10-bit, 16-bit trigger at a bit offset, 32-bit field, signed two's complement, `BigEndian` 16, 24 and 32 bits, default `LittleEndian`, `bitSize` 0 and 33, field in the ID byte, field past the length. Verify: `swift test --filter BitAddressedFieldTests` fails before 2.1 and passes after it. Done: `BitAddressedFieldTests` covers every listed case; it passes with the 2.1 code.
- [x] 1.2 Add `ConditionalInputLayoutTests.swift` in the same folder: two layouts by report ID, selection by `atLeast` and `exactly`, overlap rejected, unselected report ignored, layout carry keeps a control a report does not name. Verify: `swift test --filter ConditionalInputLayoutTests` fails before 2.3 and passes after it. Done: `ConditionalInputLayoutTests` covers selection by ID and length, overlap, the unselected report and layout carry; it passes.
- [x] 1.3 Extend `HIDUsageMapTests.swift` and `HIDDescriptorDriverTests.swift` with `HalfAxis`, `AxisDpad`, `AxisButton` and `ButtonTrigger` cases from the spec scenarios, including a missing `threshold`, both halves of one usage, the same half twice, and a whole axis plus a half. Extend `Tests/HIDUsageGolden/hid-usage-layouts.txt` with one line group per kind. Verify: `swift test --filter HIDUsageMapTests` and `--filter HIDDescriptorDriverTests` fail before 2.4 and pass after it. Done: `HIDUsageMapTests`, `HIDDescriptorDriverTests` and four new groups in `hid-usage-layouts.txt` cover the four kinds; they pass.
- [x] 1.4 Add SchemaRejections cases in `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections/controller.json` for: removed keys `byte`, `mask`, `bits`; `bitSize` 33; unaligned `BigEndian`; overlapping selectors; a 65-byte length; a missing `threshold`; one half twice. Set `"schema": true` only where the JSON Schema alone rejects. Verify: `swift test --filter SchemaRejectionTests` fails before 2.1 to 2.4 and passes after them. Done: SchemaRejections cases added in `controller.json` (and the converted `protocol-description.json`); `SchemaRejection` passes and `test_schema_rejection_flags` passes.
- [x] 1.5 Confirm the snapshots of the five converted records exist in `Tests/EquivalenceSnapshots` (platform-neutral-redesign task 1.1) and fail the build on any frame difference. Verify: `swift test --filter EquivalenceSnapshotTests` passes on the unchanged tree. Done: the snapshots exist and `EquivalenceSnapshotTests` passed on the unchanged tree and passes after the change.

## 2. Schema and Swift

Owns: `Resources/Schemas/controller.schema.json`, `Resources/Schemas/protocol-description.schema.json` (input layout text), `Sources/OpenJoystickDriverKit/Protocol/`.
Depends: 1.
Verify: `./Scripts/ojd check schemas`, `swift test`.

- [x] 2.1 Replace `byte`, `mask` and `bits` with `bitOffset`, `bitSize`, `byteOrder`, `signed`, and 32-bit `min` and `max` in `inputField`, `inputButton`, `inputAxis`, `inputHatSource` and `inputTrigger`. Change `ReportBitField` and `ControllerInputLayout.Axis` and `Trigger` to bit addressing and a 64-bit read path with `Double` normalization. Verify: `swift test --filter BitAddressedFieldTests` and `--filter ControllerInputLayoutTests` pass. Done: `BitAddressedFieldTests` and `ControllerInputLayoutTests` pass.
- [x] 2.2 Update `ControllerRecordDocument+InputLayout.swift` to decode the bit-addressing keys, reject the removed keys as unknown, and validate bounds, ID byte, length and `BigEndian` alignment with `ControllerRecordProblem` messages. Verify: `swift test --filter SchemaRejectionTests` passes for the 1.4 field cases. Done: `SchemaRejection` passes for the field cases.
- [x] 2.3 Add `layouts` to `input`, selector overlap detection, the "Unselected report" rule and layout carry in `ControllerInputLayout` and `ReportLayoutDriver`; keep the 64-byte ceiling with a message that names it. Update the `input` schema `oneOf`. Verify: `swift test --filter ConditionalInputLayoutTests` passes. Done: `ConditionalInputLayoutTests` passes.
- [x] 2.4 Add the four kinds to `HIDUsageMap.Binding`, the decoder (`kind is Button, Axis, Hat, HalfAxis, AxisDpad, AxisButton or ButtonTrigger`), the schema `hidUsage` `oneOf`, the per-half uniqueness rule, `HIDUsageMap` `controls` (the capability set used by `HIDUsageMap.swift:170`), and the fold in `HIDDescriptorDriver`. Verify: `swift test --filter HIDUsageMapTests` and `--filter HIDDescriptorDriverTests` pass; `./Scripts/ojd check profiles` passes. Done: `HIDUsageMapTests` and `HIDDescriptorDriverTests` pass; `Scripts.Quality.check_profiles` validates 696 records (run through plain `swift`, see 4.4).
- [ ] 2.5 Search every reader of the removed keys: `grep -rn '"mask"\|"byte"\|"bits"' Scripts Sources Resources Tests Tools` and remove or convert each hit that belongs to an input field. Verify: the grep lists no input-field hit; `pyright` and `ruff check Scripts Tests/RepositoryScripts` pass.

## 3. Data

Owns: authored records and descriptions that use the removed keys.
Depends: 2.
Verify: `./Scripts/ojd catalog regenerate --check`, `swift test --filter EquivalenceSnapshotTests`.

- [x] 3.1 Convert `Resources/Controllers/2563/2563-0575.json`, `Resources/ControllerPatches/046d/046d-cad1.patch.json`, `Resources/Protocols/vendor-flydigi.json`, `Resources/Protocols/xbox-xid.json` and `Resources/Protocols/nintendo-switch-input-only.json` to `bitOffset`, `bitSize` and `layouts`. Verify: `./Scripts/ojd check profiles` and `./Scripts/ojd check schemas` pass. Done: `Scripts.Quality.check_profiles` and `Scripts.Quality.validate_schemas` pass (run through plain `swift`, see 4.4).
- [ ] 3.2 Regenerate the records and the protocol copies under `Sources/OpenJoystickDriverKit/Resources/` with `./Scripts/ojd catalog regenerate --write`, using whatever sync step the repository provides for `Resources/Protocols`. Verify: `./Scripts/ojd catalog regenerate --check` exits 0 and `git diff --stat` lists only the files of 3.1 and their generated copies.
- [x] 3.3 Prove no behavior change. Verify: `swift test --filter EquivalenceSnapshotTests` reports zero frame differences for the five records. Done: `EquivalenceSnapshotTests` passes with zero frame differences.

## 4. Docs, wiki and CHANGELOG

Owns: `wiki/Controller-Records.md`, `docs/development/`, `CHANGELOG.md`.
Depends: 3.
Verify: markdownlint over the changed files; `grep -n 'byte\b.*mask' wiki/Controller-Records.md` finds no input-field text.

- [x] 4.1 Rewrite the input section of `wiki/Controller-Records.md` (lines 96-99) for `bitOffset`, `bitSize`, `byteOrder`, `signed`, range and `layouts`, including the rules "Unselected report" and "Layout carry" and the 64-byte ceiling. Verify: `bunx markdownlint-cli2 wiki/Controller-Records.md` exits 0. Done: the input section describes bit addressing, `layouts`, Unselected report, Layout carry and the 64-byte ceiling; markdownlint passes and the grep finds no input-field text.
- [x] 4.2 Describe the four usage map kinds, `threshold`, and per-half uniqueness in the `hidUsageMap` section (lines 313-320). Verify: markdownlint exits 0 and a scan of the added lines finds none of the words renamed, was, now, new, old, legacy. Done: the four kinds, `threshold` and per-half uniqueness are in the Map HID Usages section; markdownlint passes and the added lines hold none of the listed words.
- [x] 4.3 Add `CHANGELOG.md` entries under `[Unreleased]`: Added (layouts, kinds) and Changed (**BREAKING** field keys). Verify: markdownlint exits 0. Done: Added and Changed (**BREAKING**) entries under `[Unreleased]`; markdownlint passes.
- [ ] 4.4 Run the full check list from the repository `CLAUDE.md` once. Verify: `just check` exits 0.

## Hardware Checks (Maintainer)

The maintainer sends tester builds to the Discord testers (`docs/development/tester-builds.md`); each tester result is recorded in the wiki. A pad that nobody owns does not block the release.

- [ ] H1 A pad of each converted record that a tester owns (Logitech `046D:CAD1`, `2563:0575`): `ojd controller watch CONTROLLER --output` shows every control as before the change.
- [ ] H2 SDL comparison for `HalfAxis`: with `Tools/SDLGamepadProbe`, a pad with a combined trigger axis reads the same trigger values in SDL and in OJD.
