# AGENTS.md

OpenJoystickDriver is a macOS userspace gamepad driver with a Swift package, persistent menu-app runtime, and a generated USB DriverKit extension. Ground support claims in source, tests, schemas, or recorded hardware evidence.

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
- Schema policy: `Resources/Schemas/README.md`
- Build and signing entry point: `scripts/ojd`
- USB DriverKit runtime adapter: `Sources/OpenJoystickDriverUSB/`
- DriverKit native-project generator: `Sources/DriverKitGenerator/`
- Generated DriverKit project: `.build/driverkit/generated/` (ephemeral; never edit or commit)
- Resolved package versions: `Package.resolved`

Use the catalog generator for controller catalog changes; do not hand-edit generated runtime records. Use `./scripts/ojd driverkit generate` for the DriverKit native project; do not patch its output. Keep shared protocol behavior in code and device data limited to factual deviations. Follow the detailed rules in `CONTRIBUTING.md` and `docs/development/xpad-import.md`.

## Validation

Run the checks relevant to the change. The standard repository gates are:

```bash
./scripts/ojd catalog regenerate --check
./scripts/ojd check profiles
./scripts/ojd check schemas
./scripts/ojd check scripts
./scripts/ojd check swift-structure
./scripts/ojd lint
./scripts/ojd check driverkit
swift test
```

Use `./scripts/ojd test parsers-macos14` for parser or protocol changes. Hardware, DriverKit, signing, notarization, and permission behavior require the focused local diagnostics documented under `docs/testing/` and `scripts/README.md`.

If `swift test` reports the documented SwiftPM module-cache mismatch, run `./scripts/ojd repair swiftpm-module-cache`, then rerun the test.

## Change Rules

- Never generate SVGs or images.
- Preserve unrelated work and keep secrets out of source and output.
- Follow Swift 6.2 strict-concurrency and SwiftLint rules in `CONTRIBUTING.md`.
- Treat `swift-format` as canonical for comma placement and collection-literal alignment; do not enable SwiftLint's conflicting `trailing_comma` or `collection_alignment` rules.
- Use decimal numeric values in committed controller JSON.
- Treat `Resources/Schemas/` as the only authority for repository JSON contracts. Do not invent per-device, per-command, per-date, temporary, or task-specific schemas.
- Machine-readable controller records and reports must declare the one current schema from `Resources/Schemas/`. Update that schema and every producer/consumer atomically; never create staged `v1`/`v2` files, dated schemas, migration shims, manifests, snapshots, or bespoke evidence JSON under `docs/`.
- Controller records contain operational facts only. Never add provenance, verification, confidence, evidence-level, source-note, or review-state fields or flags such as `experimental` and `needsHardwareTest`; source revisions belong in `ControllerSources.lock.json`, while accepted observations belong in testing documents, issues, and Git history.
- Support reports contain observed state only. Never add machine-authored verification claims, evidence levels, test plans, or migration payloads.
- Keep `OpenJoystickDriverKit` independent of SwifterKit. Only `OpenJoystickDriverUSB` and `DriverKitGenerator` may import it; compose those targets at the app entry point.
- Do not hand-author or retain a manual DriverKit native build path or post-generation patch path. Generated output remains under `.build/driverkit/`.
- Preserve the host entitlement allowlist for `com.openjoystickdriver.XboxUSBDevice`; never substitute an allow-any DriverKit user-client entitlement.
- Avoid broad signing, DriverKit, or application-service lifecycle changes without targeted validation.
- Do not assert human-readable message text in tests; check return codes, routes, and structural properties instead.
- Do not write tests that read source files with `String(contentsOf:)` and assert on literal substrings via `.contains(...)`. These break on any reformat and guard formatting, not function. Test behavior: call the public API, feed it inputs, and assert on outputs. Use `@testable import` to access internal types when needed. Verify invariants through function calls (e.g. `CLIGrammar(arguments:).invocation`, `ParserRegistry().hidProfileIdentifiers()`, `ApplicationServiceRuntimeHealthAnalyzer.summarize(...)`), not source-text matching.
- Confirm destructive actions, external writes, and publication.

Direct user instructions override this file. A closer subtree `AGENTS.md` takes precedence for files in that subtree. `CLAUDE.md`, `GEMINI.md`, and `.github/copilot-instructions.md` are symlinks to this file.
