# Gates

## Contents

- [Gate sync](#gate-sync)
- [Index-snapshot hook](#index-snapshot-hook)
- [Swift file gate](#swift-file-gate)

## Gate Sync

**Definition.** A repository check appears in up to five places:

- the `AGENTS.md` check list;
- the `justfile` recipes `lint`, `check-hook`, `check-fast`, and `check`;
- the `.github/workflows/ci.yml` steps;
- `Scripts/README.md`;
- `CLAUDE.md`, if the check is one of its listed commands.

**Use when.** Adding, removing, or changing the arguments of a check.

**Do not use when.** Never add an expensive hardware or signing step to CI or `check-fast`. Such a step belongs in a `diagnose` or `signing` route that is run by hand.

**Example.** The Swift file checker runs in `check-hook`, `check-fast`, and `check-swift-file-length`, in the CI "Check Swift formatting and lint" step, and in the `AGENTS.md` list.

**Cost removed.** Before beta.5, the length checker ran only in the commit hook, so a commit made with `--no-verify` reached the branch unchecked.

**Verify.** `rg -n '<check command>' AGENTS.md justfile .github/workflows Scripts/README.md` shows every intended place.

## Index-Snapshot Hook

**Definition.** `lefthook.yml` `pre-commit` runs `Scripts/Quality/check-index-snapshot.sh`. The script commits the index to a temporary commit, checks it out in a temporary worktree, and runs `just check-hook` there. As a result, the hook checks exactly what is being committed, and ignores unstaged edits. `pre-push` runs `Scripts/Quality/check-pushed-tips.sh` on the pushed refs.

**Use when.** Changing what runs at commit or push time.

**Do not use when.** Never add slow gates such as `swift test` to `check-hook`. Hooks must stay fast, or people bypass them.

**Verify.** `./Scripts/ojd hooks validate` passes. `Tests/RepositoryScripts/test_git_hooks.py` covers the pre-push check. Add a case there for any hook behavior you change.

## Swift File Gate

**Definition.** `Scripts/Quality/check_swift_file_length.py` counts code lines per tracked Swift file, excluding blank and comment-only lines. The limit is 500 for files under `Sources` and 1000 for files under `Tests`. The script also rejects any extension-file concern (the text after the last `+`) that is exactly `Behavior` or `Scenarios`, or that ends in a digit.

**Use when.** Changing a limit or the naming rule.

**Do not use when.** Never raise a limit to fit one file. Split the file by concern (`ojd-swift-change`). A limit change needs the user's approval and an update to `docs/development/source-topology.md`.

**Cost removed.** A 350-line limit with no naming rule produced 150 `+BehaviorN` files and forced `private` state to become internal.

**Verify.** `Tests/RepositoryScripts/test_swift_file_length.py` covers the limits and the rejected names, and `python3 Scripts/Quality/check_swift_file_length.py` passes on the tree.
