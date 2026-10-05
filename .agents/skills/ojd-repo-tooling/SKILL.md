---
name: ojd-repo-tooling
description: >-
  Changes OpenJoystickDriver repository tooling: the ./Scripts/ojd dispatcher
  and its Python and shell targets under Scripts/, justfile recipes, lefthook
  Git hooks, GitHub Actions workflows, quality gates such as the Swift
  file-length and naming checker, and their unittest coverage in
  Tests/RepositoryScripts. Use when adding or changing an ojd route, a just
  recipe, a hook, a CI step, or a repository check. Not for building, signing,
  or releasing (ojd-build-sign-release), catalog generator inputs
  (ojd-controller-catalog), or Swift product code (ojd-swift-change).
---

# OpenJoystickDriver Repository Tooling

Change one tool route or gate, cover it with a Python unit test, and keep the dispatcher, `justfile`, hooks, CI, and `AGENTS.md` telling the same story.

## Workflow

1. Read `Scripts/README.md`, `AGENTS.md` (the check list), the `justfile`, `lefthook.yml`, and `.github/workflows/ci.yml`, plus the target script and its test in `Tests/RepositoryScripts/`.
1. Pick the layer with the [layer card](references/layers.md#which-layer-owns-it).
1. Write the unittest first and watch it fail ([script tests](references/layers.md#script-tests)).
1. Make the change. For a new or changed route, apply every edit in the [route change card](references/layers.md#adding-an-ojd-route).
1. When a gate changes, update every place that runs it in the same change ([gate sync](references/gates.md#gate-sync)).
1. Run `uv run --no-project --with jsonschema python -m unittest discover -s Tests/RepositoryScripts` and `just lint`. For hook changes, also run `./Scripts/ojd hooks validate`.

## Route the Problem To a Card

| Situation | Card |
| --- | --- |
| Where the new behavior goes | [Which layer owns it](references/layers.md#which-layer-owns-it) |
| New `./Scripts/ojd` command or flag | [Adding an ojd route](references/layers.md#adding-an-ojd-route) |
| Testing a script | [Script tests](references/layers.md#script-tests) |
| A check runs locally but not in CI, or the reverse | [Gate sync](references/gates.md#gate-sync) |
| Commit hook fails, or passes on unstaged files | [Index-snapshot hook](references/gates.md#index-snapshot-hook) |
| Changing the Swift length or naming gate | [Swift file gate](references/gates.md#swift-file-gate) |

## Rules

- `./Scripts/ojd` is the only repository entry point. `just` recipes call standard tools or `./Scripts/ojd`, and do not reimplement a route.
- Script tests are Python `unittest` tests in `Tests/RepositoryScripts/`. There is no `Tests/Scripts`, and no Swift test runs shell or Python.
- Tests assert on exit codes, parsed data, and forwarded arguments. Help text and prose change freely, so a test that asserts on them breaks for no reason.
- Homebrew `python3` lacks `jsonschema`, so tests that import it fail with `ModuleNotFoundError`. Run the suite with `uv run --no-project --with jsonschema`, or through `.build/schema-validator`.
- Hooks are managed by lefthook. Edit `lefthook.yml` and the scripts it runs, never `.git/hooks/`. `ojd hooks install` rewrites that directory.
- Scripts contain no secrets, Team IDs, or signing identities. Those values come from the environment (`docs/development/environment.md`).

## References

- [Layers](references/layers.md): which layer owns it, adding an ojd route, script tests.
- [Gates](references/gates.md): gate sync, index-snapshot hook, Swift file gate.

## Completion Evidence

The report names the route or gate changed, and the unittest that failed before the change and passes after it. It gives the results of `just lint` and the unittest suite, and lists every place the gate appears. It says whether CI was run, or only the local equivalent.
