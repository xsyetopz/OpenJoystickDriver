# Tasks: ZD O+ Switch Mode

No reporter is available, so group 1 can be run by anyone with an `11C0` ZD pad. Groups 2 and 3 do not wait for it; group 4 does.

## Working Agreements

- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/`; change `Resources/Controllers/`, then `./Scripts/ojd catalog regenerate --write` and, after a match-list change, `./Scripts/ojd driverkit generate`.
- A record Swift rejects gets a case in `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections/`.
- Docs state current behavior with no history words.
- A task is done only after its Verify command ran in the session that closes it.

## 1. Tester Evidence (Hardware, Testers)

Owns: `docs/testing/zd-o-plus.md`.
Depends: none.
Verify: `markdownlint docs/testing/zd-o-plus.md`.

- [ ] 1.1 Write `docs/testing/zd-o-plus.md` with the steps for any owner of a ZD O+ (or another `11C0` ZD pad). Not run yet. The tester sends back, for each of (i) OJD stopped and (ii) OJD running: the mode the pad shows (`11C0:5505` or `057E:2009`) and its `bInterval`; the `ioreg -l -w0 -r -c IOUSBHostDevice` entry with the USB serial, manufacturer string, product string and `bcdDevice`; and whether the pad comes up as `11C0:5505` when nothing handshakes.
- [ ] 1.2 Apply the result to the Open decision in `design.md` (O1) and record the choice there.

## 2. Diagnose Check

Owns: `Sources/OpenJoystickDriverKit/Diagnostics/DiagnosticsService.swift`, `Sources/OpenJoystickDriverCLI/Commands/Diagnose/DiagnoseChecks.swift`, `Sources/OpenJoystickDriverKit/Resources/*.lproj/Localizable.strings`.
Depends: none.
Verify: `swift test --filter Diagnos`.

- [ ] 2.1 Find how the snapshot exposes connected controllers and whether it carries the USB serial; if it does not, record that here and stop before inventing a source.
- [ ] 2.2 Write `diagnoseWarnsOnPlaceholderSwitchSerial`, `diagnosePassesOtherSwitchSerial` and `diagnoseSkipsWithoutSwitchIdentity`.
- [ ] 2.3 Add the check beside `recordCheck` and `inputMappingCheck` in `DiagnosticsService.checks`; add the message to the localization files and review translations against `LOCALIZATION.md`.

## 3. Docs

Owns: `wiki/Known-Issues.md`, `CHANGELOG.md`.
Depends: 2.

- [ ] 3.1 Add a Known Issues entry: some pads report `057E:2009` with serial `000000000001` in Switch mode, `ojd diagnose` names them, and the report interval is the pad's own unless group 4 shows otherwise.
- [ ] 3.2 Add to `CHANGELOG.md` under `[Unreleased]` / `### Added`: `ojd diagnose` reports a `057E:2009` controller with serial `000000000001`.

## 4. Gated: Branch (a) or (b)

Depends: 1.2. Do not start before it.

- [ ] 4.1 If (a): add the mode match, the no-handshake binding and the `11c0-5505` record per design O1 only if the pad's strings or `bcdDevice` differ from a genuine Pro Controller; add tests, regenerate, and confirm the G50S still binds `NintendoSwitch1`.
- [ ] 4.2 If (b): write the wiki steps per design O1.
