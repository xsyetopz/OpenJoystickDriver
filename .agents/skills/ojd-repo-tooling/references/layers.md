# Layers

## Contents

- [Which layer owns it](#which-layer-owns-it)
- [Adding an ojd route](#adding-an-ojd-route)
- [Script tests](#script-tests)

## Which Layer Owns It

**Definition.**

| Layer | Path | Owns |
| --- | --- | --- |
| Entry point | `Scripts/ojd` → `Scripts/Command/__main__.py` | Starting Python |
| Dispatcher | `Scripts/Command/dispatcher.py` | Parsing arguments, `usage()` text, and routing with `match` to a target |
| Execution | `Scripts/Command/execution.py` | Process execution helpers |
| Platform | `Scripts/Platform/` | The capability model, the route requirements, and `environment.sh` (Xcode and SDK resolution) |
| Feature groups | `Scripts/{Build,Catalog,Diagnostics,Documentation,Quality,Release,Signing}/` | One narrow implementation each |
| Orchestration | `justfile` | Recipes that chain standard tools and `./Scripts/ojd` routes |
| Hooks | `lefthook.yml` | `pre-commit` and `pre-push` commands |
| CI | `.github/workflows/ci.yml`, `release.yml` | The hosted gate and release jobs |

**Use when.** Deciding where a new behavior goes.

**Do not use when.** The behavior belongs to one feature group only. Keep it in that group, and have the dispatcher forward to it.

**Verify.** `./Scripts/ojd --help` lists the route, and `just --list` shows the recipe, if one was added.

## Adding an ojd Route

**Definition.** A route is a `case` in `dispatch()` that validates the arity of its arguments with `require(...)`, then forwards them with `exec_target(<relative path>, [args], python=?, env=?)`. An unknown subcommand calls `die("Unknown: ... (expected: ...)")`.

**Use when.** Adding a command or subcommand, or changing a flag.

**Do not use when.** Never add the route for a one-off local task. Run the script directly instead.

**Example.** Edits for a new `check foo` route:

1. Add this under `case "check":`:

   ```python
   if sub == "foo":
       require("check foo", tail, count=0)
       exec_target("Quality/foo.py", [], python=True)
   ```

1. Extend the `die(... expected: ...)` list and `usage()`.
1. Add a forwarding case to `Tests/RepositoryScripts/test_dispatcher.py` that asserts the target path and arguments.
1. If the route is a gate, apply the [gate sync](gates.md#gate-sync) edits.
1. Mention the route in `Scripts/README.md`, or in the doc that owns the workflow.

**Cost removed.** An undocumented route, or one missing from `usage()`, gets reinvented as a second script with the same job.

**Verify.** `./Scripts/ojd check foo` runs the target, and an unknown subcommand exits non-zero. The dispatcher test passes.

## Script Tests

**Definition.** `unittest.TestCase` classes live in `Tests/RepositoryScripts/test_<script>.py` and import the scripts as the `Scripts.<Group>.<module>` package. Fixtures go in `Tests/RepositoryScripts/fixtures/`. Tests that write files use a `tempfile.TemporaryDirectory` copy, never the working tree.

**Use when.** Any change under `Scripts/`.

**Do not use when.** The only behavior to assert is shellcheck-clean syntax. The `just lint` shellcheck line covers that.

**Example.** `test_bump_version.py` builds a temporary repository root. It asserts that a bump sets the app version with no CHANGELOG heading, and that a version with build metadata is refused without touching `Info.plist`.

**Verify.**

```bash
uv run --no-project --with jsonschema python -m unittest Tests.RepositoryScripts.test_<script>
```

The command fails before the change and passes after it.
