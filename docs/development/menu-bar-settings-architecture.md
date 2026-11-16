# Menu-Bar and Settings UI Architecture

- **Status:** Architecture decision
- **Scope:** The macOS menu-bar app, reusable settings window, and controller-mapping editor.
- **Out of scope:** DriverKit topology, controller-record generation, profile-schema changes, and new diagnostic RPCs.

## Decision

The UI lives in the `OpenJoystickDriverPresentation` library, which depends on `OpenJoystickDriverKit` only. The `OpenJoystickDriver` executable composes it with the runtime.

- `NSStatusItem` and a shallow `NSMenu` provide the menu-bar surface.
- `MainWindowController` owns the main window, its sidebar areas, the last area and the window geometry across launches, and close/reopen behavior; `SettingsWindowController` owns the Settings window and its panes.
- SwiftUI renders the settings content. AppKit remains the lifecycle shell.
- `ApplicationServiceRuntime` starts once. The shell receives an injected `ApplicationServiceGateway` backed by `ApplicationServiceClient`.
- The UI never starts a CLI subprocess, creates another runtime, or opens another RPC server.
- macOS 12 is the deployment floor. Newer APIs require an availability check and an older path.
- The consumer UI covers ordinary button, D-pad, axis, trigger, keyboard, mouse, pointer, scroll, and axis-tuning workflows. Advanced automation remains CLI-only.

## Runtime Boundary

`ApplicationServiceRuntime` is the `@MainActor` composition and process-lifecycle owner. It starts and stops the service actors but does not perform controller I/O or serve as a presentation gateway. `DeviceManager` owns physical discovery and sessions; the remapping router, permission manager, and application server retain their existing isolated responsibilities.

`HeadlessApplicationHost` is the composition root; it lives in `OpenJoystickDriverMacOSHost`, which the executable installs through `PlatformHost`. A no-argument launch starts the runtime and the AppKit presentation shell. Argument-bearing launches keep the existing CLI path.

```text
main.swift
  ├─ arguments ─► CLI ─► existing commands and services
  └─ no arguments ─► HeadlessApplicationHost (via PlatformHosts.current.runApplication())
                      ├─ ApplicationServiceRuntime
                      └─ AppKit shell
                           ├─ NSStatusItem / NSMenu
                           ├─ MainWindowController / SwiftUI
                           ├─ SettingsWindowController / SwiftUI
                           └─ ApplicationServiceGateway
                                └─ ApplicationServiceClient / local RPC
```

The gateway is the only presentation-to-service seam. Views and view models do not access `DeviceManager`, `RemappingProfileLibrary`, socket frames, or CLI parsers. `OpenJoystickDriverKit` remains independent of SwifterKit.

Input Test uses this same seam for live input, rumble, player indicators, brightness, motion calibration, and tokenized temporary color previews. It does not bypass RPC through the in-process runtime. Releasing a preview token restores the next authoritative physical-color owner.

## Presentation Ownership

Feature and screen ViewModels are `@MainActor` and own asynchronous workflow state. Store service payloads once and derive presentation values from them. Views own only transient visual state; coordinators own AppKit lifecycle and panels.

`RuntimeViewModel` is the single controller-inventory refresh coordinator for settings and the menu bar. Overlapping callers merge their requested scopes into one trailing refresh rather than dropping work, and only one gateway request executes at a time. A transient background failure preserves the last authoritative inventory. Controllers selection is reconciled only when that inventory changes.

Developer snapshot and capture requests use one replaceable operation. Switching controllers, refreshing, stopping capture, and closing the window cancel and await the predecessor; publication also requires both the current operation generation and session token. Device I/O, parsing, packet differencing, classification, and bulk row formatting remain outside `@MainActor`. The main actor publishes observable snapshots and owns the SwiftUI/AppKit lifecycle only.

