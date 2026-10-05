# Menu-Bar and Settings UI Architecture

- **Status:** Architecture decision
- **Scope:** The macOS menu-bar app, reusable settings window, and controller-mapping editor.
- **Out of scope:** DriverKit topology, controller-record generation, profile-schema changes, and new diagnostic RPCs.

## Decision

The UI lives in the `OpenJoystickDriverPresentation` library, which depends on `OpenJoystickDriverKit` only. The `OpenJoystickDriver` executable composes it with the runtime.

- `NSStatusItem` and a shallow `NSMenu` provide the menu-bar surface.
- One `NSWindowController` owns the settings window, activation, pane restoration, and close/reopen behavior.
- SwiftUI renders the settings content. AppKit remains the lifecycle and 10.15 compatibility shell.
- `ApplicationServiceRuntime` starts once. The shell receives an injected `ApplicationServiceGateway` backed by `ApplicationServiceClient`.
- The UI never starts a CLI subprocess, creates another runtime, or opens another RPC server.
- macOS 12 is the deployment floor. Newer APIs require an availability check and an older path.
- The consumer UI covers ordinary button, D-pad, axis, trigger, keyboard, mouse, pointer, scroll, and axis-tuning workflows. Advanced automation remains CLI-only.

## Runtime Boundary

`ApplicationServiceRuntime` is the `@MainActor` composition and process-lifecycle owner. It starts and stops the service actors but does not perform controller I/O or serve as a presentation gateway. `DeviceManager` owns physical discovery and sessions; the remapping router, permission manager, and application server retain their existing isolated responsibilities.

`HeadlessApplicationHost` is the composition root. A no-argument launch starts the runtime and the AppKit presentation shell. Argument-bearing launches keep the existing CLI path.

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

The gateway is the only presentation-to-service seam. Views and view models do not access `DeviceManager`, `RemappingProfileLibrary`, socket frames, or CLI parsers. `OpenJoystickDriverKit` remains independent of SwifterKit.

Input Test uses this same seam for live input, rumble, player indicators, brightness, motion calibration, and tokenized temporary color previews. It does not bypass RPC through the in-process runtime. Releasing a preview token restores the next authoritative physical-color owner.

## Presentation Ownership

Feature and screen ViewModels are `@MainActor` and own asynchronous workflow state. Store service payloads once and derive presentation values from them. Views own only transient visual state; coordinators own AppKit lifecycle and panels.

`RuntimeViewModel` is the single controller-inventory refresh coordinator for settings and the menu bar. Overlapping callers merge their requested scopes into one trailing refresh rather than dropping work, and only one gateway request executes at a time. A transient background failure preserves the last authoritative inventory. Controllers selection is reconciled only when that inventory changes.

Developer snapshot and capture requests use one replaceable operation. Switching controllers, refreshing, stopping capture, and closing the window cancel and await the predecessor; publication also requires both the current operation generation and exact runtime identifier. Device I/O, parsing, packet differencing, classification, and bulk row formatting remain outside `@MainActor`. The main actor publishes observable snapshots and owns the Catalina-compatible SwiftUI/AppKit lifecycle only.

| Area | Owner | Boundary |
| --- | --- | --- |
| App lifecycle and status item | `Sources/OpenJoystickDriverPresentation/MenuBar/MenuBarCoordinator.swift` | AppKit activation, status menu, and termination only |
| Settings window lifecycle | `Sources/OpenJoystickDriverPresentation/Settings/Shell/WindowController.swift` | One reusable window, toolbar selection, geometry persistence, and pane activation |
| Settings panes and access summary | `Sources/OpenJoystickDriverPresentation/Settings/Shell/SettingsNavigation.swift` | Pane navigation, native toolbar symbols, permission presentation, and shared accessibility compatibility |
| Developer diagnostics | `Sources/OpenJoystickDriverPresentation/Settings/Developer/` | Replaceable diagnostic operation, compact controller facts, bounded capture presentation, and virtualized packet rows |
| Shared settings primitives | `Sources/OpenJoystickDriverPresentation/Components/{SettingsRows,StateViews}.swift` | Headers, rows, loading, empty, and error states |
| Controller details and identity | `Sources/OpenJoystickDriverPresentation/Controllers/Inventory/ControllersView.swift` | Connected devices, identity selection, loading, failure, and retry |
| Profiles and editor | `Sources/OpenJoystickDriverPresentation/Profiles/{List/ProfilesView,Editor/ProfileEditorViews}.swift` | Selection, drafts, assignments, save/conflict flow, and profile actions |
| Mapping capture | `Sources/OpenJoystickDriverPresentation/Profiles/Editor/MappingCaptureViews.swift`, `Sources/OpenJoystickDriverPresentation/InputCapture/KeyboardCaptureViews.swift` | Controller and keyboard capture plus axis adjustment |
| Presentation state | `Sources/OpenJoystickDriverPresentation/Runtime/{RuntimeViewModel,SupportState}.swift` | Loading, permission, input, virtual HID profile override, mutation, diagnostics, and conflict state |
| Service adapter | `Sources/OpenJoystickDriverPresentation/Runtime/ApplicationServiceGateway.swift` | Typed `ApplicationServiceClient` calls and stable presentation errors |

