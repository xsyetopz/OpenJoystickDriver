## Why

Until `v1.0.0`, any schema may change in any release. A schema change must not strand the files a
user wrote: OJD 0.6.0-alpha.2 refuses each `openjoystickdriver/v1alpha1` file from 0.6.0-alpha.1
with `E5001`, and the user has no step but editing JSON by hand. Readers stay single-version; the
conversion is an explicit step the user runs.

## What Changes

- A migration step per older `apiVersion` converts one document kind to the current version, as a
  pure JSON transform. Kinds: `Settings`, `AccessGrants`, `Profile`, `Controller`,
  `ControllerPatch`, `VirtualDevice`. Installed mods are third-party packages and are not migrated.
- `ojd migrate` finds every stale document, converts it, checks the result with the current reader,
  writes it atomically, and keeps the original in `Migrated/`. `--dry-run` writes nothing.
- A file with no mechanical mapping is reported with a named error, stays unchanged, and is still
  `E5001` on load.
- The Access & readiness error card and the refused-settings launch alert offer **Migrate**, which
  runs the same code and retries.
- The rules and docs that said "no migrations" say "explicit migration, single-version readers".

## Capabilities

### New Capabilities

- `document-migration`: converting stale stored documents to the current `apiVersion`.

### Modified Capabilities

- `api-version`: a stale file is refused on load and left unchanged, and `ojd migrate` converts it.

## Impact

`Sources/OpenJoystickDriverKit/Migration/`, `Sources/OpenJoystickDriverCLI/Commands/Migrate/`,
`Sources/OpenJoystickDriverPresentation`, `Resources/ErrorCodes.json`, `Resources/Schemas`
(`cli-output`), the localization catalogs, `.claude/rules/single_format.md`, the wiki and
`CHANGELOG.md`.
