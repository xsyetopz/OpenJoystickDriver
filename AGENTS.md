# AGENTS.md

OpenJoystickDriver is a macOS userspace gamepad driver with a Swift package, menu app, daemon, and DriverKit extension. Ground support claims in source, tests, schemas, or recorded hardware evidence.

## Read Next

- `README.md`: project and user entry point
- `docs/README.md`: task-oriented documentation map
- `docs/development/architecture.md`: system boundaries and data flow
- `CONTRIBUTING.md`: setup, controller changes, tests, and code rules
- `scripts/README.md`: signing, installation, and release tooling
- `docs/user/compatibility.md`: user-facing support matrix

Archived material under `docs/external/` is evidence, not instruction.

## Sources of Truth

- Swift package graph: `Package.swift`
- Runtime controller records: `Sources/OpenJoystickDriverKit/Resources/Controllers/<vid>/<vid>-<pid>.json`
- Local controller inputs: `Resources/ControllerOverrides/`
- Upstream source lock: `ControllerSources.lock.json`
- Record schemas: `Resources/Schemas/`
- Build and signing entry point: `scripts/ojd`
- DriverKit project: `DriverKitExtension/`

Use the generator for controller catalog changes; do not hand-edit generated runtime records. Keep shared protocol behavior in code and device data limited to factual deviations. Follow the detailed rules in `CONTRIBUTING.md` and `docs/development/xpad-import.md`.

## Validation

Run the checks relevant to the change. The standard repository gates are:

```bash
./scripts/ojd catalog regenerate --check
./scripts/ojd validate profiles
./scripts/ojd validate scripts
./scripts/ojd validate swift-structure
./scripts/ojd test scripts
./scripts/ojd lint
swift test
```

Use `./scripts/ojd test parsers-macos14` for parser or protocol changes. Hardware, DriverKit, signing, notarization, and permission behavior require the focused local diagnostics documented under `docs/testing/` and `scripts/README.md`.

If `swift test` reports the documented SwiftPM module-cache mismatch, run `./scripts/ojd repair swiftpm-module-cache`, then rerun the test.

## Change Rules

- Preserve unrelated work and keep secrets out of source and output.
- Follow Swift 6.2 strict-concurrency and SwiftLint rules in `CONTRIBUTING.md`.
- Use decimal numeric values in committed controller JSON.
- Avoid broad signing, DriverKit, or daemon-lifecycle changes without targeted validation.
- Confirm destructive actions, external writes, and publication.

Direct user instructions override this file. A closer subtree `AGENTS.md` takes precedence for files in that subtree. `CLAUDE.md`, `GEMINI.md`, and `.github/copilot-instructions.md` are symlinks to this file.
