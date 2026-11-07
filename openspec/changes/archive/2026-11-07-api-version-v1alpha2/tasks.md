# Tasks: API Version v1alpha2

This change lands before every other alpha.2 change. Each task names its check.

## 1. Tests and Spec First

- [x] 1.1 Change every test fixture to `v1alpha2`, and add `v1alpha1` refusal cases to `ProfileCommandTests` (`profile validate`), `SettingsStoreTests` and `AccessGrantStoreTests`. Verify: `test_schema_naming.py` fails before task 2.1 and passes after it; the three suites pass.
- [x] 1.2 The settings alert: `SettingsFileStartup.decide` offers recovery for every `SettingsStoreError`, and the `v1alpha1` case of `SettingsStoreTests` gives one with `E5001`. No new string. Verify: `SettingsStoreTests` and `SettingsFileRecoveryTests` pass.
- [x] 1.3 Replace `v1alpha1` with `v1alpha2` in the `platform-neutral-redesign` proposal, design, tasks and its `schema-versioning`, `sdk-endpoint`, `mod-sdk` and `mod-packages` specs. Verify: `validate platform-neutral-redesign --strict` lists only its three long-requirement warnings.

## 2. Constant, Schemas and Data

- [x] 2.1 Set `OpenJoystickDriverAPI.version` and `schemaBase` to `v1alpha2`. Verify: `just check`.
- [x] 2.2 Change the 17 schemas and every authored file under `Resources`. Verify: `./Scripts/ojd check schemas`.
- [x] 2.3 Make `catalog regenerate --write` write the bundled copies first and build the tool again after them, test first in `ProtocolCopyTests`. Run `catalog regenerate --write`, `errors regenerate --write` and `vocabulary regenerate --write`. Verify: the new test fails before the fix and passes after it; `catalog regenerate --check` passes.
- [x] 2.4 Update `Scripts/SDK/reference_client.py`, `Tools/BridgeCore`, the two WebRTCBridge tests and the docs samples. Verify: `grep -rln v1alpha1 Sources Resources Scripts Tools docs` is empty, and `wiki` names it only in the update section; `swift test` in `Tools/WebRTCBridge` passes.

## 3. User-Facing Text

- [x] 3.1 A refused `AccessGrants.json` keeps the endpoint off (`EndpointServer.start`) and fails each `ojd access` command. Verify: `AccessGrantStoreTests` passes with its `v1alpha1` case.
- [x] 3.2 Add "Update from 0.6.0-alpha.1" to `wiki/Updating-and-Uninstalling.md`, and replace `v1alpha1` in `docs` and `wiki`. Verify: markdownlint.
- [x] 3.3 Rewrite the `ci.yml` checkout comment. Verify: `actionlint` reports only the `runs-on: xcode-27` label on line 20.
- [x] 3.4 Add the **BREAKING** entry and the generator entry to `CHANGELOG.md` `[Unreleased]`. Verify: markdownlint.

## 4. Checks

- [x] 4.1 Build once, run the changed tests and `swift test` in `Tools/WebRTCBridge`, then `just check` once. Verify: exit 0.
