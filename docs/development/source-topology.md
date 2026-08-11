# Source topology

OpenJoystickDriver uses capability directories inside its existing SwiftPM targets. A directory
names a durable owner and lifecycle; a test directory mirrors the source capability that it proves.
This is a path-level architecture decision: module names, products, RPC contracts, resources,
entitlements, and generated DriverKit output are unchanged.

## Package boundaries

```text
OpenJoystickDriverKit       reusable controller domain and shared service contracts
  └─ OpenJoystickDriverRelay  SwifterKit DriverKit relay adapter
       └─ DriverKitGenerator  build-time native-project generator
OpenJoystickDriver          composition root: app shell, runtime, CLI, and platform adapters
OpenJoystickDriverHIDTool   internal hardware investigation executable
OpenJoystickDriverGameControllerProbe  isolated GameController visibility probe
```

The dependency direction remains inward:

```text
OpenJoystickDriverKit ← OpenJoystickDriverRelay ← DriverKitGenerator
OpenJoystickDriverKit ← OpenJoystickDriverRelay ← OpenJoystickDriver
OpenJoystickDriverKit ← OpenJoystickDriver
OpenJoystickDriverKit ← OpenJoystickDriverHIDTool
```

`OpenJoystickDriverKit` never imports SwifterKit. `OpenJoystickDriverRelay` is the only runtime
adapter that does. The application owns the single `ApplicationServiceRuntime` and authenticated
RPC socket; presentation and CLI code do not create another runtime or server.

## Architecture decision

**Decision:** organize capabilities inside the existing SwiftPM targets and mirror those
capabilities in the matching test targets. Keep package products, module boundaries, public
contracts, and generated DriverKit ownership unchanged.

**Forces and quality scenarios:**

- **Discoverability:** an agent following a capability name from `Sources/` reaches the behavior
  tests under the same relative owner in `Tests/` without guessing between phase or type buckets.
- **Separation of concerns:** reusable controller/protocol behavior stays in Kit; AppKit/SwiftUI,
  CLI, runtime composition, status, and CoreGraphics adaptation stay in the app target.
- **Apple-platform coherence:** menu-bar lifecycle, one reusable settings window, semantic native
  controls, loading/error/empty states, and accessibility seams remain visible under `Presentation`.
- **Regression safety:** a path-only move must leave SwiftPM target membership, imports, RPC
  contracts, resources, entitlements, generated DriverKit inputs, and test behavior unchanged.
- **Evolution:** a new capability gets one canonical source owner, one mirrored test owner, and a
  new package only when its dependency or lifecycle boundary is independently justified.

**Candidates considered:**

| Candidate | Discoverability | Separation and migration cost | Decision |
| --- | --- | --- | --- |
| Keep the flat/phase-oriented tree | Low; users and agents infer ownership from filenames | Lowest immediate cost, but preserves drift and filename colonies | Rejected |
| Capability directories inside existing targets | High; paths name user/runtime behavior and tests mirror them | Small reversible path migration; package graph remains stable | **Selected** |
| New SwiftPM target for every capability | Very high local isolation | Adds dependency edges, build cost, and public-boundary churn without a current lifecycle need | Rejected |

**Migration and rollback:** inventory the current graph, move intact source/test units into their
capability owners, consolidate only declarations with one lifecycle (status snapshots, system
extension probe state, and virtual-device identity), update canonical documentation/path literals,
then run the executable gates below. Rollback is a single reviewable reversal of the path and
documentation diff; no alias, forwarding file, or old-path tombstone is retained.

**Executable acceptance:** `swift package describe --type json` must include only canonical paths;
`./scripts/ojd check swift-structure`, `./scripts/ojd lint`, `swift test`, the catalog/profile/script
checks, parser harness, and generated unsigned DriverKit validation must pass. The architecture
enforcement command is run fail-closed with no exclusions, thresholds, baselines, or suppressions.

**Evolution triggers:** propose a new package or deeper capability split only when a capability
acquires an independent dependency direction, lifecycle/failure domain, public contract, or
behavior-owned test seam. Do not split a file solely by declaration kind, line count, view type, or
operation phase; keep the race-sensitive runtime state machine and cohesive profile editor intact.

## Shared controller domain

`Sources/OpenJoystickDriverKit/` and `Tests/OpenJoystickDriverKitTests/` use the same capability
shape:

