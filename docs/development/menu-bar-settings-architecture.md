# Menu-Bar and Settings UI Architecture

- Status: Architecture decision
- Scope: menu-bar app, settings window, mapping editor.
- Out of scope: DriverKit topology, record generation, profile-schema changes, added diagnostic RPCs.

## Decision

The UI is the `OpenJoystickDriverPresentation` library, which depends only on `OpenJoystickDriverKit`. The `OpenJoystickDriver` executable composes it with the runtime.

| Component | Role |
| --- | --- |
| NSStatusItem, shallow NSMenu | Menu-bar surface |
| `MainWindowController` | Main window, sidebar areas, geometry across launches, close and reopen |
| SettingsWindowController | Settings |
| SwiftUI / AppKit | SwiftUI renders content; AppKit is the lifecycle shell |
| `ApplicationServiceRuntime` | Starts once. The shell gets an injected `ApplicationServiceGateway` backed by `ApplicationServiceClient` |

The UI starts no CLI subprocess, second runtime, or RPC server. The consumer UI covers button, D-pad, axis, trigger, keyboard, mouse, pointer, scroll, and axis-tuning workflows. Advanced automation is CLI-only.

## Runtime Boundary

`ApplicationServiceRuntime` (@MainActor) owns the process lifecycle, starts and stops the service actors, and does no controller I/O. `DeviceManager` owns discovery and sessions.

HeadlessApplicationHost, the composition root in OpenJoystickDriverMacOSHost, starts the runtime and AppKit shell; with arguments, the CLI runs.

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

The gateway is the only presentation-to-service seam: views and view models never touch `DeviceManager`, RemappingProfileLibrary, socket frames, or CLI parsers. `OpenJoystickDriverKit` does not depend on SwifterKit.

Input Test uses the gateway for live input, output, motion calibration, and tokenized color previews; releasing a token restores the next physical-color owner.

## Presentation Ownership

@MainActor ViewModels own async workflow state: store service payloads once, derive presentation values. Views own transient visual state; coordinators own AppKit lifecycle and panels.

`RuntimeViewModel` is the one inventory refresh coordinator for settings and the menu bar: overlapping callers merge into one trailing refresh, one gateway request at a time. A transient failure keeps the last authoritative inventory.

Developer snapshot and capture requests use one replaceable operation; switching controllers, refreshing, stopping capture, and closing the window cancel and await the predecessor. Publication needs the current generation and session token. Device I/O, parsing, packet differencing, and row formatting stay off @MainActor.

| Area | Owner | Boundary |
| --- | --- | --- |
| App lifecycle and status item | `Sources/OpenJoystickDriverPresentation/MenuBar/MenuBarCoordinator.swift` | AppKit activation, status menu, termination only |
| Main window | `Sources/OpenJoystickDriverPresentation/MainWindow/` | One reusable window, sidebar areas, toolbar, problem banner, last area and geometry |
| Main menu | `Sources/OpenJoystickDriverPresentation/MainMenu/` | Menu model and its AppKit rendering |
| Settings window | `Sources/OpenJoystickDriverPresentation/SettingsWindow/` | General, Notifications, Advanced panes, toolbar selection |
| Developer diagnostics | `Sources/OpenJoystickDriverPresentation/Settings/Developer/` | Replaceable diagnostic operation, controller facts, bounded capture, virtualized packet rows |
| Shared settings primitives | `Sources/OpenJoystickDriverPresentation/Components/{SettingsRows,StateViews}.swift` | Headers, rows, loading, empty, and error states |
| Controller details and identity | `Sources/OpenJoystickDriverPresentation/Controllers/Inventory/ControllersView.swift` | Connected devices, identity selection, loading, failure, retry |
| Profiles and editor | `Sources/OpenJoystickDriverPresentation/Profiles/{List/ProfilesView,Editor/ProfileEditorViews}.swift` | Selection, drafts, assignments, save/conflict flow, profile actions |
| Mapping capture | `Sources/OpenJoystickDriverPresentation/Profiles/Editor/MappingCaptureViews.swift`, `Sources/OpenJoystickDriverPresentation/InputCapture/KeyboardCaptureViews.swift` | Controller and keyboard capture plus axis adjustment |
| Presentation state | `Sources/OpenJoystickDriverPresentation/Runtime/{RuntimeViewModel,SupportState}.swift` | Loading, permission, input, virtual HID profile override, mutation, diagnostics, conflict state |
| Service adapter | `Sources/OpenJoystickDriverPresentation/Runtime/ApplicationServiceGateway.swift` | Typed `ApplicationServiceClient` calls, stable presentation errors |

Add files only for focused, independently testable capabilities.

## Settings Surface

### Menu Bar

`StatusItemModel` holds the menu as data; `MenuBarCoordinator+StatusMenu.swift` renders it.

