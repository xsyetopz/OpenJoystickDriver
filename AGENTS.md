# AGENTS.md

macOS userspace gamepad driver. Ground claims in source, tests, schemas, or recorded hardware evidence.

Read `CONTRIBUTING.md`, `docs/README.md`, `LOCALIZATION.md`, `docs/AGENTS.md`, `Resources/Schemas/AGENTS.md`.

Do not edit generated records under `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`. Catalog write: `./scripts/ojd catalog regenerate --write`. DriverKit: `./scripts/ojd driverkit generate`. No SVGs or secrets. Confirm destructive writes and publication.

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

Parser/protocol: `./scripts/ojd test parsers-macos14`. Cache: `./scripts/ojd repair swiftpm-module-cache`.
