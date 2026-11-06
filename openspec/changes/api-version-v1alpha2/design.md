## Context

- One Swift constant holds the version (`OpenJoystickDriverAPI.swift:7`) and one the `$id` base (`:10`). `headerProblem` (`:18`) refuses any other `apiVersion` with `E5001` and names the found and supported versions.
- Python reads both through `OJDRepositoryTool facts` (`Scripts/Quality/repository_tool.py:134`). The catalog generator writes headers from it (`Scripts/Catalog/schema_header.py:37`).
- `platform-neutral-redesign/specs/schema-versioning/spec.md:5,28` names `v1alpha1` literally, and its "Single version constant" requirement has a test that the constant equals every schema's const.
- No script compares schemas with a release tag. `validate_schemas.py` validates documents and runs `ojd diagnose`; `ci.yml:29` says otherwise. CI needs the full history for `bundle_version.py:79`.
- `Scripts/SDK/reference_client.py` and `Tools/BridgeCore` are outside clients and hold their own copy of the string, as a third-party client would.

## Decisions

### D1. One Version for All Documents

Every schema and document kind moves to `v1alpha2` together, because one constant drives them all and the spec requires the constant to equal every schema's const. A per-kind version would need a second constant and a reader per kind, which the no-compatibility rule forbids.

### D2. No Reader for `v1alpha1`

`v1alpha1` fails like any unknown version: `E5001` with the existing message, "apiVersion openjoystickdriver/v1alpha1 is not supported; the supported apiVersion is openjoystickdriver/v1alpha2". No code names `v1alpha1` after this change, except the tests that feed it as an unsupported value.

### D3. How Users Bring Files Back

Each stored file has a path out, written in the "Update from 0.6.0-alpha.1" section of `wiki/Updating-and-Uninstalling.md` and linked from the CHANGELOG entry:

- `Settings.json`: the app already shows an alert for a refused file at launch; `ojd setting reset` moves it to the Trash.
- `AccessGrants.json`: the endpoint stays off (`EndpointServer.swift:127`) and each `ojd access` command fails with `E5001`; edit the `apiVersion` line, or move the file to the Trash and grant again.
- Profiles: change the `apiVersion` line by hand, then `ojd profile validate FILE`. A profile that uses `doubleTap` also needs `multiTap` (`remapper-actions`).
- User controller records: OJD skips the file and uses the bundled record; change the line, then `ojd record validate FILE`. Virtual device files are skipped too; change the line.
- Mods: the author publishes a `v1alpha2` package; `ojd mod validate` names what fails.

### D4. Outside Clients Change by Hand

`reference_client.py` and `BridgeCore` keep their own literal, because they show how a client outside the Kit speaks the endpoint. Their tests send `v1alpha2` and expect `Welcome`.

### D5. the CI Comment

`ci.yml:29` states the real reason for `fetch-depth: 0`: the bundle version counts commits. Adding a release-tag schema compare is not part of this change.

## Risks / Trade-Offs

- **Testers lose settings, grants and profiles on update.** The wiki page and the CHANGELOG entry say so before they update, and every refusal names `E5001`.
- **The `$id` URLs are not served.** No workflow publishes `Resources/Schemas`; this change keeps that as it is, and schemas are never fetched at run time.