| Row | Content |
| --- | --- |
| Problem (one per problem needing the user) | `Permission Missing: <name>` opens Access at that permission; a service problem row starts the service (title text not verified). MenuBarViewModel reads problems from the status RPC via StatusItemState.problems |
| Controller (one per connected) | Battery level, active profile, paused state. With none: disabled No Controller Connected row |
| Controller submenu | Checkmarked profile list ending in No Profile (More Profiles after ten, opening Profiles); Pause or Resume; Test Input; Show in Window; for wireless, Disconnect Bluetooth Connection |
| Fixed | Open OpenJoystickDriver, Settings, Quit |

The menu has two levels. Activity Log, Explain Error Code, Report Problem, and Project Website are in Help. Keep logs, reports, packet streams, raw identifiers, and audits out.

The icon is a controller symbol, or a warning triangle while a problem row exists. Its accessibility label is the first problem, no controller connected, or ready.

The item sets `behavior = .removalAllowed`. Command-dragging it out makes `isVisible` false; `MenuBarCoordinator` then writes Show in menu bar off and Show in Dock on in one write (`SettingsPreferencesModel.menuBarItemRemoved()`) and opens the main window. A failed write shows the item again. The store refuses a write that turns both off; a settings file with both off reads as `storedNoVisibleEntryPoint`, opening the main window at launch with an alert offering Reset Settings, Show in Finder, and Quit. `applicationShouldHandleReopen` opens the main window.

### Main Window

Dirty profile edits intercept an area change, offering Cancel or Discard.

| Area | Shortcut | Content |
| --- | --- | --- |
| Controllers | Command-1 | Connected controllers, selected controller facts, Input Test, Handled by picker, virtual HID profile, Draft Record, Capture Packets |
| Profiles | Command-2 | Profile list, Assignments editor |
| Library | Command-3 | Controller records and mods; Validate, Install, Replace, Remove, Test Record |
| Access | Command-4 | Permissions, local endpoint, programs with access, tokens, refused requests, open connections |
| Activity | Command-5 | Log, diagnostics checks |

Settings has General, Notifications, and Advanced panes. Raw packet, watch, and catalog workflows are CLI-only, except Developer Tools in Advanced. Profile rows use native list and table controls, not a bitmap hit map.

### Profile Editing

| Topic | Rule |
| --- | --- |
| Capture | Non-blocking; Cancel or Escape stops it |
| Axis adjustment | Only axis and axis-direction sources |
| Key capture | Native; handles modifiers and Clear |
| Save | `updateRemappingProfile(_:expectedCurrent:)`; a conflict keeps the draft and offers Reload or Keep Editing |
| Mutation | Controls disabled; Delete uses destructive button semantics |
| Presentation | One `alert(item:)` for profile alerts; one `sheet(item:)` for capture and adjustment |

## Gateway Contract

`ApplicationServiceGateway` covers:

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

The adapter returns typed payloads, maps transport failures to stable presentation errors, and exposes no socket paths, CLI text, or raw RPC descriptions.

## State and Permission Rules

| Topic | Rule |
| --- | --- |
| States | Loading, unavailable, empty, denied, requesting, saving, conflict, failed are explicit |
| Stale response | Cannot replace newer permission, post-event, virtual HID profile, or input state |
| Permission request | Superseded: opens no Privacy & Security pane. Denied: opens the recovery pane. Only the authoritative follow-up read establishes a grant |
| Paths | Controller publication and CoreGraphics keyboard and pointer posting have separate permission paths |
| Identity request | A failed one is retry intent only; the picker uses the last authoritative identity |

## Compatibility and Accessibility

| Topic | Rule |
| --- | --- |
| Deployment floor | macOS 12. Newer APIs behind `#available` with an older path; AppKit template images and SwiftUI compatibility modifiers |
| Targets | 28 points preferred, 20 minimum for interactive targets |
| Color and type | Semantic system colors and typography; text plus icon or shape for state |
| VoiceOver | Full values available when text truncates |
| Keyboard and motion | Keyboard paths, Escape cancellation, reduced-motion alternatives, Full Keyboard Access |
| Symbols | SF Symbols with AppKit template fallbacks |

## Validation

Run the fitting gates:

```bash
just catalog-regenerate --check
just check-profiles
just lint
python3 -m unittest discover -s Tests/RepositoryScripts
just driverkit-check
swift test
```

Package tests cover injected gateway state, permission generation, profile drafts, diagnostics, and settings navigation. Runtime acceptance needs a signed app on supported macOS versions:

| Check |
| --- |
| TCC transitions |
| VoiceOver and Full Keyboard Access |
| Appearance and reduced motion |
| Hardware and DriverKit activation |

## Design References

- [Apple Settings HIG](https://developer.apple.com/design/human-interface-guidelines/settings)
- [Apple Accessibility HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Apple Designing for macOS HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)

## Further Reading

- [Architecture](architecture.md)
- [Source Topology](source-topology.md)
