# Menu-Bar and Settings UI Architecture

How the menu-bar icon, the main window, and Settings are built. Think of the windows as a shop front and the background engine as the stock room: the front only asks through one counter (the gateway), and never walks into the back.

- Status: decided
- Covers: the menu-bar app, the settings window, and the mapping editor.
- Doesn't cover: how DriverKit is laid out, record generation, changes to the profile format, or extra diagnostic RPCs.

## What We Decided

The UI is the `OpenJoystickDriverPresentation` library, which only uses `OpenJoystickDriverKit`. The `OpenJoystickDriver` program joins it to the engine.

| Part | Job |
| --- | --- |
| NSStatusItem, shallow NSMenu | The menu-bar icon and its menu |
| `MainWindowController` | Main window, sidebar areas, remembering its size and place, closing and reopening |
| SettingsWindowController | Settings |
| SwiftUI / AppKit | SwiftUI draws the content. AppKit runs the app's start, windows, and quit |
| `ApplicationServiceRuntime` | Starts once. The windows get an `ApplicationServiceGateway`, passed in from outside, that uses `ApplicationServiceClient` |

The UI starts no command-line process, second engine, or RPC server. The everyday UI covers buttons, D-pad, axes, triggers, keyboard, mouse, pointer, scrolling, and axis tuning. Advanced scripting is command line only.

## Where the Windows End and the Engine Begins

`ApplicationServiceRuntime` (@MainActor) runs the process from start to quit, starts and stops the service actors, and never reads or writes a controller itself. `DeviceManager` finds controllers and runs their sessions.

HeadlessApplicationHost in OpenJoystickDriverMacOSHost wires the parts together and starts the engine and the AppKit windows. With arguments, the command-line tool runs instead.

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

The gateway is the only door from the windows to the service. Views and view models never touch `DeviceManager`, RemappingProfileLibrary, socket frames, or command-line parsers. `OpenJoystickDriverKit` does not depend on SwifterKit.

Input Test uses the gateway for live input, output, motion calibration, and color previews. Each preview holds a token, and giving the token back returns the light color to whoever set it before.

## Which Code Owns Which Screen

@MainActor ViewModels hold the state of work in progress: they keep each service reply once and work out what to show from it. Views hold short-lived look-only state. Coordinators handle AppKit windows and panels.

`RuntimeViewModel` is the one place that refreshes the controller list for Settings and the menu bar. Callers that overlap share one refresh that runs after them, with one gateway request at a time. A brief failure keeps the last good list.

Developer snapshot and capture requests share one slot, and a new request replaces the old. Switching controllers, refreshing, stopping capture, and closing the window cancel the old request and wait for it to end. Showing a result needs the current generation and session token. Device reads and writes, parsing, packet comparison, and row formatting stay off @MainActor.

| Area | Code | What it handles |
| --- | --- | --- |
| App lifecycle and status item | `Sources/OpenJoystickDriverPresentation/MenuBar/MenuBarCoordinator.swift` | Only bringing the app forward, the status menu, and quitting |
| Main window | `Sources/OpenJoystickDriverPresentation/MainWindow/` | One reusable window, sidebar areas, toolbar, problem banner, last area and geometry |
| Main menu | `Sources/OpenJoystickDriverPresentation/MainMenu/` | Menu model and its AppKit rendering |
| Settings window | `Sources/OpenJoystickDriverPresentation/SettingsWindow/` | General, Notifications, Advanced panes, toolbar selection |
| Developer diagnostics | `Sources/OpenJoystickDriverPresentation/Settings/Developer/` | One replaceable diagnostic request, controller facts, size-limited capture, packet rows drawn only when on screen |
| Shared settings building blocks | `Sources/OpenJoystickDriverPresentation/Components/{SettingsRows,StateViews}.swift` | Headers, rows, loading, empty, and error states |
| Controller details and identity | `Sources/OpenJoystickDriverPresentation/Controllers/Inventory/ControllersView.swift` | Connected devices, identity selection, loading, failure, retry |
| Profiles and editor | `Sources/OpenJoystickDriverPresentation/Profiles/{List/ProfilesView,Editor/ProfileEditorViews}.swift` | Selection, drafts, assignments, saving and edit clashes, profile actions |
| Mapping capture | `Sources/OpenJoystickDriverPresentation/Profiles/Editor/MappingCaptureViews.swift`, `Sources/OpenJoystickDriverPresentation/InputCapture/KeyboardCaptureViews.swift` | Controller and keyboard capture plus axis adjustment |
| Presentation state | `Sources/OpenJoystickDriverPresentation/Runtime/{RuntimeViewModel,SupportState}.swift` | Loading, permission, input, saved virtual HID profile choice, changes in progress, diagnostics, edit clashes |
| Service adapter | `Sources/OpenJoystickDriverPresentation/Runtime/ApplicationServiceGateway.swift` | `ApplicationServiceClient` calls, and errors with fixed wording for the UI |