Add files only for focused, independently testable capabilities. Group related helpers rather than splitting by individual control or visual role.

## Settings Surface

### Menu Bar

Menu items:

- one readiness, controller-count, and active-profile summary;
- `Request access...` only when permissions need attention;
- connected-controller shortcuts;
- Open Workbench, Settings, Help/About, and Quit.

Do not put refresh, profile editing, logs, reports, packet streams, raw identifiers, catalog audits, support tests, contributor diagnostics, or metrics dashboards in the menu.

### Settings Window

Use one visible native `NSToolbarItemGroup` for the four panes. The selected pane and window geometry persist across launches. Dirty profile edits intercept pane changes and offer Cancel or Discard.

1. **Overview:** readiness, controller count, and the Access & readiness summary. Input Monitoring, controller publication, and Keyboard & pointer each have an explicit request action.
1. **Controllers:** friendly names, connection state, selected profile, controller identity, and technical identifiers in the selected-device detail.
1. **Profiles:** profile list and the selected profile's Assignments editor.
1. **Debug:** typed runtime/controller details, diagnostics collection, Save report, and Save logs. Raw packet, watch, and catalog workflows remain CLI-only.

The resizable window opens at its initial size and reuses one controller. Profile rows use native list/table controls, not a bitmap or coordinate hit map.

### Profile Editing

- Capture is non-blocking, cancellable with Cancel or Escape, and keeps the window usable.
- Axis adjustment is available only for axis and axis-direction sources.
- Native key capture handles modifiers and Clear.
- Saves go through `updateRemappingProfile(_:expectedCurrent:)`.
- A conflict preserves the draft and offers Reload or Keep editing. It never overwrites silently.
- Profile mutation controls are disabled while a save or other mutation is active.
- Delete uses destructive button semantics where available and a macOS 10.15 fallback.
- Profile alerts use one `alert(item:)`; capture and adjustment use one `sheet(item:)` for the 10.15 presentation path.

## Gateway Contract

`ApplicationServiceGateway` covers the current presentation surfaces:

```text
status()
virtualDeviceDiagnostics()
requestPermissions()
requestPermission(requirement)
controllerState(selector)
packetLog(selector)
sendControllerOutput(command, selector)/previewColor/releaseColorPreview
motionCalibration(selector, command)
remappingSnapshot()
remappingProfile(id)
create/update(expectedCurrent)/import/delete profile
activate/deactivate profile
remappingPostEventAccess()/requestRemappingPostEventAccess()
setVirtualHIDProfileOverride(profile, for: selector)/resetVirtualHIDProfileOverride(for: selector)
```

The adapter connects the existing client, returns typed payloads, and maps transport failures to stable presentation errors. It does not expose socket paths, CLI text, or raw RPC descriptions.

## State and Permission Rules

- Loading, unavailable, empty, denied, requesting, saving, conflict, and failed states are explicit.
- A stale async response cannot replace newer permission, post-event, virtual HID profile, or input state.
- A superseded permission request does not open a Privacy & Security pane.
- A denied result opens the matching native recovery destination. Only the authoritative follow-up read establishes a grant.
- Controller publication and CoreGraphics keyboard/pointer posting remain separate permission paths.
- Failed controller-identity requests remain retry intent only; the picker and accessibility value use the last authoritative identity.

## Compatibility and Accessibility

- Keep newer APIs behind `#available`; use AppKit template images and SwiftUI compatibility modifiers for macOS 12.
- Prefer 28-point controls and never make an interactive target smaller than 20 points.
- Use semantic system colors, system typography, and text plus icon/shape for state. Never rely on color alone.
- Keep full values available to VoiceOver when visual text truncates.
- Preserve keyboard and mouse paths, Escape cancellation, reduced-motion alternatives, and Full Keyboard Access through the visible toolbar, lists, rows, and editor controls.
- Add no generated artwork. Use SF Symbols with AppKit template fallbacks.

## Validation

Run the repository gates relevant to the change:

```bash
./Scripts/ojd catalog regenerate --check
./Scripts/ojd check profiles
just lint
python3 -m unittest discover -s Tests/RepositoryScripts
./Scripts/ojd check driverkit
swift test
```

The package tests cover injected gateway state, permission generation, profile drafts, diagnostics, and settings navigation. Runtime acceptance still requires a signed app on supported macOS versions:

- TCC transitions;
- VoiceOver and Full Keyboard Access;
- appearance and reduced motion;
- hardware and DriverKit activation checks.

## Design References

- [Apple Settings HIG](https://developer.apple.com/design/human-interface-guidelines/settings)
- [Apple Accessibility HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Apple Designing for macOS HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)
