# Repository Scripts

`./Scripts/ojd` is the supported entrypoint for repository-specific behavior. Just orchestrates standard formatters, linters, type checkers, tests, and those repository routes.

The dispatcher owns command parsing; `Scripts/Command/` owns process execution, while `Scripts/Platform/` owns capability models, resolution, and route requirements. The remaining feature groups own narrow implementations.

Use `./Scripts/ojd help` for supported routes. Run the standard tools directly or use the equivalent `just lint`, `just check-fast`, and `just check` recipes:

```bash
./Scripts/ojd check profiles
./Scripts/ojd check schemas
./Scripts/ojd check tools
./Scripts/ojd test parsers-macos14
ruff format --check Scripts Tests/RepositoryScripts
ruff check Scripts Tests/RepositoryScripts
pyright
find Scripts -type f \( -name '*.sh' -o -name ojd \) -print0 | xargs -0 shellcheck \
  --external-sources --source-path=SCRIPTDIR
git ls-files -z -co --exclude-standard '*.md' | xargs -0 markdownlint-cli2
swift-format lint --recursive --strict Package.swift Sources Tests
swiftlint lint --no-cache --strict
python3 -m unittest discover -s Tests/RepositoryScripts
swift test --no-parallel
```

`catalog regenerate --write` writes generated controller records. DriverKit project generation writes DriverKit output. All other commands retain their documented route-specific effects and requirements.
