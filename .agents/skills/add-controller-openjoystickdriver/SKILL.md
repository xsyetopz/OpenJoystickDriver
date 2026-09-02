---
name: add-controller-openjoystickdriver
description: >
  Use when adding or importing OpenJoystickDriver controller support: controller catalog records, raw-USB JSON profiles, ControllerSources.lock.json, ControllerOverrides, Linux xpad translation, parser mappings, or catalog regeneration; not for hardware diagnosis, generic tests, UI, topology, or hand-editing generated output.
---

# Add Controller Support

Use this action skill when a new VID/PID or factual controller deviation must
enter OpenJoystickDriver. It owns canonical catalog inputs, schema shape,
deterministic regeneration, and review evidence. `$debug-controller-openjoystickdriver`
owns physical packet and hardware diagnosis; `$test-openjoystickdriver` owns
product-test evidence.

## When to use

- Importing a controller identity from the pinned Linux `xpad.c` source or an
  exact review-only revision.
- Adding a complete local controller record under `Resources/ControllerOverrides`
  or patching selected sections with local-hardware/tester-packets evidence.
- Updating catalog translation or controller transport facts while preserving
  shared parser behavior.
- Regenerating and reviewing `Sources/OpenJoystickDriverKit/Resources/Controllers`
  after an intentional lockfile or override change.
- Checking VID/PID collisions, decimal JSON values, schema validity, and
  deterministic catalog output.

## When NOT to use

- Capturing or interpreting physical packets, USB descriptors, reconnect,
  rumble, LEDs, or macOS permissions; use
  `$debug-controller-openjoystickdriver`.
- Changing parser/protocol/device behavior without a catalog-data decision; use
  `$maintain-openjoystickdriver` and `$test-openjoystickdriver`.
- Moving Sources/Tests or changing capability ownership; use
  `$organize-openjoystickdriver`.
- Designing controller settings UI or accessibility; use
  `$design-openjoystickdriver` and `$apple-design-hig`.
- Hand-editing generated controller records, generated DriverKit output, or
  writing tests for catalog/scripts prose.

## Non-negotiables

- Treat `ControllerSources.lock.json`, `Resources/ControllerOverrides/`, and
  `Resources/Schemas/` as authored inputs. Treat
  `Sources/OpenJoystickDriverKit/Resources/Controllers/` as generated runtime
  output owned by the catalog generator.
- Never hand-edit or retain a generated-record patch path. Change the lock,
  override, schema, or generator source, then regenerate and inspect the diff.
- An override `add` must not collide with an upstream identity. A `patch` must
  target an upstream record and change only intended top-level sections.
  Redundant or malformed overrides fail closed.
- Keep shared protocol behavior in Kit code. Controller data contains factual
  deviations, endpoints, startup packets, and mappings—not provenance, a second
  parser implementation, or a compatibility shim.
- Use decimal numeric values in committed JSON, stable lowercase VID/PID paths,
  and the canonical schema shape. Linux recognition or record validation is not
  macOS hardware verification; keep review status in testing documents and issues.
- Scripts are support tooling. Run the repository dispatcher’s catalog/profile
  checks; do not add `Tests/Scripts`, script fixtures, or prose assertions.

## Quick start

1. **Establish the baseline.** Read `AGENTS.md`, `CONTRIBUTING.md`,
   `docs/development/xpad-import.md`, `docs/testing/controller-record.md`, the
   relevant schema, lock entry, parser registry, and nearest product tests.
2. **Classify the evidence.** Decide whether the identity is pinned-source
   import, complete local add, or evidence-backed patch. Record the exact VID/PID,
   connection mode, protocol, and what is not yet known in the testing document.
3. **Edit one canonical input.** Update the lock/override/generator input only;
   preserve generated records and `.build` output. Use the smallest factual
   override instead of copying shared parser logic into data.
4. **Regenerate deterministically.** Run the catalog write route only after the
   input is intentional, then run read-only catalog/profile checks. Inspect
   generated paths, decimal values, and unrelated record churn.
5. **Prove the product seam.** Route parser/record behavior to
   `$test-openjoystickdriver`; route physical packet or hardware claims to
   `$debug-controller-openjoystickdriver`. Do not mark hardware support from a
   passing generator or parser test alone.
6. **Report the evidence boundary.** State source-backed, packet-backed, and
   hardware-verified claims separately, with exact commands and remaining gaps.

## Reference map

| Need | Load |
|---|---|
| Canonical inputs, generated output, and evidence flow | `references/controller-data.md` |
| Linux xpad translation and override rules | `docs/development/xpad-import.md` |
| Candidate record validation and physical probe procedure | `docs/testing/controller-record.md` |
| Support status and compatibility limits | `docs/user/compatibility.md`, `docs/development/experimental-controllers.md` |
| Product parser/record tests and gates | `$test-openjoystickdriver` |
| Physical controller diagnosis | `$debug-controller-openjoystickdriver` |
| Shared implementation/package boundaries | `$maintain-openjoystickdriver` |

## Completion criteria

- The change edits the correct canonical input and regenerates deterministic
  records; no generated record or build output was hand-edited.
- Schema, VID/PID collision, decimal-value, parser mapping, and
  catalog/profile checks pass with no unrelated generated churn.
- Product behavior evidence is routed through matching Tests, while physical
  claims have the separate diagnosis/hardware evidence required by the docs.
- User-facing support claims are truthful; unresolved
  hardware, permission, signing, or platform gaps are named explicitly.
- The final handoff lists input paths, generated outputs, commands/results,
  source/packet/hardware evidence class, and rollback steps.

## Validation instructions

Run the global skill validator and canonical catalog gates:

```sh
python3 "$HOME/.agents/scripts/validate_skill.py" .agents/skills/add-controller-openjoystickdriver
./scripts/ojd catalog regenerate --check
./scripts/ojd check profiles
./scripts/ojd check swift-structure
```

For an intentional input change, use the catalog write route documented in
`docs/development/xpad-import.md`, then repeat the read-only checks and review
generated diff. Run focused product
tests and parser/hardware evidence through `$test-openjoystickdriver` and
`$debug-controller-openjoystickdriver`; never substitute source-text or prose
assertions. Use `$organize-openjoystickdriver` if paths or ownership change.

## Related skills

- `$debug-controller-openjoystickdriver` — packet, descriptor, runtime, and hardware evidence.
- `$maintain-openjoystickdriver` — existing parser/domain/package behavior.
- `$test-openjoystickdriver` — product-only tests and repository gates.
- `$organize-openjoystickdriver` — source/test topology changes.
- `$design-openjoystickdriver` — controller settings UI and user-flow proof.
- `$skizzles:no-legacy-cleanup` — clean removal of obsolete record paths or wrappers.
