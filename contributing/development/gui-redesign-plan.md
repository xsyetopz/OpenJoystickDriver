# GUI Redesign Plan

Status: proposed. Follows the [CLI Redesign Plan](cli-redesign-plan.md) and the [Controller Configuration Plan](controller-config-plan.md). Breaking changes are allowed, with no migration.

## Goal

The app is a graphical layer over the command line, the way Windows 3.11 ran over MS-DOS. Every app action runs an operation that an `ojd` command also runs, and shows the same data. A feature ships in the CLI first. The app may lag behind the CLI, but it never has a feature the CLI lacks.

The app follows Apple's Human Interface Guidelines for macOS first, and is structured so an iPadOS and iOS companion can reuse its model and views. Citations below name the HIG page and heading, such as `settings.md › Best practices`.

## Thesis

A quiet utility. One glance answers two questions: does each controller work, and what do games see? The one distinctive element is a live controller diagram that uses the pad's own button labels and, where the system has them, the GameController SF Symbols, because `game-controls.md › Physical controllers` says to "Prefer using symbols, not text, to refer to game controller elements" and to "Customize onscreen content to match the connected game controller". Everything around the diagram uses standard system components.

## Current state

- The shell is AppKit: an `NSStatusItem` with an `NSMenu`, and `NSWindowController` windows that host SwiftUI through `NSHostingView`.
- One 1040 by 700 window with a `NavigationView` sidebar: Overview, Controllers, Profiles, Console, Developer Tools, and Settings. Settings is a sidebar item, not a Settings window. A second window tests input. Fifteen sheets.
- View models are `ObservableObject` types that call `ApplicationServiceClientGateway` directly, not the operations the CLI runs.
- Accessibility: 8 fixed `.font(.system(size:))` sizes, 41 fixed frames, no handling for Reduce Motion or Differentiate Without Color.
- About 14 `#available` checks for macOS 13, plus older shims: `OJDSystemSymbol`, `NavigationView`, `.alert(isPresented:)`, one sheet per view, and `MenuBarStatusItemImage`.
- iOS blockers: `OpenJoystickDriverKit` imports IOKit, and 61 presentation files import AppKit.
- `docs/using-the-app/` has no Profiles page, and `menu-bar-settings-architecture.md` describes the current design.

## Prior art

| App | What it shows |
| --- | --- |
| Karabiner-Elements | A watched configuration file is the single source of truth. The app and the CLI both edit that file. |
| Tailscale for macOS | One bundle for the app and the CLI, with a Settings action that installs the CLI. |
| Little Snitch | Rules can be exported and restored from the command line, after the user opts in. |
| LuLu | A menu for quick state and a separate rules window for editing. |
| Steam Input | Per-controller layouts with a controller diagram as the main surface. |
| DS4Windows | Per-controller profiles, and profile switching from the tray. |
| macOS Game Controllers settings (macOS 13 and later) | Per-app button remapping for supported controllers. OJD does not duplicate it; the Controllers area links to it for pads macOS serves, on systems that have it. |

## Operating system floor

The floor is macOS 12 and DriverKit 21, the lowest deployment targets of Xcode 27. `Package.swift` and `Scripts/Build/driverkit.sh` set them, and the Intel and Apple silicon slices share them. macOS 12 has the Swift Concurrency runtime, so the app bundles no back-deployment library.

Newer APIs are used behind `@available` and `#available`, under these rules:

- Every gated feature has a fallback on older systems that keeps the same function. It may lose polish, never a feature (`layout.md`: "Keep functionality the same as size classes change" states the same principle for size classes).
- The check sits in the smallest view or helper that needs the API, not around whole screens, so each screen has one implementation.
- A check is for API availability only, never a guess about hardware or OS behavior.
- When the floor rises, the checks and fallbacks below the new floor are removed with the `remove-unneeded-compatibility-code` procedure.

The iPadOS and iOS companion apps start at iPadOS 15 and iOS 15, the lowest deployment targets of Xcode 26 and Xcode 27, and gate newer features the same way.

