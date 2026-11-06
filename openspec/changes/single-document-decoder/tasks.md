# Tasks: Single Document Decoder

Each task names its check. Error codes stay as they are; only message text may change.

## 1. Parity First

- [ ] 1.1 Add `OrderedJSONTests` cases showing that `OrderedJSON.parse` refuses every input `JSONSerialization` refuses (design Risks): lone surrogate escape, raw control character in a string, leading zero, trailing comma, `NaN`, nesting beyond the parser limit. Verify: `swift test --filter OrderedJSONTests` passes; a case the parser accepts is fixed in the parser, not skipped.

## 2. Controller and Patch Files

- [ ] 2.1 Add `OpenJoystickDriverAPI.requireHeader(apiVersion:kind:expected:file:)` for values read from `OrderedJSON`, and use it in `ControllerRecordSet.parse` and `ControllerPatch.parse` in place of the `JSONSerialization` object (design D2). Verify: `swift test --filter ControllerRecordSetTests` and `SchemaRejectionTests` pass.
- [ ] 2.2 Delete `ControllerRecordSet.jsonObject` and its calls in `loadCatalog` and `RepositoryValidation+Patches`, and the `JSONSerialization` check in `ControllerDefaults.validate` (design D2). Verify: `rg 'jsonObject\(' Sources/OpenJoystickDriverKit/Protocol` finds no call that parses a document file; `swift test --filter 'ControllerRecordSet|ControllerDefaults|RepositoryValidation|OJDRepositoryTool'` passes.
- [ ] 2.3 `ModPackageStore.requireKind` reads `kind` from `OrderedJSON.parse` (design D2). Verify: `swift test --filter ModPackage` passes.
- [ ] 2.4 `ControllerRecordProbePlan.init(data:)` reads through `requireUTF8`, `ordered` and `decode` (design D3). Add tests: a record that names a member twice and one with a byte order mark fail with E5007; a bundled model still builds a plan. Verify: `swift test --filter ControllerRecordProbePlan` passes.
- [ ] 2.5 `SystemGamepadSupportAudit.bundledOJDRecords()` returns the models of `ControllerRecordSet.bundled` and drops its bundle scan and `ProfileDocument` (design D4). Verify: `swift test --filter SystemGamepadSupportAudit` passes; the count equals the generated catalog's record count.

## 3. Virtual-Device Files

- [ ] 3.1 Replace the `[String: Any]` decoder in `VirtualDevice+Decoding.swift` with a strict `Decodable` document (design D5). Keep the header check first and the persona/match rules after decoding. Verify: `swift test --filter 'VirtualDevice|VirtualHIDProfileOverrideStore'` passes; tests show an unknown member gives E5007 and a wrong `kind` gives E5001.

## 4. Docs and Whole Check

- [ ] 4.1 Update `wiki/Controller-Records.md` so it lists the commands that read a file and give the same verdict, and add a CHANGELOG entry (`ojd diagnose record` now refuses non-UTF-8 text and a member named twice). Verify: markdownlint passes on both files.
- [ ] 4.2 Run the full check. Verify: `just check` passes; rerun only failures.
