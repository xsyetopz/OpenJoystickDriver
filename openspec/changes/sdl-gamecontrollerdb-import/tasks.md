# Tasks: SDL_GameControllerDB import

Status: proposal. No task is started. Target release: alpha.2. Depends on change `declarative-input-layouts` (tasks 2.4 and 3 of that change) for the map kinds; start the groups below that need them after it lands.

## Working agreements

- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`. The database resource is generated too; change the lock or the generator, then regenerate.
- No hidden behavior: every source choice (record, database, standard map), tier and rejection has a name, a test and user-facing text.
- Swift is canonical. Python only downloads, verifies and filters the database text; it does not convert lines.
- Docs state current behavior; no history words. History goes only in `CHANGELOG.md`.
- Write all code for a group, build once, test the changed area, run `just check` once; rerun only failures.

## 1. Tests and fixtures first

Owns: fixtures and failing tests.
Depends: none.

- [ ] 1.1 Add `dump-elements` to `Sources/OpenJoystickDriverHIDTool` (usage page, usage, cookie, logical range, arrival order, as JSON) and capture lists from the pads testers or the maintainer own, plus a pad with Button-page and Consumer-page buttons to settle the sort key. Store each under `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SDLMappingFixtures/` with its database line and expected `hidUsageMap`. Verify: `swift run OpenJoystickDriverHIDTool dump-elements` prints valid JSON for a connected pad, and the fixture folder has at least three pads.
- [ ] 1.2 Add `SDLElementOrderTests.swift`: axis, hat and button list order, usage-number sort, arrival-order ties, duplicate cookies dropped. Verify: `swift test --filter SDLElementOrderTests` fails before 2.2 and passes after it.
- [ ] 1.3 Add `SDLGUIDTests.swift` and `SDLMappingConverterTests.swift`: GUID from bus, name CRC16, vendor, product, version; `ExactGUID` and `GUIDWithoutNameCRC`; a GUID with no match; a line with half axes; `b#`, `a#`, `h#.#`, `+a#`, `-a#`, `~`; an unmapped control; an index past the list rejects the line. Verify: `swift test --filter SDLGUIDTests` and `--filter SDLMappingConverterTests` fail before 2.3 and pass after it.
- [ ] 1.4 Add `SDLMappingBindingTests.swift`: an unrecorded pad with a line binds with rule `SDLGameControllerDB`; a pad with a record ignores the database; a pad that fails the descriptor contract stays unbound and notes the line; the no-match pad reports `StandardHIDUsageMap`. Verify: `swift test --filter SDLMappingBindingTests` fails before 2.5 and passes after it.
- [ ] 1.5 Add a generator test in `Tests/RepositoryScripts` for the database filter: Mac lines kept, other platforms dropped, controller-list pads skipped and counted, hash mismatch fails, duplicate GUIDs counted. Verify: `.build/schema-validator/bin/python -m unittest discover -s Tests/RepositoryScripts` fails before 3.2 and passes after it.
- [ ] 1.6 Settle `sdlAxisButtonThreshold` and the sort key of the buttons list by comparing a fixture pad with `Tools/SDLGamepadProbe` (SDL reading) and record the numbers in the fixture notes. Verify: the golden test of 1.3 pins the chosen value and the probe output is attached to the fixture.

## 2. Swift

Owns: `Sources/OpenJoystickDriverKit/Protocol/`, `Sources/OpenJoystickDriverMacOSPlatform/HID/`, the CLI and app surfaces.
Depends: 1, and `declarative-input-layouts` 2.4.
Verify: `swift test`.