Liquid Glass on macOS 26 comes from standard AppKit toolbars, sidebars, and menus. Content never gets a custom glass or blur.

## Architecture

- The app shell stays AppKit on every macOS version: the app delegate, the menu bar extra, windows, split views, toolbars, the Settings window, and the main menu. SwiftUI's `Window` and `MenuBarExtra` need macOS 13, and a second, SwiftUI shell for newer systems would duplicate every scene. AppKit can meet every HIG rule below on macOS 12.
- Screen content is SwiftUI in `NSHostingController`, written against the macOS 12 SwiftUI API, with newer modifiers gated. Lists that need `NSTableView` or `NSOutlineView` behavior on macOS 12, such as the sidebar and the log, use AppKit.
- A new platform-neutral target, `OpenJoystickDriverModel`, holds the operation request and result types, the profile and record types, and their localization. The CLI encodes these results as its `--json` output. It imports no IOKit or AppKit.
- An `OJDOperations` protocol lists the operations. On macOS the RPC client implements it; on iPadOS and iOS a local implementation works on files only.
- View models are `ObservableObject` types that call `OJDOperations`, never the RPC gateway. `@Observable` needs macOS 14 and cannot be gated per type without keeping two model types, so it is not used.
- `OpenJoystickDriverKit` stays macOS only.
- Code for one platform sits in files for that platform, not inside `#if` blocks in shared views. `#if os(macOS)` appears only in the app shell.

## Menu bar extra

An `NSStatusItem` that shows an `NSMenu`. `the-menu-bar.md › Menu bar extras`: "Display a menu — not a popover — when people click your menu bar extra."

- A status line: all good, or the first problem with the command that fixes it.
- One submenu per controller: a checkmark list of profiles, the virtual pad identity, and Suspend.
- Open OpenJoystickDriver, Settings… (⌘,), and Quit OpenJoystickDriver.
- Items keep their place and are disabled when they cannot run. `the-menu-bar.md › Best practices`: "Always show the same set of menu items".
- The icon is a template image made from an SF Symbol. `the-menu-bar.md › Menu bar extras`: "Consider using a symbol".
- A setting, Show in Menu Bar, turns the extra off. `the-menu-bar.md › Menu bar extras`: "Let people — not your app — decide whether to put your menu bar extra in the menu bar." Opening the app again always shows the main window, so a hidden extra never locks anyone out ("Avoid relying on the presence of menu bar extras").
- The Dock menu repeats the profile switch while the app has a Dock icon ("Consider exposing app-specific functionality in other ways, too").

## Main window

One `NSWindow` with an `NSSplitViewController`. The app shows a Dock icon and its menus while this window or Settings is open, and returns to a menu-bar-only app when both close, by switching the activation policy.

The sidebar is a source list with four areas and at most two levels (`sidebars.md › Best practices`: "no more than two levels"):

| Area | Content | CLI equivalent |
| --- | --- | --- |
| Controllers | Each connected controller: live diagram, output tests, ownership, virtual pad, and the effective record with its file path. | `ojd controller`, `ojd virtual` |
| Profiles | Profile list and the binding editor. | `ojd profile`, `ojd binding` |
| Records | User records, bundled records, validation results, and drafts from a connected pad. | `ojd record` |
| Activity | Service log and support bundle. | `ojd log`, `ojd diagnose` |

- The sidebar can be hidden and is visible by default (`sidebars.md › Best practices`). The selection stays highlighted (`split-views.md › Best practices`: "persistently highlight the current selection").
- Details that belong to the selection open in a trailing inspector pane, not in a bottom bar. `windows.md › Desktop (macOS)` and `layout.md` both say to keep critical information and actions out of the bottom of a window. On macOS 14 and later the pane is an inspector split item; earlier it is a plain trailing split item with the same content.
- The window resizes freely with minimum pane widths (`windows.md › Best practices`: "adapt fluidly to different sizes"; `split-views.md › Desktop (macOS)`).
- Missing permissions and an inactive extension appear as the Controllers empty state with the step that fixes them, and as a Finish Setup… menu item. They are not settings. `settings.md › Best practices`: "Avoid using settings to ask for setup information you can get in other ways".
- Each action's context menu has Copy Command, which copies the `ojd` command that does the same thing. It teaches the CLI and makes a bug report reproducible.
- Destructive actions (delete profile, remove record) ask for confirmation, like the CLI's prompt, and profile edits support Undo through the window's `UndoManager`.

