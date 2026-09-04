---
name: test-openjoystickdriver
description: >
  Use when proving OpenJoystickDriver product behavior through Swift Sources,
  matching Tests, parser regressions, and repository validation; not for
  controller catalog authoring, live physical-controller diagnosis, script
  fixtures, prose/source inspection, UI design, topology ownership, or unrelated
  repositories.
---

# Test OpenJoystickDriver

Use this repository-local skill to make test evidence executable, behavior-led,
and scoped to OpenJoystickDriver's real Swift product. `AGENTS.md` and the
nearest subtree instructions remain authoritative; this skill turns their
product-only test rule and validation sequence into a repeatable contract.

## When to use

- Add or update behavior tests under the matching `Tests/` owner for Swift
  product code in `Sources/`.
- Prove HID, device, protocol/parser, catalog, output, remapping,
  application-service, runtime, CLI, relay, generator, or status behavior.
- Investigate a regression with a focused Swift test, the parser harness, or a
  supported `ojd` repository diagnostic/check.
- Validate a product change through the catalog/profile/script/structure/lint/
  DriverKit and full SwiftPM gates.
- Review whether a proposed test observes a product contract rather than
  guarding source layout, formatting, documentation, or script prose.

## When NOT to use

- Writing unit tests for shell/Python helpers, documentation, prose, or source
  text. Do not create `Tests/Scripts`, script fixtures, or tests that read
  source files and assert literal substrings.
- Designing or relocating capability ownership. Route shared repository
  boundaries to `$maintain-openjoystickdriver` and topology work to
  `$organize-openjoystickdriver`.
- Authoring, importing, or regenerating controller catalog records, lock entries,
  or overrides; route to `$add-controller-openjoystickdriver`.
- Capturing or diagnosing live controller discovery, packets, reconnect, or
  rumble/LED behavior; route to `$debug-controller-openjoystickdriver`.
- Designing menu-bar/settings UI or visual/accessibility proof. Route UI work
  to `$design-openjoystickdriver` and use `$apple-design-hig` for Apple HIG
  review.
- A generic architecture decision or removal of obsolete paths; use
  `$architecture-design`, `$architecture-enforce`, or
  `$skizzles:no-legacy-cleanup` as appropriate.
- Generated `.build/driverkit/generated/` output, unrelated repositories, or
  global agent tooling.

## Non-negotiables

- `Tests/` proves actual Swift code under `Sources/` (and the supported relay or
  generator product targets), never repository scripts. Keep each test beside
  its canonical capability owner; use the documented nearest-owner exception
  only when the topology says one exists.
- Call public APIs or use `@testable import` to exercise behavior. Assert return
  codes, routes, state transitions, events, typed payload structure,
  machine-readable identifiers, and invariants. Protocol or persisted
  machine-readable fields are valid assertions when they are observable product
  contracts.
- Never read repository source, scripts, documentation, or generated output as
  a test fixture, regardless of the file-read API; never use regexes over Swift
  text or `.contains(...)` to prove implementation structure. Never assert
  human-readable message, help, or script prose; prefer routes, status,
  identifiers, typed state, return codes, or payload structure.
- Repository scripts are support tooling. Validate them with their supported
  `ojd` repository checks; do not invoke script implementation from Swift tests.
- Keep Swift 6.3.3 strict concurrency, package boundaries, generated DriverKit
  ownership, resources, entitlements, and hardware limitations explicit.

## Quick start

1. **Read the baseline.** From the repository root, inspect `AGENTS.md`,
   `Package.swift`, `CONTRIBUTING.md`, `docs/development/source-topology.md`,
   and the nearest source/test owner. Check `git status --short --branch` and
   preserve unrelated changes.
2. **Name the observable contract.** Identify the target, capability owner,
   input, expected state/route/event/payload, failure case, and whether hardware
   or macOS access is required. Avoid tests whose only oracle is source text or
   prose.
