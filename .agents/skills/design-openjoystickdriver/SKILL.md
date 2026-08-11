---
name: design-openjoystickdriver
description: >
  Use when designing, reviewing, or changing OpenJoystickDriver’s macOS menu-bar app, settings window, SwiftUI/AppKit presentation, accessibility, permissions, lifecycle, loading/error states, or user flows; not for unrelated UI, protocol-only behavior, or generated output.
---

# Design OpenJoystickDriver

Use this action skill for Apple-coherent product UI and lifecycle work. It keeps
the menu-bar app, one reusable settings window, typed runtime gateway, semantic
controls, and accessibility states aligned with Apple HIG while leaving domain
behavior in Kit and product behavior tests in their matching owners.

## When to use

- Designing or changing menu-bar lifecycle, settings navigation, toolbar
  structure, profile editing, controller capture, status, or diagnostics flows.
- Reviewing AppKit/SwiftUI layout, semantic controls, focus order, VoiceOver,
  Full Keyboard Access, appearance, text sizing, reduced motion, or contrast.
- Changing permission, system-extension, unavailable, loading, empty, or error
  states shown to users.
- Proving stale-response, cancellation, window reuse, runtime gateway, or app
  lifecycle behavior at the real product boundary.

## When NOT to use

- A Kit protocol, parser, HID, output, or remapping change without a user-flow
  decision; use `$maintain-openjoystickdriver`.
- Moving or splitting source/test paths; use `$organize-openjoystickdriver`.
- Adding or reviewing product behavior tests and repository gates; use
  `$test-openjoystickdriver`.
- Generic Apple HIG questions without an OpenJoystickDriver surface; use
  `$apple-design-hig` directly.
- Editing `.build/driverkit/generated/`, generated records, scripts, or source
  prose fixtures.

## Non-negotiables

- Read `AGENTS.md`, `docs/development/source-topology.md`, and the relevant
  presentation source/test owner before editing. `$apple-design-hig` owns the
  platform guidance; this skill maps it to this product.
- Keep one persistent menu-bar application lifecycle and one reusable settings
  window. Do not create competing runtime instances, RPC servers, or windows
  for the same user flow.
- Keep a typed gateway into `ApplicationServiceRuntime` at the composition
  boundary. Presentation and CLI code do not recreate runtime state.
- Prefer semantic native AppKit/SwiftUI controls, native toolbar/navigation,
  keyboard behavior, and system appearance over custom imitations.
- Represent loading, empty, unavailable, permission-denied, and failure states
  explicitly. Never turn unknown system state into a successful empty result.
- Preserve capture cancellation and stale-response guards when views disappear
  or users change profiles quickly. Respect reduced motion and do not make
  animation necessary to understand or complete an action.
- UI tests call view models, gateways, state transitions, and product actions;
  they do not assert source text, spacing prose, script output, or generated
  markup. Use `$test-openjoystickdriver` for the test contract.

## Quick start

1. **Name the user outcome.** State the user, entry point, action, visible
   states, permission/runtime dependencies, and failure recovery.
2. **Audit the current flow.** Find the composition root, reusable window,
   presentation state machine, typed gateway, nearest product-test owner, and
   existing accessibility seams. Preserve unrelated behavior.
3. **Choose native interaction.** Compare the current control/navigation with
   the macOS HIG pattern; keep platform conventions, focus order, labels,
   keyboard access, appearance, and reduced-motion behavior explicit.
4. **Implement one boundary.** Keep presentation state in `App/Presentation`,
   domain behavior in Kit, runtime composition in the app root, and permissions
   truthful. Do not add a second gateway or lifecycle path.
5. **Exercise real product behavior.** Add or update matching tests for state,
   gateway calls, cancellation, errors, and user actions. Use the real app/runtime
   seam and `$skizzles:design-proof-gate` for screenshot/accessibility evidence.
6. **Validate and report.** Run the global skill validator, focused product
   tests, applicable repository gates, `git diff --check`, and visual proof.
   Report platform or hardware limits instead of substituting prose assertions.

## Reference map

| Need | Load |
|---|---|
| Product presentation owners and nearest tests | `$organize-openjoystickdriver` |
| Shared package, generated, and product boundary contract | `$maintain-openjoystickdriver` |
| Product-only test and gate contract | `$test-openjoystickdriver` |
| Apple interaction and accessibility guidance | `$apple-design-hig` |
| Screenshot-backed visual acceptance | `$skizzles:design-proof-gate` |
| Product-specific UI seams | `references/apple-platform.md` |

## Completion criteria

- The user flow has one clear entry point, one reusable settings window, one
  runtime gateway, semantic controls, truthful state, and accessible recovery.
- VoiceOver labels/focus, Full Keyboard Access, appearance/text sizing, reduced
  motion, loading/error/empty/permission states, and stale/cancellation behavior
  are verified for the changed flow.
- Domain/package boundaries and matching product tests remain intact; no script,
  prose, source-text, or generated-output fixture was added.
- Focused tests, applicable repository gates, visual/accessibility proof, and the
  global skill validator pass, or each blocker is named with exact evidence.
- The handoff states the changed user flow, runtime boundary, proof artifacts,
  commands/results, and remaining platform limitations.

## Validation instructions

Run the global validator and focused product proof:

```sh
python3 "$HOME/.agents/scripts/validate_skill.py" .agents/skills/design-openjoystickdriver
swift test --filter OpenJoystickDriverTests
```

Then run the applicable product gates from `$test-openjoystickdriver` and the
real app/runtime or screenshot/accessibility proof from
`$skizzles:design-proof-gate`. Use `$apple-design-hig` for the platform review;
do not claim visual acceptance from string assertions.

## Related skills

- `$maintain-openjoystickdriver` — implementation and package boundaries.
- `$organize-openjoystickdriver` — source/test ownership and topology.
- `$test-openjoystickdriver` — product-only behavior tests and gates.
- `$apple-design-hig` — Apple HIG and accessibility review.
- `$skizzles:design-proof-gate` — screenshot-backed production UI proof.
