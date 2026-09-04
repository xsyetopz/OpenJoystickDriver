# Menu-bar and settings UI architecture

- **Status:** Architecture decision
- **Scope:** The macOS menu-bar app, reusable settings window, and controller-mapping editor.
- **Out of scope:** DriverKit topology, controller-record generation, profile-schema changes, and
  new diagnostic RPCs.

## Decision

Keep the UI in the existing `OpenJoystickDriver` executable.

- `NSStatusItem` and a shallow `NSMenu` provide the menu-bar surface.
- One `NSWindowController` owns the settings window, activation, pane restoration, and close/reopen
  behavior.
- SwiftUI renders the settings content. AppKit remains the lifecycle and 10.15 compatibility shell.
- `ApplicationServiceRuntime` starts once. The shell receives an injected
  `ApplicationServiceGateway` backed by `ApplicationServiceClient`.
- The UI never starts a CLI subprocess, creates another runtime, or opens another RPC server.
- macOS 10.15 is the deployment floor. Newer APIs require an availability check and an older path.
- The consumer UI covers ordinary button, D-pad, axis, trigger, keyboard, mouse, pointer, scroll, and
  axis-tuning workflows. Advanced automation remains CLI-only.

## Runtime boundary

`ApplicationServiceRuntime` remains the only owner of physical discovery, remapping, virtual output,
permission polling, foreground routing, local RPC, shutdown, and process lifetime.

`HeadlessApplicationHost` is the composition root. A no-argument launch starts the runtime and the
AppKit presentation shell. Argument-bearing launches keep the existing CLI path.

```text
main.swift
  ├─ arguments ─► CLI ─► existing commands and services
  └─ no arguments ─► HeadlessApplicationHost
                      ├─ ApplicationServiceRuntime
                      └─ AppKit shell
                           ├─ NSStatusItem / NSMenu
                           ├─ SettingsWindowController / SwiftUI
                           └─ ApplicationServiceGateway
                                └─ ApplicationServiceClient / local RPC
```

The gateway is the only presentation-to-service seam. Views and view models do not access
`DeviceManager`, `RemappingProfileLibrary`, socket frames, or CLI parsers. `OpenJoystickDriverKit`
remains independent of SwifterKit.

## Presentation ownership

| Area | Owner | Boundary |
| --- | --- | --- |
| App lifecycle and status item | `App/Presentation/MenuBar/Coordinator.swift` | AppKit activation, status menu, and termination only |
| Settings window lifecycle | `App/Presentation/Settings/WindowController.swift` | One reusable window, toolbar selection, geometry persistence, and pane activation |
| Settings panes and access summary | `App/Presentation/Settings/Shell.swift` | Pane navigation, native toolbar symbols, permission presentation, and shared accessibility compatibility |
| Shared settings primitives | `App/Presentation/Settings/Support.swift` | Headers, rows, loading, empty, and error states |
| Controller details and identity | `App/Presentation/Controllers/{ControllerViews,OutputViews}.swift` | Connected devices, identity selection, loading, failure, and retry |
| Profiles and editor | `App/Presentation/Profiles/{MappingViews,ProfileEditorViews}.swift` | Selection, drafts, assignments, save/conflict flow, and profile actions |
| Mapping capture | `App/Presentation/Profiles/MappingCaptureViews.swift`, `App/Presentation/InputCapture/KeyboardCaptureViews.swift` | Controller and keyboard capture plus axis adjustment |
| Presentation state | `App/Presentation/Runtime/{State,SupportState}.swift` | Loading, permission, input, compatibility, mutation, diagnostics, and conflict state |
| Service adapter | `App/Presentation/Runtime/Gateway.swift` | Typed `ApplicationServiceClient` calls and stable presentation errors |

Add a new file only for a focused, independently testable capability. Keep related helpers together
rather than splitting them by individual control or visual role.

## Settings surface

### Menu bar

Menu items:

- readiness and controller count;
- active profile or `No active profile`;
- direct links to Overview, Controllers, Profiles, and Debug;
- `Request access...` when permissions need attention;
- Settings and Quit.