```text
ApplicationService/  Client, RPC transport, payloads, lifecycle, remapping, compatibility
Device/              controller events, identity, input state, discovery, and USB pipeline
HID/                 HID stream, session, and device events
Diagnostics/         support reports, probes, runtime health, and packet logs
Output/              backends, foreground routing, HID reports, Xbox formats, and profiles
Permissions/         TCC access ownership
Process/             bounded process execution
Protocol/            catalog, GIP, parsers, and output capabilities
Remapping/           Profile and Engine domain capabilities
Update/              semantic versioning and update checks
```

`Integration/` is a test-only cross-capability surface for packaging and runtime checks; it is not
part of the Kit source capability map.

Tests follow those owners, for example `Device/Discovery/USBAdmissionTests.swift` proves
`Device/Discovery/USBDiscovery.swift`, `Protocol/GIP/ParserTests.swift` proves `Protocol/GIP/Parser.swift`,
and `Remapping/Engine/EngineTests.swift` proves `Remapping/Engine/Engine.swift`.

## Application composition root

`Sources/OpenJoystickDriver/` and `Tests/OpenJoystickDriverTests/` use these capability owners:

```text
App/
  Presentation/      AppKit lifecycle shell and SwiftUI settings/user flows
CLI/
  Catalog/            installed command catalog and help renderer
  Commands/           Controller, Diagnostics, Installation, Mapping, and Settings commands
Diagnostics/          app-side controller input and support-report services
Remapping/
  Profiles/           app profile library state and persistence adaptation
  Routing/            output router, scheduling, transactions, and state
  SystemEvents/       CoreGraphics access, sink, and foreground policy
Runtime/
  RPC/                authenticated application-service server boundary
  ForegroundOutput/   foreground-consumer discovery and monitor
Status/
  RuntimeSnapshot/    runtime snapshot observation
  SystemExtension/    system-extension observation
```

The presentation test tree mirrors the source user-flow ownership exactly:

```text
App/Presentation/InputCapture/  keyboard and controller capture behavior
App/Presentation/Profiles/      profile names, drafts, and editor behavior
App/Presentation/Runtime/       status, profile mutation, compatibility, gateway races, and diagnostics
App/Presentation/Settings/      settings navigation and window behavior
```

The CLI test tree mirrors command ownership under `CLI/`. Remapping, runtime, and status tests use
the same capability names as their source owners. Tests that exercise a cross-capability contract
remain under the nearest integration or owning capability; `Integration/` is the only explicit
test-only exception and is never a source owner.

## Ownership rules

- Add a directory only for an independently owned capability, state boundary, or lifecycle.
- Give each product capability one obvious canonical source path and one matching test path; do not
  retain aliases, forwarding files, or competing entry points for the same responsibility.
- Keep related helpers and extensions with their capability; do not create declaration-category,
  operation-phase, or one-type directories.
- Use nouns that describe user-visible or runtime behavior (`Presentation`, `Routing`, `Discovery`,
  `ForegroundOutput`, `SystemEvents`), not procedural buckets such as `Managers`, `Helpers`, or
  `Types`.
- Keep product source and behavior tests together in the same capability map. Tests exercise public
  or `@testable` product APIs and runtime behavior only; scripts, docs, and source prose are not
  Swift test fixtures.
- Preserve unique Swift basenames within each target. SwiftPM discovers files recursively under the
  target path, so no import or forwarding shim is needed after a move.
- Never move controller records, schemas, entitlements, or `.build/driverkit/generated/` as part of
  source organization. Change catalog generator inputs and regenerate records only for catalog work.

## Apple-platform context

Apple does not prescribe Swift folder names. The `Presentation` topology follows the product's
documented AppKit/SwiftUI lifecycle and user flows: one reusable settings window, a stable toolbar
navigation boundary, semantic native controls, explicit loading/error/empty states, and one typed
gateway into the runtime. These choices align with the current [macOS design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos),
[Settings guidance](https://developer.apple.com/design/human-interface-guidelines/settings), and
[Accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility).

Keep the race-sensitive `App/Presentation/Runtime/State.swift` state machine and the cohesive
profile editor together unless a future change establishes an independently testable user-flow
boundary. Profile draft/options declarations belong to `App/Presentation/Profiles/Draft.swift`;
the settings window controller belongs to `App/Presentation/Settings/WindowController.swift`.
Validate UI topology changes with settings navigation, stale-response, capture-cancellation,
VoiceOver, Full Keyboard Access, appearance, reduced-motion, and signed-app lifecycle checks.

## Generated boundary

The DriverKit native project remains generated by `./scripts/ojd driverkit generate` from
`DriverKitGenerator` and `OpenJoystickDriverRelay`. Generated files under `.build/driverkit/` are
ephemeral outputs and are never hand-edited, moved, or used as source ownership evidence.
