## Why

OpenJoystickDriver 0.5.x knows its controllers partly in data and partly in Swift: 25 `ControllerQuirk` tags, VID:PID literals in Swift and Python, family defaults in code, and one `DeviceIdentifier` type that stands for six different things (1012 references in 248 files).
The user's rule is that people must not have to edit source code to add a controller, and that names say what they mean.
A single breaking release, `0.6.0-alpha.1`, is the place to fix this: no legacy readers, aliases or upgraders are kept.
Live evidence from 2026-10-14 (macOS 27, SDL 3.4.18) also shows that the current default virtual identity `045E:02FD` is invisible to SDL, while OJD's own `1209:4A4F` identity works once SDL has a mapping.

## What Changes

- **BREAKING** Controller knowledge becomes data. A `Controller` record lists `modes[]` with match keys (interface signature, strings, read-only behavioral probes), declarative bit-level input layouts, init and keepalive sequences, output templates and vendor control transfers. `ControllerQuirk`, family tables in Swift and Python, and VID:PID literals in code are removed. Code keeps only algorithmic protocols (GIP authentication, Switch subcommands, Sony CRC, Steam, descriptor interpreters).
- **BREAKING** Same-ID clones are told apart by records through read-only probes (the DS3 clone case).
- **BREAKING** One serving-route decision (`NativePassThrough`, `VirtualHID`, `ExtensionOwned`, `OutputDisabled`) is made by one pure policy.
- **BREAKING** Two virtual personas: `SDLCompatible` (`045E:0B0C`, automatic when the controller's primary controls fit it) and `Generic` (`1209:4A4F`, otherwise or by choice). OJD publishes an SDL mapping for `1209:4A4F`. No Microsoft ID appears outside the `SDLCompatible` persona.
- **BREAKING** Identity types are renamed: `ControllerModelID`, `ControllerHardwareIdentity`, `ControllerConnectionAddress`, `LogicalControllerID`, `ControllerSessionToken`, `ControllerPortKey`, `ControllerReference`. No aliases.
- **BREAKING** One control vocabulary (position-based, UpperCamelCase values) replaces `ControlID` and `RemappingButton`, with a crosswalk to W3C Gamepad, SDL3, Linux evdev, HID usages and Apple GameController.
- **BREAKING** Every OJD document carries `apiVersion: openjoystickdriver/v1alpha2` and `kind`. Schemas are flat files in `Resources/Schemas/`, published with `$id` on GitHub Pages. Unknown versions are rejected; there is no upgrader.
- **BREAKING** The CLI vocabulary is OS-neutral (`system|ojd`, `input-read`, `transport-extension`, `publisher.kind`); macOS terms live under `platform`. The CLI follows clig.dev.
- **BREAKING** The GUI is rebuilt as an AppKit shell (window with a sidebar for the five areas Controllers, Profiles, Library, Access and Activity and a toolbar for the area title and actions, a problem banner shown only while something is wrong, and Input Test inside the Controllers detail; Settings window with pane buttons), following Apple HIG. Every CLI capability is reachable in the GUI; the menu bar is a subset of the GUI.
- **BREAKING** Localization keys are re-keyed into namespaces, with positional specifiers, translator comments and a `crowdin.yml`.
- New: a public SDK endpoint with a reference client, an `InputSource`/`OutputSink` streaming boundary, a WebRTC bridge program that is an endpoint client, and consumer support for SDL, Wine/CrossOver and browsers.
- New: wiki, docs, release checks, and a hardware-check list for the maintainer.

Out of scope: submitting the mapping to SDL_GameControllerDB or SDL upstream; enabling GitHub Pages; asking Apple for more `transport.usb` IDs; push, tag, notarize and publish. Each is the user's decision.

## Capabilities

### New Capabilities

- `controller-records`: the `Controller` and `ControllerPatch` documents and their data model.
- `protocol-descriptions`: protocols as data, typed parameters, and the code/data boundary.
- `device-matching`: observed device to link to record mode, including same-ID clone probes and DEXT match generation.
- `serving-routes`: the single serving-route policy.
- `virtual-personas`: the `Generic` and `SDLCompatible` personas and the `VirtualDevice` document.
- `sdl-consumer-support`: SDL mapping publication, Wine/CrossOver and browser behavior per persona.
- `control-vocabulary`: canonical control ids and the crosswalk.
- `schema-versioning`: `apiVersion`/`kind`, hosting, loader behavior, value formats.
- `identity-naming`: identity type names and the removal of aliases.
- `cli-surface`: neutral vocabulary and command tree.
- `gui-shell`: main window, Settings window, areas, accessibility.
- `menu-bar`: main menu and status item.
- `localization-keys`: key namespaces, specifiers, comments, Crowdin.
- `sdk-endpoint`: public endpoint and reference client.
- `input-streaming`: streaming boundary and the WebRTC bridge.

### Modified Capabilities

- `mod-localization`, `mod-packages`, `mod-sdk`, `release-readiness`, `usb-device-detection`, `virtual-input-delivery`, `virtual-ownership`: requirements change to match the localization keys, document headers, schema paths, serving words and check list of this change. `driverkit-signing` is unchanged.

## Impact

- `Sources/OpenJoystickDriverKit` (protocol catalog, USB, output profiles, identity types, endpoint payloads), `Sources/OpenJoystickDriver` (CLI), `Sources/OpenJoystickDriverService`, the app target, DriverKit sources.
- `Resources/Schemas/`, `Resources/ControllerPatches/`, `Scripts/Catalog/`, `Scripts/Quality/`, `crowdin.yml`, 22 localization bundles, `wiki/`, `docs/`.
- 696 generated controller records are regenerated; user files from 0.5.x are not read.
- Release checks listed in the repository `CLAUDE.md` all run on the final tree.