Do not put packet streams, raw identifiers, catalog audits, support tests, or metrics dashboards in
the menu. A popover is optional and limited to transient status, capture, or axis-adjustment content.

### Settings window

Use one visible native `NSToolbarItemGroup` for the four panes. The selected pane and window geometry
persist across launches. Dirty profile edits intercept pane changes and offer Cancel or Discard.

1. **Overview:** readiness, controller count, and the Access & readiness summary. Input Monitoring,
   controller publication, and Keyboard & pointer each have an explicit request action.
2. **Controllers:** friendly names, connection state, selected profile, controller identity, and
   technical identifiers in the selected-device detail.
3. **Profiles:** profile list and the selected profile's Assignments editor.
4. **Debug:** typed runtime/controller details, diagnostics collection, Save report, and Save logs.
   Raw packet, watch, and catalog workflows remain CLI-only.

The window opens at its initial size, remains resizable, and reuses one controller.
Profile rows use native list/table controls, not a bitmap or coordinate hit map.

### Profile editing

- Capture is non-blocking, cancellable with Cancel or Escape, and keeps the window usable.
- Axis adjustment is available only for axis and axis-direction sources.
- Native key capture handles modifiers and Clear.
- Saves go through `updateRemappingProfile(_:expectedCurrent:)`.
- A conflict preserves the draft and offers Reload or Keep editing. It never overwrites silently.
- Profile mutation controls are disabled while a save or other mutation is active.
- Delete uses destructive button semantics where available and a macOS 10.15 fallback.
- Profile alerts use one `alert(item:)`; capture and adjustment use one `sheet(item:)` for the 10.15
  presentation path.

## Gateway contract

`ApplicationServiceGateway` covers the current presentation surfaces:

```text
status()
virtualDeviceDiagnostics()
requestPermissions()
requestPermission(requirement)
deviceInputState(selector)
remappingSnapshot()
remappingProfile(id)
create/update(expectedCurrent)/import/delete profile
activate/deactivate profile
remappingPostEventAccess()/requestRemappingPostEventAccess()
compatibilityIdentity()/setCompatibilityIdentity(identity)
```

The adapter connects the existing client, returns typed payloads, and maps transport failures to
stable presentation errors. It does not expose socket paths, CLI text, or raw RPC descriptions.

## State and permission rules

- Loading, unavailable, empty, denied, requesting, saving, conflict, and failed states are explicit.
- A stale async response cannot replace newer permission, post-event, compatibility, or input state.
- A superseded permission request does not open a Privacy & Security pane.
- A denied result opens the matching native recovery destination. A request return is never treated as
  a grant without the authoritative follow-up read.
- Controller publication and CoreGraphics keyboard/pointer posting remain separate permission paths.
- Failed controller-identity requests remain retry intent only; the picker and accessibility value use
  the last authoritative identity.

## Compatibility and accessibility

- Keep newer APIs behind `#available`; use AppKit template images and SwiftUI compatibility modifiers
  for macOS 10.15.
- Prefer 28-point controls and never make an interactive target smaller than 20 points.
- Use semantic system colors, system typography, and text plus icon/shape for state. Never rely on
  color alone.
- Keep full values available to VoiceOver when visual text truncates.
- Preserve keyboard and mouse paths, Escape cancellation, reduced-motion alternatives, and Full
  Keyboard Access through the visible toolbar, lists, rows, and editor controls.
- Add no generated artwork. Use SF Symbols with AppKit template fallbacks.

## Validation

Run the repository gates relevant to the change:

```bash
./scripts/ojd catalog regenerate --check
./scripts/ojd check profiles
./scripts/ojd check scripts
./scripts/ojd check swift-structure
./scripts/ojd lint
./scripts/ojd check driverkit
swift test
```

The package tests cover injected gateway state, permission generation, profile drafts, diagnostics,
and settings navigation. Runtime acceptance still requires a signed app on supported macOS versions:

- TCC transitions;
- VoiceOver and Full Keyboard Access;
- appearance and reduced motion;
- hardware and DriverKit activation checks.

## Design references

- [Apple Settings HIG](https://developer.apple.com/design/human-interface-guidelines/settings)
- [Apple Accessibility HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Apple Designing for macOS HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)
