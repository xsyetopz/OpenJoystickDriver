# AGENTS.md

- Read `CONTRIBUTING.md` (`#ai-agents`), `LOCALIZATION.md`, `wiki/Home.md`, and `Resources/Schemas/AGENTS.md` first.
- Follow the active `openspec/changes/` change; ground claims in source, tests, schemas, or hardware evidence.
- Before `v1.0.0`, validate and reject invalid names and shapes; preserve one clear format without aliases, shims, fallbacks, retries, or migrations.
- Find every reference before removing code. Name behavior explicitly, test it, and document it for users.
- Keep comments and docs current; put history only in `CHANGELOG.md`.
- Generate, rather than edit, controller and DriverKit files: `./Scripts/ojd catalog regenerate --write` and `./Scripts/ojd driverkit generate`.
- Review translations against `LOCALIZATION.md`; regenerate errors after changing `Resources/ErrorCodes.json`.
- Record Swift-rejected catalog cases in `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections/`; use `"schema": true` only for schema-only failures.
- Preserve SVGs and keep secrets out of the repository. Confirm destructive writes and publication.
- Treat Swift as canonical; have Python call Swift or consume its output rather than duplicate its logic.
- Build once, test changed code, then run `just check` once; rerun only failures. `just check-fast` skips build and tests.

## Duplication

Call `mcp__jscpd__check_duplication` with each function or block before you write it, and reuse the code it finds. Call `mcp__jscpd__get_file_clones` before you refactor a file, and `mcp__jscpd__check_current_directory` after you edit files.