| Area | Owner | Boundary |
| --- | --- | --- |
| App lifecycle and status item | `Sources/OpenJoystickDriverPresentation/MenuBar/MenuBarCoordinator.swift` | AppKit activation, status menu, and termination only |
| Main window | `Sources/OpenJoystickDriverPresentation/MainWindow/` | One reusable window, sidebar areas, toolbar, problem banner, and the last area and geometry across launches |
| Main menu | `Sources/OpenJoystickDriverPresentation/MainMenu/` | Menu model and its AppKit rendering |
| Settings window | `Sources/OpenJoystickDriverPresentation/SettingsWindow/` | General, Notifications, and Advanced panes and toolbar selection |
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

The menu has a stated purpose: show the state of each connected controller, choose a controller's profile, pause or resume a controller, open the window or Settings, and quit. `StatusItemModel` holds the menu as data; `MenuBarCoordinator+StatusMenu.swift` renders it.

Rows, from top to bottom:

- a problem row for each problem that needs the user: `Permission Missing: <name>` opens the Access area at that permission, and `Service Not Running: Start It` starts the service. `MenuBarViewModel` reads the problems from the status RPC through `StatusItemState.problems`;
- one row per connected controller, with its battery level, active profile and paused state, or one disabled `No Controller Connected` row, which is not a problem. A controller row has one submenu: a checkmarked profile list ending in `No Profile` (`More Profiles` after ten, which opens the Profiles area), Pause or Resume, Test Input, Show in Window and, for a wireless controller, Disconnect Wireless Link;
- Open OpenJoystickDriver, Settings, and Quit.

The menu has two levels. Activity Log, Explain Error Code, Report Problem and Project Website are in the Help menu of the main menu. Do not put refresh, profile editing, logs, reports, packet streams, raw identifiers, catalog audits, support tests, contributor diagnostics, or metrics dashboards in the menu.

The icon is the controller symbol, or a warning triangle while a problem row exists, so a problem shows by shape and not by color alone. A state with no controller connected keeps the controller symbol. The accessibility label names the first problem, `no controller connected`, or `ready`.

The item sets `behavior = .removalAllowed`. Dragging it out with Command makes `isVisible` false; `MenuBarCoordinator` then stores Show in menu bar off and Show in Dock on in one settings write (`SettingsPreferencesModel.menuBarItemRemoved()`), which removes the item and opens the main window. When the write fails the item is made visible again. The two settings are never both off: the store refuses a write that would turn both off. A settings file that has both off is read as `storedNoVisibleEntryPoint`; the item then shows whatever Show in menu bar says, the main window opens at launch, and an alert offers Reset Settings, Show in Finder, and Quit. Opening the app again while it runs opens the main window through `applicationShouldHandleReopen`.

### Main Window

The main window has a sidebar with five areas, selected with Command-1 to Command-5: Controllers, Profiles, Library, Access and Activity. Dirty profile edits intercept an area change and offer Cancel or Discard.

1. **Controllers:** the connected controllers and the selected controller's detail: facts, Input Test, the Served by picker, the virtual HID profile, Draft Record and Capture Packets.
2. **Profiles:** profile list and the selected profile's Assignments editor.
3. **Library:** controller records and mods, with Validate, Install, Replace, Remove and Test Record.
4. **Access:** permission rows with a request action each, the local endpoint, programs with access, tokens, refused requests and open connections.
5. **Activity:** the log and the diagnostics checks.

The Settings window has three panes: General, Notifications and Advanced. Raw packet, watch, and catalog workflows remain CLI-only except for the Developer Tools in the Advanced pane.

The resizable window opens at its initial size and reuses one controller. Profile rows use native list/table controls, not a bitmap or coordinate hit map.

### Profile Editing

- Capture is non-blocking, cancellable with Cancel or Escape, and keeps the window usable.
- Axis adjustment is available only for axis and axis-direction sources.
- Native key capture handles modifiers and Clear.
- Saves go through `updateRemappingProfile(_:expectedCurrent:)`.
- A conflict preserves the draft and offers Reload or Keep editing. It never overwrites silently.
- Profile mutation controls are disabled while a save or other mutation is active.
- Delete uses destructive button semantics.
- Profile alerts use one `alert(item:)`; capture and adjustment use one `sheet(item:)`.

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
just catalog-regenerate --check
just check-profiles
just lint
python3 -m unittest discover -s Tests/RepositoryScripts
just driverkit-check
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