## Settings

A separate Settings window with General and Advanced panes, opened from the App menu with ⌘,. `settings.md › Desktop (macOS)`: the settings window has a toolbar that people cannot customize, its title names the current pane, and it reopens on the last pane. The toolbar uses the preference style.

- General: Launch at Login, Show in Menu Bar, Check for Updates.
- Advanced: Install Command-Line Tool, log level.
- Each setting is an `ojd setting` key. Nothing about a single controller or profile goes here (`settings.md › Task-specific options`: "prefer letting people modify task-specific options without going to your settings area").
- Appearance follows the system; there is no app appearance setting (`settings.md › Best practices`: "Respect people's systemwide settings").

## Menus

`designing-for-macos.md › Best practices`: "Use the menu bar to give people easy access to all the commands". Every toolbar button and context menu action also has a menu item.

- File: New Profile (⌘N), Import Profile…, Export Profile…, Install Record…
- Edit: standard items, with Undo for profile edits.
- View: Show Sidebar, Show Inspector.
- Controller: Test Rumble, Set Player, Suspend, Resume, Disconnect, Copy Command.
- Window and Help: standard. Help opens the user docs.

## Controller diagram

- Drawn with SwiftUI shapes, with no bitmaps and no SVG files in the repository. Input glyphs are GameController SF Symbols where the running system has the symbol, and the button's label in text otherwise.
- Face buttons use the pad's own labels (A/B/X/Y, Cross/Circle/Square/Triangle, or the Nintendo layout), taken from the record.
- A pressed input changes shape and fill and shows its value. Color is never the only signal (`accessibility.md`: "Convey information with more than color alone").
- Motion follows Reduce Motion: pressed states change instantly, without animation.
- The diagram is not mirrored in right-to-left languages, because it shows physical hardware. The rest of the layout uses leading and trailing edges. This is a judgment call; the HIG has no rule for it.
- Several controllers each get their own diagram (`game-controls.md › Physical controllers`: "Support multiple connected controllers").
- Input comes from the service through `ojd controller watch`'s operation, not from the GameController framework, so the diagram works for pads macOS does not serve.

## Accessibility and layout

- Text uses text styles, not fixed point sizes. macOS has no Dynamic Type (`typography.md`), but the layout must still fit every font size the app supports ("Make sure your app's layout adapts to all font sizes").
- Fixed frames become minimum sizes or flexible layouts.
- Controls stay at the standard sizes: 28 by 28 points on macOS (20 minimum), 44 by 44 on iOS (28 minimum) (`accessibility.md`).
- Colors are semantic system colors. OJD's brand color appears only in content, such as the diagram's accent. One color has one meaning (`color.md`: "Avoid using the same color to mean different things"). Every color works in light, dark, and increased contrast.
- Lighting colors are picked with the system color panel (`color.md`: "prefer system-provided color controls").
- Every icon-only control has an accessibility label. VoiceOver reads the diagram as a list of inputs and their values.
- Keyboard access covers every action, including binding capture.

## iPadOS and iOS

Not part of beta.5. macOS is the only platform where OJD is a driver. iPadOS and iOS get companion apps, starting at iPadOS 15 and iOS 15. The design keeps these targets possible without changing the macOS app later.