Add a file only for one focused job that can be tested on its own.

## What You See

### Menu Bar

`StatusItemModel` holds the menu as data. `MenuBarCoordinator+StatusMenu.swift` draws it.

| Row | Content |
| --- | --- |
| Problem (one per problem needing the user) | `Permission Missing: <name>` opens Access at that permission; a service problem row starts the service (its title text isn't confirmed). MenuBarViewModel reads problems from the status RPC via StatusItemState.problems |
| Controller (one per connected) | Battery level, active profile, paused state. With none: disabled No Controller Connected row |
| Controller submenu | Profile list with a checkmark on the one in use, ending in No Profile (More Profiles after ten, opening Profiles); Pause or Resume; Test Input; Show in Window; for wireless, Disconnect Bluetooth Connection |
| Fixed | Open OpenJoystickDriver, Settings, Quit |

The menu is two levels deep. Activity Log, Explain Error Code, Report Problem, and Project Website are in Help. Logs, reports, packet streams, raw IDs, and audits stay out of the menu.

The icon is a controller symbol, or a warning triangle while a problem row exists. Its accessibility label is the first problem, no controller connected, or ready.

The item sets `behavior = .removalAllowed`, so you can drag it off the menu bar while holding Command. That makes `isVisible` false. `MenuBarCoordinator` then turns Show in menu bar off and Show in Dock on in one write (`SettingsPreferencesModel.menuBarItemRemoved()`) and opens the main window, so the app never disappears. If the write fails, the item comes back.

The store refuses a write that turns both off. A settings file with both off reads as `storedNoVisibleEntryPoint`: the main window opens at launch with an alert offering Reset Settings, Show in Finder, and Quit. `applicationShouldHandleReopen` opens the main window.

### Main Window

If a profile has unsaved edits, switching areas stops and offers Cancel or Discard.

| Area | Shortcut | Content |
| --- | --- | --- |
| Controllers | Command-1 | Connected controllers, selected controller facts, Input Test, Handled by picker, virtual HID profile, Draft Record, Capture Packets |
| Profiles | Command-2 | Profile list, Assignments editor |
| Library | Command-3 | Controller records and mods; Validate, Install, Replace, Remove, Test Record |
| Access | Command-4 | Permissions, local endpoint, programs with access, tokens, refused requests, open connections |
| Activity | Command-5 | Log, diagnostics checks |

Settings has General, Notifications, and Advanced panes. Raw packets, watching, and catalog work are command line only, except Developer Tools in Advanced. Profile rows use standard list and table controls, not a picture with clickable spots.

### Profile Editing

| Topic | Rule |
| --- | --- |
| Capture | Doesn't freeze the window. Cancel or Escape stops it |
| Axis adjustment | Only axis and axis-direction sources |
| Key capture | Standard macOS control. Handles modifier keys and Clear |
| Save | `updateRemappingProfile(_:expectedCurrent:)`; an edit clash keeps the draft and offers Reload or Keep Editing |
| While saving | Controls are turned off. Delete is marked as a destructive button |
| Presentation | One `alert(item:)` for profile alerts; one `sheet(item:)` for capture and adjustment |

## What the Gateway Offers

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

The adapter returns typed replies, turns connection failures into errors with fixed wording, and never shows socket paths, command-line text, or raw RPC descriptions.

## State and Permission Rules

| Topic | Rule |
| --- | --- |
| States | Loading, unavailable, empty, denied, requesting, saving, conflict, and failed each have their own state |
| Late reply | Can't overwrite newer permission, post-event, virtual HID profile, or input state |
| Permission request | Replaced by a newer one: opens no Privacy & Security pane. Denied: opens the pane where you can fix it. Only the follow-up check decides that access was granted |
| Paths | Showing the virtual controller and sending keyboard and pointer events through CoreGraphics ask for permission separately |
| Identity request | A failed one only means "try again". The picker keeps the last confirmed identity |

## Compatibility and Accessibility

| Topic | Rule |
| --- | --- |
| Oldest macOS | macOS 12. Newer APIs sit behind `#available` with an older fallback. Uses AppKit template images and SwiftUI compatibility modifiers |
| Click targets | 28 points is best, 20 points is the smallest allowed |
| Color and type | System colors and text styles. A state is shown with text plus an icon or shape, never color alone |
| VoiceOver | Reads the full value when the text is cut off |
| Keyboard and motion | Everything works from the keyboard, Escape cancels, Reduce Motion is respected, and Full Keyboard Access works |
| Symbols | SF Symbols with AppKit template fallbacks |

## Checks

Run the checks that fit the change:

```bash
just catalog-regenerate --check
just check-profiles
just lint
python3 -m unittest discover -s Tests/RepositoryScripts
just driverkit-check
swift test
```

Package tests cover a fake gateway's state, permission generations, profile drafts, diagnostics, and moving around Settings. Checking the real app needs a signed build on supported macOS versions:

| Check |
| --- |
| Permission (TCC) changes |
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
