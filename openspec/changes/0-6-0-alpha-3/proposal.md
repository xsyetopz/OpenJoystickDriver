# 0.6.0-alpha.3

## Why

Users of 0.6.0-alpha.2 and the maintainer report six groups of failures and requests, and the open issues and pull requests wait on decisions this release makes.

1. **8BitDo.** The Ultimate 2C Wireless is reported to work only by cable (#34). On the maintainer's pad the 2.4 GHz receiver works while the pad is in XInput mode, where it re-enumerates as `2DC8:310A`. In DInput mode the receiver keeps `2DC8:301C`, which is bundled as an idle identity, so OJD lists no controller for it. Over Bluetooth LE (`2DC8:301B`) OJD decodes every control except the two rear buttons and has no rumble (#41). It leaves the pad to macOS and publishes nothing, and macOS lists no controller for the pad, so no game receives a controller from macOS or from OJD. After `ojd controller claim` OJD publishes its `SDLCompatible` gamepad, which SDL games and Steam read; a GameController game also needs `ojd virtual set game-controller-compatible`. The Ultimate C Wired for Xbox (`2DC8:2027`) and the Ultimate Mini Wired for Xbox (`2DC8:2019`) are listed as Xbox One (GIP) pads and deliver no input (#59).
2. **Xbox USB driver.** The "Repair Xbox USB Driver" button shows no result, the banner appears for people who have no Microsoft controller, and users ask whether the driver extension is needed at all (#59, #18).
3. **Stale documents.** Users who kept `v1alpha1` files see `E5001` and get no way forward: the Access area offers only "Try Again", and the Profiles area calls the profile corrupted and offers only "Delete" (#59 screenshots, #58).
4. **Schemas.** The 15 schema files hold 308 descriptions that name Swift types, file paths, commands, and runtime behavior, and some documents carry prose-only properties.

5. **The app's interface.** The maintainer reports that the menu bar item has no clear purpose and its options are hard to navigate, that users say dropdowns and other options in the window do nothing, and that the scale of the window is questionable. Source reading backs each: the menu is three levels deep and its status line can read "Needs attention" with no named problem; several controls return without a message, need a separate Apply button that nothing points to, or show a stored value that is not in force; and one profile, one virtual gamepad, and one driver extension each carry several names.
6. **What users ask for.** Users ask for per-app profiles they can set without typing an identifier, for the mapper features of InputConfig that OJD lacks, for tester builds they can download, and, in #63, for a controller whose bundled record does not fit its dongle and which no patch can fix.

A further input is the proposal `controller-schema-migration-proposal.md`: property lists for storage and JavaScriptCore for generator scripts. `design.md` records the checks run on it. Both hold up on the repository's real data, so this change adopts both.

One rule orders all of it: a controller works when it is plugged in; in the rare other case a patch or a record fixes it; nobody edits source for a controller. The branch is close: the classifier binds a controller with no record by its interface signature or HID descriptor, and Swift names a model in five lines. `design.md` lists the five places where a controller still needs a source change, and this change closes four of them and measures the fifth.

## What Changes

- **Support is a ladder: nothing, a patch, a record, a generator script, and source only for a protocol family OJD lacks.** Every controller fix in this release lands as data. A repository check keeps model identifiers out of Swift.
- **BREAKING**: a record's input layouts apply to every protocol family, so a device with its own report shape, such as a GIP wheel, is a record.
- **BREAKING**: `idle` moves from the record to the mode and names its reason, so a receiver that is idle only while no pad is linked, and a bootloader identity, are record data.
- `v1alpha3` takes every breaking change to the document contract that is known today, so later versions add to it and do not reshape it.
- **8BitDo Ultimate 2C Wireless is supported in all three modes**: cable (`2DC8:310A`), 2.4 GHz receiver (`2DC8:310A` with the pad in XInput mode, `2DC8:301C` in DInput mode), and Bluetooth LE (`2DC8:301B`), with input and the rear buttons, each proved by a capture, and with rumble wherever a capture shows a write that runs a motor.
- The receiver identity is idle only while no controller is linked to it.
- **OJD leaves a pad to macOS only when macOS lists a controller for it.** `GCController.supportsHIDDevice` alone decides it on the branch, and for the 2C over Bluetooth LE that answer is yes while GameController lists nothing. The `2DC8:301B` record names OJD as its server.
- The Ultimate C Wired for Xbox and Ultimate Mini Wired for Xbox get a startup sequence compared against the Linux capture from #59, and a session that has received no input says so.
- **The driver extension is optional.** OJD never requests it on its own. A Microsoft model that no driver owns is served on the direct USB route. The extension serves only the models Apple's own driver holds, after the user claims them.
- The repair button shows progress, the result, and the macOS error. The banner appears only when a connected controller needs the extension.
- **BREAKING**: `apiVersion` becomes `openjoystickdriver/v1alpha3`. Readers accept only that version.
- **BREAKING**: stored documents become XML property lists (`.plist`): bundled records, patches, protocol descriptions, catalog rules, the crosswalk, virtual devices, and every document a user keeps. A user-defined record or patch follows the same schema as a bundled one. `ojd --json` output and the local endpoint stay JSON.
- **BREAKING**: a patch deletes a key through a `remove` list, because a property list has no `null`.
- **Migration reaches every stale document.** `ojd migrate` converts `v1alpha1` and `v1alpha2` JSON documents to `v1alpha3` property lists in one run, covers every user store, gives every file a verdict, and runs at service start with a backup. Every screen that reports `E5001` offers Migrate.
- **Generator scripts.** `ojd generate <script.js>` runs a JavaScript file with JavaScriptCore in a helper process and writes the documents it returns, after the same checks a hand-written file gets. The service and the app never run a script.
- The wiki shows how AppleScript, JavaScript for Automation, and Shortcuts drive OJD through the command line and the App Intents it already has.
- **BREAKING**: schemas follow one description style taken from Apple's published conventions: one sentence fragment that says what the value is. Prose-only properties leave the schemas and the bundled documents.
- Each open issue and pull request gets its fix, its record, or a named gate (reporter evidence or hardware).
- **A patch reaches every section of a record and changes one mode by its `id`**, so the controller of #63 is fixed by a patch on the user's Mac. `ojd record draft` works for a controller OJD does not serve. A controller whose record fits none of its interfaces falls back to its HID descriptor.
- **Every control acts or says why it cannot.** A choice applies when chosen; a refusal appears beside the control; a control offers only what the service accepts and shows the value in force.
- **The menu bar item has a stated purpose**: controller state, profile choice, pause, open, quit. Each controller is a row with its battery and profile, a problem row names the problem and opens its fix, and the menu is two levels deep.
- **The toolbar buttons of the main window stay.** They are intended, and Apple Notes uses the same form. Each gets a menu command.
- **One "Interface" setting with Simple and Advanced**, as OBS offers its output mode. Simple shows what connecting and playing need. The level hides controls and changes no behavior.
- **One term for one concept**, defined in a glossary and enforced on the English strings: "profile" only for remapping, virtual gamepad kinds named by what reads them, one name for the driver extension.
- **BREAKING**: a profile's `applicationScope` holds `appIDs`, a list, so one profile serves several apps. The user picks apps from a list of running and installed apps.
- **Mapper features users ask for**: a live controller view drawn from the record, a calibration view, profile templates that fit any controller, profile conversion between models, a pause shortcut, idle disconnect, more system actions, and in-app help.
- Tester builds are public pre-releases, linked from the issue they answer.
- The interface is measured before it changes: an audit lists each view against its Human Interface Guidelines page and an Apple app on the maintainer's Mac.

## Capabilities

### New Capabilities

- `record-driven-support`: serving a controller with no record, the per-model facts a record states, idle modes, input layouts for every family, and the path from a controller to an installed record.
- `eightbitdo-controllers`: the 8BitDo Ultimate 2C Wireless in its three modes, the receiver's idle state, and the 8BitDo GIP pads.
- `driver-extension-setup`: when OJD asks for the Xbox USB driver extension, what the repair button shows, and when the banner appears.
- `usb-route-selection`: which route serves a Microsoft GIP model, with and without the driver extension.
- `api-version`: the one `apiVersion` this release reads and writes.
- `document-migration`: converting stale user documents from every earlier version, in every store, from the command line and the app.
- `document-format`: property-list storage of documents, the schema that checks them, and key removal in patches.
- `document-generators`: generating documents from a JavaScript file, and the limits on that script.
- `schema-style`: the wording rules of schema descriptions and the removal of prose-only properties.
- `controller-coverage`: the controller defects and records the open issues and pull requests ask for.
- `app-interface`: what every control of the window does when used, the toolbar and its menu commands, sizes and text styles, the three controller states, first-start setup, in-app help, and the audit against the Human Interface Guidelines.
- `menu-bar-item`: the purpose, rows, depth, and labels of the menu bar item, and how the user removes it.
- `interface-level`: the Simple and Advanced levels of the interface.
- `terminology`: the glossary and the one term each concept has in the app, the command line, and the wiki.
- `per-app-profiles`: choosing apps for a profile from a list, several apps per profile, and showing the profile in force.
- `mapper-features`: the live controller view, calibration, templates, profile conversion, the pause shortcut, idle disconnect, system actions, and the changes shown after an update.
- `status-reporting`: when Input Test reports activity, the sentence and next step for each reason a controller is not served, and the content of a document refusal.
- `release-distribution`: public tester builds and how the update check finds them.

### Modified Capabilities

None. `openspec/specs/` is empty: commit `f1921573e` removed the earlier specs.

## Impact

- **Code**: `OpenJoystickDriverKit` (classifier, HID drivers, GIP driver, migration, API version), `OpenJoystickDriverService` (route selection, driver extension client, profile library), `OpenJoystickDriverPresentation` (banner, Access, Profiles, Settings), `OpenJoystickDriverUSB` (interrupt transfer timeout), `OpenJoystickDriverCLI` (`migrate`, `generate`, `record`, `transport-extension`, `controller claim`). The layout decoder and the idle state move from one family and one flag to every family and every mode (`ProtocolDriverRegistry.swift`, `ControllerRecordDocument.swift`, `ProtocolClassifier.swift`, `ControllerModelID.swift`).
- **Data**: every document under `Resources/Controllers/`, `Resources/ControllerPatches/`, `Resources/Protocols/`, `Resources/CatalogRules/`, `Resources/Vocabulary/`, and `Resources/VirtualDevices/` changes from `.json` to `.plist`, with the generated copies under `Sources/OpenJoystickDriverKit/Resources/`. All 15 files in `Resources/Schemas/` change and stay JSON Schema.
- **Code that reads documents**: 144 `JSONDecoder`, `JSONEncoder`, and `JSONSerialization` sites in `Sources/`, 616 in `Tests/`, and 27 Python files under `Scripts/`, `Tools/`, and `Tests/RepositoryScripts/`. Each site that handles a stored document moves to the property-list API; each site that handles a message stays.
- **Users**: every stored document is rewritten to a `v1alpha3` property list at first start, with the old file kept in `Migrated/`. Mod packages and pull requests written as JSON need `ojd migrate <folder>`.
- **Docs**: `wiki/Controller-Records.md`, `wiki/Writing-Controller-Mods.md`, `wiki/Automating-OpenJoystickDriver.md`, `llms.txt`, `llms-full.txt`, `wiki/Command-Reference.md`, `docs/development/apple-controller-ownership.md`, `docs/testing/8bitdo-ultimate-2c.md`, `CHANGELOG.md`, `Scripts/SDK/reference_client.py`.
- **Hardware**: the maintainer owns the 2C, so its cable, receiver, and Bluetooth tasks are done in the apply session with the pad. Every controller the maintainer does not own (`2DC8:2027`, `2DC8:2019`, `045E:02E3`, `045E:02D1`, `044F:B671`, and others in `tasks.md`) waits for its reporter's capture.
- **Interface**: `Sources/OpenJoystickDriverPresentation` (the status menu in `MenuBar/`, the controller pickers in `Controllers/Inventory/`, `Controllers/InputTest/`, `Profiles/Editor/`, `SettingsWindow/`, `MainWindow/`), every string file under `Sources/OpenJoystickDriverKit/Resources/*.lproj`, `profile.schema.json` and `settings.schema.json`, `wiki/Using-the-App.md`, `wiki/Remapping-Profiles.md`, `wiki/Home.md`, a `wiki/Glossary.md`, and `docs/development/menu-bar-settings-architecture.md`.
- **Scope**: groups 10 to 12, 14, and 17 of `tasks.md` fix what users and the maintainer report. Groups 13, 15, and 16 add features; each can leave this release without changing another group, and the maintainer decides which stay.
- **License**: OJD is under MPL-2.0, which permits commercial use (`design.md`, Open Questions, "Businesses", resolved). InputConfig is MIT; this change copies none of its code.
- **Others see it**: closing issues and merging or closing pull requests are the maintainer's actions; the tasks prepare them and do not perform them. Publishing a tester build as a pre-release is also the maintainer's action.