- Navigation is a tab bar with the four areas as tabs (`sidebars.md › Mobile (iOS, iPadOS)`: "Consider using a tab bar first"; `tab-bars.md`: tabs navigate, never act, and use single words). Where the `sidebarAdaptable` tab view style exists (iPadOS 18), regular width shows a sidebar instead; earlier systems keep the tab bar at every width, with the same functions.
- Layout follows size classes, never device type or orientation (`layout.md`: "Determine layout based on size classes, not device type or orientation"; "Keep functionality the same as size classes change"). The app works in portrait, landscape, Split View, Stage Manager where available, and every window width (`split-views.md › Tablet (iPadOS)`: "Account for narrow, compact, and intermediate window widths").
- Scope is a companion app: an input tester through the GameController framework, a profile and record editor for the same JSON files through Files and iCloud Drive, and a record validator.
- Neither companion runs a driver:
  - **iPhone:** no DriverKit on iPhone was found in Apple's documentation.
  - **iPadOS:** [DriverKit on iPad](https://developer.apple.com/videos/play/wwdc2022/110373/) exists from iPadOS 16, on M1 or later iPads, for USB, PCI, and Audio only. OJD's USBDriverKit extension could read a pad there, but OJD could not present it to other apps:
    - The iOS 27 SDK has neither `IOUSBHost` nor `IOHIDUserDevice`, which the macOS app uses for raw USB and virtual gamepads.
    - Apple documents HIDDriverKit and `IOUserHIDDevice` for macOS only.
  - Driver work on iPad starts only if Apple documents a way for an extension to publish a HID device there.

## Compatibility code to classify

Each candidate is classified in its slice with the `remove-unneeded-compatibility-code` procedure against the macOS 12 floor.

| Candidate | Expected class |
| --- | --- |
| `#available` checks for macOS 13 | required when they gate an API newer than macOS 12 and have a fallback with the same function; never required when the gated API exists on macOS 12 |
| `OJDSystemSymbol` | required while a symbol it shows is newer than macOS 12: it falls back to another symbol or text |
| `MenuBarStatusItemImage` | folded into the menu bar extra unless it does more than wrap an SF Symbol |
| `NSStatusItem`, `NSMenu`, `NSWindowController`, `NSHostingView` | required: they are the shell on every version |
| `NavigationView` | retired by `NSSplitViewController` |
| `.alert(isPresented:)` | never required: the newer alert API exists on macOS 12 |
| One-sheet-per-view workaround | unresolved: find the macOS 12 behavior it works around before keeping or removing it |
| `ObservableObject` and `@Published` | required |
| Settings as a sidebar item | never required |

## Slices

Each slice is one change with its tests, docs, and checks. Slices after slice 2 start only when their CLI commands exist.

1. **Model target.** Create `OpenJoystickDriverModel` and `OJDOperations`, and move view models onto them. Classify the existing `#available` checks.
1. **App shell.** The AppKit shell: menu bar extra, main window with split view and inspector pane, Settings window, menus, and the Dock icon switch. Delete the `NavigationView` sidebar and the Settings sidebar item.
1. **Controllers.** The area, the diagram, the inspector, output tests, and the setup empty state.
1. **Profiles.** The area and the binding editor with Undo.
1. **Records.** The area, validation, install and remove, drafts, Reveal in Finder, and Open in the user's editor.
1. **Activity.** The log view and the support bundle.
1. **Accessibility and localization pass.** Largest text size, VoiceOver, keyboard-only use, Reduce Motion, increased contrast, and every supported language.
1. **iPadOS and iOS companion.** A later release.

## Checks

- Each slice runs the repository checks in `CLAUDE.md`.
- View model tests use a fake `OJDOperations` and assert the same results the CLI tests assert.
- Each area is checked on macOS 12 and on the current macOS release.
- Each area is checked in light, dark, and increased contrast, at the smallest and largest window size, with VoiceOver, and with the keyboard only. Screenshots go into the pull request.
- The user docs in `docs/using-the-app/` are rewritten per slice, with a new Profiles page and a Records page. `menu-bar-settings-architecture.md` is replaced by this design.

## Open questions

- Whether the Records area gets a structured record editor later. This plan answers the Controller Configuration Plan's question with the minimum: the app shows the effective record and its path, validates and installs files, and opens them in the user's editor, the same as `ojd record` and `ojd profile edit`.
