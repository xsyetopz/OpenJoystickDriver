---
name: ojd-app-ui
description: >-
  Designs and changes OpenJoystickDriver's menu-bar and settings experience in
  the OpenJoystickDriverPresentation target: AppKit window and status-item
  lifecycle, SwiftUI panes, @MainActor view models behind
  ApplicationServiceGateway, explicit loading/denied/stale/error states,
  keyboard and VoiceOver access, macOS 12 fallbacks, and localized copy.
  Use when adding or changing a pane, menu item, profile editor flow, input
  test window, permission prompt, or UI string. Not for runtime, RPC, or
  domain logic (ojd-swift-change) or physical output proof
  (ojd-hardware-evidence).
---

# OpenJoystickDriver App UI

Deliver one native, accessible user flow in Presentation, with its states and recovery path spelled out. Controller and protocol behavior stay outside the views.

## Workflow

1. Read `docs/development/menu-bar-settings-architecture.md` (owners, gateway contract, and state rules), `LOCALIZATION.md`, the affected source, and its mirror under `Tests/OpenJoystickDriverPresentationTests/`.
1. Write down the primary action, its prerequisite, the success state, and the recovery path. Then list which [required states](references/states-and-proof.md#required-states) apply.
1. Put the change at its [owner](references/ownership.md#presentation-owners). Views hold transient visual state. `@MainActor` view models hold workflow state. Coordinators and window controllers hold AppKit lifecycle and panels.
1. Reach the runtime only through `ApplicationServiceGateway`. When the gateway lacks a call, add it to the Kit client and the Service server first (`ojd-swift-change`), then [extend the gateway](references/ownership.md#gateway-seam).
1. Add strings to the Kit template catalog, then reference them with `OJDLocalized` ([localized copy](references/states-and-proof.md#localized-copy)).
1. Test view-model behavior against `GatewayStub` ([state tests](references/states-and-proof.md#state-tests)). Then run `swift test --filter OpenJoystickDriverPresentationTests`, `just lint`, and `swift test --no-parallel`.
1. Check the [proof points](references/states-and-proof.md#proof-points) in the running app. Report any you could not check as unverified.

## Route the Problem To a Card

| Situation | Card |
| --- | --- |
| Where a view, model, or coordinator goes | [Presentation owners](references/ownership.md#presentation-owners) |
| The UI needs data or an action from the runtime | [Gateway seam](references/ownership.md#gateway-seam) |
| A second window, runtime, or CLI subprocess appears | [Single window and runtime](references/ownership.md#single-window-and-runtime) |
| Spinner forever, blank pane, silent failure | [Required states](references/states-and-proof.md#required-states) |
| Old response overwrites a newer one | [Required states](references/states-and-proof.md#required-states) (stale) |
| Testing a view model | [State tests](references/states-and-proof.md#state-tests) |
| New label, alert, or button text | [Localized copy](references/states-and-proof.md#localized-copy) |
| API newer than macOS 12 | [Proof points](references/states-and-proof.md#proof-points) |

## Rules

- Presentation imports Kit only. `DeviceManager`, `RemappingProfileLibrary`, socket frames, and CLI parsers do not reach this target, and the compiler enforces it.
- The app has one `ApplicationServiceRuntime`, one reusable settings window, and no CLI subprocess. A second instance would fight the first for devices and the RPC socket.
- A newer API needs `#available` with a macOS 12 path. `@Observable` and `NavigationStack` are not available on the deployment floor.
- State is text plus a symbol or shape, never colour alone. A value that truncates visually stays complete for VoiceOver.
- Do not test view prose or read Swift source in tests. Copy changes per locale, and a source-text test passes on broken behavior.
- Do not claim hardware behavior from previews, stubs, or source reading. Hardware claims go to `ojd-hardware-evidence`.

## References

- [Ownership](references/ownership.md): presentation owners, gateway seam, single window and runtime.
- [States and proof](references/states-and-proof.md): required states, state tests, localized copy, proof points.

## Completion Evidence

The report gives the user path, the states covered (with the test for each), localization keys added, and the commands run with their results. It lists the proof points checked in the running app and those left unverified, such as VoiceOver, Full Keyboard Access, appearance, reduced motion, TCC transitions, and macOS 10.15.
