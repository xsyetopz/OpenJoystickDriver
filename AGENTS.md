# Agent brief

OpenJoystickDriver is a macOS userspace gamepad driver. Ground claims in source, tests, schemas, or recorded hardware evidence.

Before editing, read `CONTRIBUTING.md`, `docs/Home.md`, `LOCALIZATION.md`, and `Resources/Schemas/AGENTS.md`.

## Boundaries

- Do not edit generated records in `Sources/OpenJoystickDriverKit/Resources/Controllers/` or generated DriverKit files in `.build/driverkit/generated/`.
- Regenerate the catalog with `./Scripts/ojd catalog regenerate --write` only after intentionally changing its authored inputs.
- Generate DriverKit files with `./Scripts/ojd driverkit generate`.
- Do not add SVGs or secrets.
- Confirm destructive writes and publication before running them.

## Checks

Run applicable commands from the repository root:

```bash
./Scripts/ojd catalog regenerate --check
./Scripts/ojd check profiles
./Scripts/ojd check schemas
ruff format --check Scripts Tests/RepositoryScripts
ruff check Scripts Tests/RepositoryScripts
pyright
python3 -m unittest discover -s Tests/RepositoryScripts
find Scripts -type f \( -name '*.sh' -o -name ojd \) -print0 | xargs -0 shellcheck \
  --external-sources --source-path=SCRIPTDIR
git ls-files -z -co --exclude-standard '*.md' | xargs -0 markdownlint-cli2
swift-format lint --recursive --strict Package.swift Sources Tests
swiftlint lint --no-cache --strict
python3 Scripts/Quality/check_swift_file_length.py
./Scripts/ojd check driverkit
swift test
```

For parser or protocol changes, also run `./Scripts/ojd test parsers-macos14`. Use `./Scripts/ojd repair swiftpm-module-cache` only to repair a SwiftPM module-cache mismatch.
