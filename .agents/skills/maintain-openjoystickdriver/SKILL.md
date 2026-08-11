---
name: maintain-openjoystickdriver
description: >
  Use when implementing or repairing OpenJoystickDriver Swift 6/macOS product behavior, shared Kit/app/relay boundaries, controller behavior that consumes canonical catalog data, or DriverKit generator inputs; not for controller catalog authoring/regeneration, physical diagnosis, topology-only moves, product-test validation, UI design, generated .build output, or script tests.
---

# Maintain OpenJoystickDriver

Use this repository-local action skill to implement one coherent behavior change
inside an existing OpenJoystickDriver owner. It protects package/generated
boundaries and shared product contracts; specialized skills own topology,
product-test evidence, and Apple UI design. `AGENTS.md` remains authoritative.

## When to use

- Adding or repairing Swift behavior in an existing `Sources/` capability and
  its public/internal product seam.
- Changing controller discovery, HID, protocol parsers, output backends,
  remapping, runtime/RPC, diagnostics, status, or product behavior that
  consumes existing controller catalog inputs without changing ownership
  topology.
- Changing shared Kit/app/relay contracts, permissions, service boundaries, or
  `OpenJoystickDriverRelay` and `DriverKitGenerator` authored inputs.
- Changing DriverKit generator behavior or other generated-project inputs while
  preserving generated ownership and package dependency direction.

## When NOT to use

- An unrelated Swift, Apple-platform, or DriverKit repository.
- A request whose only owner is global agent tooling, Codex configuration, or
  the user’s machine rather than this repository’s `.agents/` tree.
- A topology move, directory split, source/test ownership review, or architecture
  audit; use `$organize-openjoystickdriver`.
- A test-only task, test gate, parser harness, or validation report; use
  `$test-openjoystickdriver`.
- Authoring, importing, or regenerating controller catalog records, lock entries,
  or overrides; use `$add-controller-openjoystickdriver`.
- Capturing or diagnosing physical controller discovery, packets, reconnect, or
  rumble/LED behavior; use `$debug-controller-openjoystickdriver`.
- A menu-bar/settings/accessibility/user-flow task; use
  `$design-openjoystickdriver` and `$apple-design-hig`.
- Direct edits to `.build/driverkit/generated/`, other build output, or a
  generated controller catalog record. Change the canonical generator input and
  regenerate instead.
- Generic Apple HIG advice without an implementation; use `$apple-design-hig`.

## Non-negotiables

- Read `AGENTS.md`, `Package.swift`, and the relevant canonical documentation
  before editing. Direct user instructions override repository guidance.
- Preserve the existing capability owner and package target. If ownership must
  change, stop and route to `$organize-openjoystickdriver` rather than adding a
  second path or compatibility shim.
- Keep concerns at their boundary: reusable controller/protocol behavior in
  `OpenJoystickDriverKit`; composition, AppKit/SwiftUI, CLI, runtime adapters,
  and CoreGraphics policy in `OpenJoystickDriver`; SwifterKit only in the relay
  and generator boundaries.
- Preserve Swift 6.2 strict concurrency, SwiftLint, entitlements, resources,
  RPC contracts, and the generated DriverKit boundary. Never hand-edit
  `.build/driverkit/generated/`.
- Treat controller records as generated runtime data. Route catalog authoring to
  `$add-controller-openjoystickdriver`; update locked sources or overrides and
  use the catalog generator there.
- Do not broaden signing, DriverKit, permission, or application-service changes
  without focused validation and an explicit risk note.

## Quick start

1. **Establish the baseline.** Check `git status --short --branch`; read
   `AGENTS.md`, `Package.swift`, and the nearest existing source owner.
2. **Name the behavior contract.** Identify inputs, outputs, state transitions,
   failure ownership, package boundary, and generated/canonical input. Do not
   invent a new directory in this skill.
3. **Read the boundary reference.** Load `references/boundaries.md`; route
   topology, tests, and UI to their specialized skills.
4. **Implement the smallest coherent behavior change.** Keep shared protocol
   behavior in Kit, app composition in the app, and SwifterKit in relay/generator
   adapters. Update canonical generators rather than generated output.
5. **Hand off evidence work.** Route matching product tests and gates to
   `$test-openjoystickdriver`; do not add script/prose/source-text fixtures here.
6. **Inspect the candidate.** Review target membership, imports, resources,
   entitlements, generated artifacts, `git diff --check`, and remaining risk.

## Reference map

| Need | Load |
|---|---|
| Existing package, import, and generated boundaries | `references/boundaries.md` |
| Controller catalog authoring and deterministic record generation | `$add-controller-openjoystickdriver` |
| Physical controller discovery, packet, and hardware evidence | `$debug-controller-openjoystickdriver` |
| Source/test topology or ownership change | `$organize-openjoystickdriver` |
| Product-only tests and executable gates | `$test-openjoystickdriver` |
| macOS UI, accessibility, and visual proof | `$design-openjoystickdriver`, `$apple-design-hig`, `$skizzles:design-proof-gate` |
| Full repository authority and source of truth | `AGENTS.md`, `Package.swift`, `CONTRIBUTING.md` |
| Removal of obsolete paths or wrappers | `$skizzles:no-legacy-cleanup` |

## Completion criteria

A change is complete only when all applicable conditions hold:

- The requested product outcome is implemented at its existing canonical owner,
  with no compatibility shim or competing path.
- Package target boundaries, imports, resources, entitlements, generated inputs,
  and dependency direction remain correct.
- Matching product evidence is routed through `$test-openjoystickdriver`; UI
  evidence is routed through `$design-openjoystickdriver`.
- The final report names changed paths, boundary/generator inputs, validation
  owners, and remaining risks. Do not claim acceptance from an unrun gate.

## Validation instructions

Run the installed global Agent Skills validator first:

```sh
python3 "$HOME/.agents/scripts/validate_skill.py" .agents/skills/maintain-openjoystickdriver
```

Then route product evidence to `$test-openjoystickdriver`, topology audits to
`$organize-openjoystickdriver` and `$architecture-enforce`, and UI proof to
`$design-openjoystickdriver` and `$apple-design-hig`.

## Related skills

- `$organize-openjoystickdriver` — source/test topology and ownership changes.
- `$add-controller-openjoystickdriver` — controller catalog authoring and imports.
- `$debug-controller-openjoystickdriver` — physical controller diagnosis and evidence.
- `$test-openjoystickdriver` — product-only behavior tests and repository gates.
- `$design-openjoystickdriver` — Apple menu-bar, settings, and accessibility work.
- `$apple-design-hig` — Apple platform interaction and accessibility review.
- `$architecture-design` — evidence-backed boundary decisions when ownership changes.
- `$architecture-enforce` — fail-closed topology enforcement via the organize skill.
- `$skizzles:no-legacy-cleanup` — remove obsolete paths and compatibility behavior.
- `$skizzles:completion-contract` — define acceptance evidence for substantial work.