3. **Run the smallest proof first.** Filter the affected Swift test target.
   For parser/protocol changes also run the repository dispatcher’s
   `test parsers-macos14` route documented in `references/validation.md`; this
   is the supported isolated parser harness, not a `Tests/Scripts` fixture.
4. **Run repository gates.** Use the sequence in
   [`references/validation.md`](references/validation.md): catalog, profiles,
   scripts, Swift structure, lint, DriverKit, then `swift test`.
5. **Audit and report.** If tests fail, preserve the exact command and output,
   repair only attributable failures, and report environmental, signing,
   hardware, or module-cache blockers honestly. Review `git diff --check` and
   target membership before handoff.

## Reference map

| Need | Load |
|---|---|
| Focused tests, parser harness, gate order, and recovery | [`references/validation.md`](references/validation.md) |
| Controller catalog authoring and deterministic record generation | `$add-controller-openjoystickdriver` |
| Physical controller discovery, packet, and hardware evidence | `$debug-controller-openjoystickdriver` |
| Canonical source/test ownership and shared repository boundaries | `$maintain-openjoystickdriver` |
| Topology moves, splits, merges, or architecture audit | `$organize-openjoystickdriver`, `$architecture-design`, `$architecture-enforce` |
| Menu-bar/settings UI, interaction, accessibility, and visual proof | `$design-openjoystickdriver`, `$apple-design-hig`, `$skizzles:design-proof-gate` |
| Removing obsolete test paths, wrappers, or fixtures | `$skizzles:no-legacy-cleanup` |
| Repository authority and source of truth | `AGENTS.md`, `CONTRIBUTING.md`, `docs/development/source-topology.md` |

## Completion criteria

A testing task is complete only when all applicable conditions hold:

- Tests exercise actual Swift product behavior at the canonical source owner,
  with no `Tests/Scripts`, source/prose fixture, generated-output, or formatting
  assertion.
- Machine-readable product identifiers or protocol/persistence payload fields
  are asserted only as observable values with a stable contract; assertions do
  not target human-readable messages or help prose. Prefer typed state, routes,
  status, return values, events, and structural invariants.
- The focused test or parser harness ran first, followed by applicable catalog,
  profile, script, Swift-structure, lint, DriverKit, and `swift test` gates.
- Topology changes have an architecture audit through `$architecture-enforce`
  with every warning/error resolved or named; UI changes have the routed design
  and Apple HIG evidence.
- Failures and skipped hardware/macOS/signing checks are reported with exact
  commands, observed results, and remaining risk. Never call an unrun gate
  passing.
- This skill itself passes the global validator and `git diff --check`; no local
  validator script, pycache, product-source, or product-test file was added.

## Validation instructions

Validate this skill from the repository root with the installed global
validator (never add a repo-local validator):

```sh
python3 "$HOME/.agents/scripts/validate_skill.py" .agents/skills/test-openjoystickdriver
git diff --check -- .agents/skills/test-openjoystickdriver
```

For product changes, follow the focused-to-broad command order in
[`references/validation.md`](references/validation.md). Use the documented
`ojd repair swiftpm-module-cache` recovery only for that exact
SwiftPM mismatch, then rerun `swift test`. Hardware, DriverKit signing,
notarization, and permission behavior require their focused diagnostics; record
what was unavailable instead of substituting source-text assertions.

## Related skills

- `$maintain-openjoystickdriver` — shared product boundaries and implementation
  ownership.
- `$add-controller-openjoystickdriver` — controller catalog authoring and imports.
- `$debug-controller-openjoystickdriver` — physical controller diagnosis and evidence.
- `$organize-openjoystickdriver` — source/test topology ownership and migration.
- `$design-openjoystickdriver` — product UI implementation and proof.
- `$apple-design-hig` — Apple interaction, accessibility, and platform review.
- `$architecture-design` / `$architecture-enforce` — architecture decisions and
  fail-closed topology audits.
- `$skizzles:no-legacy-cleanup` — remove obsolete paths and compatibility tests.
- `$skizzles:completion-contract` — define acceptance evidence for substantial
  work.
