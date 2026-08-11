---
name: organize-openjoystickdriver
description: >
  Use when organizing, moving, splitting, renaming, or reviewing OpenJoystickDriver Sources and matching Tests, capability ownership, SwiftPM target paths, or architecture-enforce topology; not for a behavior-only fix, generated .build output, or script tests.
---

# Organize OpenJoystickDriver

Use this action skill for path-level architecture work in OpenJoystickDriver.
It makes capability ownership and matching product tests obvious without
shattering cohesive code, changing package boundaries unnecessarily, or
retaining compatibility paths. `$maintain-openjoystickdriver` supplies the
shared repository contract; this skill owns topology decisions and migrations.

## When to use

- Moving or renaming three or more sibling Swift source/test files.
- Creating, removing, or reviewing a capability directory under `Sources/` or
  its matching `Tests/` target.
- Auditing source/test mirroring, package target membership, dependency
  direction, stale old paths, or architecture-enforce findings.
- Deciding whether a capability belongs in Kit, the app composition root, the
  relay adapter, or the DriverKit generator.
- Removing an obsolete topology, alias, forwarding file, tombstone, or other
  compatibility path.

## When NOT to use

- A behavior-only implementation whose owner and paths stay unchanged; use
  `$maintain-openjoystickdriver`.
- A test-only or evidence-only task; use `$test-openjoystickdriver`.
- Editing `.build/driverkit/generated/`, generated controller records, schemas,
  entitlements, or other generated output.
- Writing or testing shell/Python scripts, documentation prose, or source text.
- A UI interaction or accessibility review without a topology decision; use
  `$design-openjoystickdriver` and `$apple-design-hig`.

## Non-negotiables

- Read `AGENTS.md`, `Package.swift`, and `docs/development/source-topology.md`
  before changing paths. The canonical architecture document and direct user
  instructions win over this skill.
- Give each capability one obvious source owner and one mirrored product-test
  owner. Use the documented nearest-owner exceptions for Kit `HID` and app
  `Controllers`, `MenuBar`, and `Diagnostics`; never invent `Helpers`,
  `Managers`, `Types`, `Validation`, or `Scripts` buckets.
- Keep existing SwiftPM targets and dependency direction unless an independent
  lifecycle, dependency, public contract, or failure domain justifies a package.
- Move source and behavior tests together. Preserve unique Swift basenames and
  target resources; update canonical docs and path literals in the same slice.
- Do not keep old paths, aliases, forwarding shims, tombstones, exclusions,
  threshold changes, baselines, or suppressions to make an audit pass.
- Do not move controller records, schemas, entitlements, or generated DriverKit
  output as part of source organization.

## Quick start

1. **Freeze the baseline.** Check `git status --short --branch`; read the
   package graph, canonical topology decision, callers, imports, resources,
   tests, and generated boundaries. Preserve unrelated work.
2. **Map ownership before editing.** For every moved or created path record its
   behavior owner, target, visibility, lifecycle, dependencies, matching test
   owner, and reason a shallower cohesive location is insufficient.
3. **Compare candidates.** Consider do-less, capability directories in existing
   targets, and a new package only when its boundary is independently justified.
   Choose the smallest reversible structure with one obvious way to find it.
4. **Migrate intact units.** Move source and product tests together; consolidate
   only declarations with one lifecycle. Delete the old path rather than adding
   compatibility forwarding. Keep generated sources at their canonical input.
5. **Verify the graph.** Check `swift package describe --type json`, imports,
   resources, entitlements, stale paths, duplicate basenames, and target
   membership. Update `docs/development/source-topology.md` when the decision
   changes.
6. **Run fail-closed proof.** Run the repository dispatcher’s
   `check swift-structure` route, `$architecture-enforce`, focused product tests,
   and the applicable gates in
   `$test-openjoystickdriver`. Every architecture warning or error blocks
   completion; do not hide it with an exclusion.

## Reference map

| Need | Load |
|---|---|
| Current capability map and nearest test owners | `references/topology.md` |
| Canonical decision, forces, candidates, and rollback | `docs/development/source-topology.md` |
| Shared package and generated-boundary contract | `$maintain-openjoystickdriver` |
| Architecture decision and alternatives | `$architecture-design` |
| Executable audit and suppression rules | `$architecture-enforce` |
| Product-only focused and broad gates | `$test-openjoystickdriver` |
| Obsolete path removal | `$skizzles:no-legacy-cleanup` |

## Completion criteria

- Every changed path has one durable owner and a matching product-test owner or
  an explicit nearest-owner exception.
- Package targets, dependency direction, imports, resources, entitlements,
  generated inputs, and public contracts are unchanged unless explicitly part
  of the decision.
- No old path, alias, forwarding file, generated artifact, test-only script
  bucket, or audit suppression remains.
- `swift package describe --type json`, structural checks, architecture audit,
  focused product tests, and applicable repository gates pass; blockers name
  their exact command and evidence.
- The handoff records the ownership map, rejected candidates, migration and
  rollback boundary, validation output, and evolution trigger.

## Validation instructions

Run the global skill validator, then load `references/validation.md` and run its
canonical repository checks:

```sh
python3 "$HOME/.agents/scripts/validate_skill.py" .agents/skills/organize-openjoystickdriver
```

For a topology change, run the full `$architecture-enforce` audit with no
exclusions, thresholds, baselines, or suppressions, then run the focused and
broader product-only gates from `$test-openjoystickdriver`. `git diff --check`
and stale-path inspection are required before acceptance.

## Related skills

- `$maintain-openjoystickdriver` — shared implementation and boundary contract.
- `$test-openjoystickdriver` — actual Sources behavior tests and gates.
- `$design-openjoystickdriver` — UI ownership and Apple platform proof.
- `$architecture-design` — decision records and quality-attribute tradeoffs.
- `$architecture-enforce` — fail-closed topology enforcement.
- `$skizzles:no-legacy-cleanup` — clean removal of obsolete paths.