- [ ] 2.1 Add `HIDElementDescription` (usage page, usage, cookie, logical range, arrival order) and make the platform layer supply it from `IOHIDDeviceCopyMatchingElements` (`HIDDeviceStream+DeviceProperties.swift:35`). Verify: a platform test lists elements of a fake host; `swift test --filter OpenJoystickDriverMacOSPlatformTests` passes.
- [ ] 2.2 Add the pure element-order function (decision 7 of `design.md`). Verify: `swift test --filter SDLElementOrderTests` passes.
- [ ] 2.3 Add the GUID builder, the database loader (index by GUID, last-line rule or the rule found in 2.4), the line parser and the converter to `hidUsageMap`, with the authored table of database control names checked against `vocabulary.schema.json`. Verify: `swift test --filter SDLGUIDTests` and `--filter SDLMappingConverterTests` pass.
- [ ] 2.4 Read SDL's matching and duplicate rules at the pinned commit and settle the open questions of `design.md` (tiers beyond the name CRC, duplicate GUIDs); change the loader and the tests to match, and write the answer in `design.md`. Verify: a test per rule passes; `swift test --filter SDLGUIDTests` passes.
- [ ] 2.5 Bind in `ProtocolClassifier`: no record, descriptor contract passes, line found, conversion ok gives rule `SDLGameControllerDB`; otherwise the named standard map or rejection. Add the `inputMapping` fact to the binding result and the report. Verify: `swift test --filter SDLMappingBindingTests` passes.
- [ ] 2.6 Add `ojd record draft CONTROLLER --from-sdl` and its failure error. Verify: `swift test --filter ControllerRecordDraftTests` passes with a database-mapped fixture; the saved record validates with `./Scripts/ojd check profiles`.
- [ ] 2.7 Add the Input mapping row to `ojd status`, `ojd diagnose`, `ojd controller show` (human, `--plain`, `--json`) and the app's controller detail; extend `Resources/Schemas/cli-output.schema.json` and `report.schema.json`; add the rejection error code to `Resources/ErrorCodes.json` and run `./Scripts/ojd errors regenerate --write`. Verify: `swift test --filter CLIOutputSchemaTests`, `--filter SupportReportBindingTests`, `./Scripts/ojd check schemas` pass.
- [ ] 2.8 Add the localization keys for the row, the tiers, the unmapped list and the rejection in all bundles, reviewed against `LOCALIZATION.md` (Meaning, Punctuation). Verify: `python3 Scripts/Quality/check_localization_keys.py` and `swift test --filter LocalizationTests` pass, and the review notes name each reviewed locale.

## 3. Data

Owns: `ControllerSources.lock.json`, `Scripts/Catalog/`, the generated resource.
Depends: 1.5.
Verify: `./Scripts/ojd catalog regenerate --check`.

- [ ] 3.1 Add the `sdlGameControllerDB` entry to `ControllerSources.lock.json` with repository, commit and SHA-256 of the file, and extend the lock reader in `Scripts/Catalog/xpad_io.py`. Verify: `.build/schema-validator/bin/python -m unittest discover -s Tests/RepositoryScripts` passes; the lock keeps one entry per upstream.
- [ ] 3.2 Add the generator (`Scripts/Catalog/generate_sdl_gamecontrollerdb.py` or a stage of the existing generator): download, verify, keep Mac lines, skip controller-list and catalog pads with counts, write the deterministic resource with the license header. Verify: `./Scripts/ojd catalog regenerate --write` then `--check` exits 0; `ruff format --check Scripts Tests/RepositoryScripts`, `ruff check Scripts Tests/RepositoryScripts` and `pyright` pass.
- [ ] 3.3 Add the zlib entry for SDL_GameControllerDB to `THIRD_PARTY_NOTICES.md`. Verify: a test reads the file and finds the repository, the pinned revision and "zlib".
- [ ] 3.4 Record the resource size and the time to index it on first use. Verify: the numbers are in the task note and the wiki states no timing the test did not measure.

## 4. Docs, wiki and CHANGELOG

Owns: `docs/development/`, `wiki/`, `CHANGELOG.md`.
Depends: 2, 3.
Verify: `bunx markdownlint-cli2` over the changed files.

- [ ] 4.1 Add a section on the database to `docs/development/xpad-import.md` (pin, filter, skip counts) and a line to `docs/development/architecture.md:117` naming the third pinned source. Verify: markdownlint exits 0.
- [ ] 4.2 Update `wiki/Supported-Controllers.md` (Generic HID Controllers: mapped from SDL_GameControllerDB, the standard map, the rejection), `wiki/Command-Reference.md` (`controller show` row and JSON, `record draft --from-sdl`, `status`, `diagnose`) and `wiki/Controller-Records.md` (saving the mapping). Verify: markdownlint exits 0; a scan of added lines finds none of the words renamed, was, now, new, old, legacy.
- [ ] 4.3 Add `CHANGELOG.md` entries under `[Unreleased]` (Added). Verify: markdownlint exits 0.
- [ ] 4.4 Run the full check list from the repository `CLAUDE.md` once. Verify: `just check` exits 0.

## Hardware Checks (Maintainer)

The maintainer sends tester builds to the Discord testers (`docs/development/tester-builds.md`); results go to the wiki. A pad nobody owns does not block the release.

- [ ] H1 Two unrecorded HID pads whose Mac lines work in SDL (a tester names them): `ojd controller show CONTROLLER` says "mapped from SDL_GameControllerDB" and `ojd controller watch CONTROLLER --output` shows every mapped control.
- [ ] H2 Compare with `Tools/SDLGamepadProbe`: each control reads the same in SDL and in OJD for the pads of H1.
- [ ] H3 A pad with a combined trigger axis (half axes): both triggers read 0 to 1 across their halves.
- [ ] H4 An unrecorded pad with no line: the row reads "standard HID usage map".
- [ ] H5 `ojd record draft CONTROLLER --from-sdl` on a mapped pad, reconnect: the row reads `Record`.
