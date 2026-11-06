## Context

See `proposal.md` for the reason. This change is planning only: it holds specs and tasks, no code.
Evidence comes from six read-only audits of `feat/0.6.0-alpha.1` (CLI coverage, architecture, issues and resources, GUI and localization, schemas, localization review) and from a live run on 2026-10-14 (macOS 27, arm64, app 0.5.0-beta.5, SDL 3.4.18 through `Tools/SDLGamepadProbe`).
File and line references below are from that branch and move as work lands.

Floor: macOS 12. Test hosts: this Mac (macOS 27) and an Intel MacBook Pro A1398 on macOS 12. There is no macOS simulator, and a macOS VM has no Bluetooth or USB-HID passthrough.

### User decisions (authoritative, 2026-10-14)

| # | Decision (user's words in quotes) |
| --- | --- |
| 1 | "`1209:4A4F` is for Generic HID, and `045E:02FD` is for SDL-based solutions." |
| 2 | "the version token was taken from Kubernetes, so they are a big inspiration for schema versioning." "no domain sadly, unless you want to host it on github here--biome.js-style?" |
| 3 | "should use idiomatic, self-descriptive names for any construct, parameter, and code-related item. No aliases retaining. It is a breaking change." |
| 4 | `U-` and `E-` prefixes: "if you need to." |
| 5 | Clones that reuse an ID: "if you need to. you never know if it's a hit-or-miss unless somebody with a clone tests it out. user has the other clone mentioned in wiki." |
| 6 | Keep `.strings` and `.stringsdict`; "yes, agreed!" to the namespaces `term.*`, `action.*`, `status.*`, `ui.<area>.*`, `ui.menu.*`, `ui.extra.*`, `ui.settings.<pane>.*`, `a11y.*`, `cli.<group>.<command>.*`, `error.<code>.*`, `notify.*`, `platform.<os>.*`; plus `crowdin.yml`. |
| 7 | "we'll just redo the GUI entirely. it's a mess." The toolbar pane buttons of commit `6858be2e` "were awesome!" "CLI <= menubar => GUI". |
| 8 | Control vocabulary: "AGREED!" |
| 9 | "our CLI uses <https://clig.dev/> guidelines + Apple." |
| 10 | "OJD should not be hard-coding/make workarounds that are baked in... users don't have to start modifying source code." |
| 11 | The seven Microsoft IDs in the DEXT are Apple's `transport.usb` grant (`docs/development/signing.md:36`). |
| 12 | DS3 Bluetooth pairing: macOS 27 asks a PIN the DS3 lacks; older macOS pairs. Test host is the A1398 on macOS 12. |
| 13 | Stored files from earlier versions, such as profiles with old control names: "must be forward-thinking. no migrations. full drop and breaking changes all across." (2026-10-15) |
| 13 | Hardware available: Razer Wolverine V1 TE (GIP), GameSir G7 SE (GIP, 3537:1010), genuine Sony CECHZC2E DS3, a DS3 clone, genuine Sony DS4 v2, on two USB hubs; SDL3 apps such as Steam. The caller also lists an 8BitDo `2DC8:301B`. |
| 14 | One massive breaking release `0.6.0-alpha.1`; no legacy; streaming (WebRTC as a separate endpoint client), SDK/API, user configs, SDL/Wine/CrossOver/browser support in scope. |
| 15 | Main window navigation: "real Apple apps comparison (maybe our toolbar-based solution is wrong, and needs a native Apple sidebar+toolbar hybrid?" (Finder, Notes, Photos, Books, Journal on macOS 27); chose "Sidebar + toolbar". |
| 16 | Native look at every window size: "couldn't we design them better in a way where a minimum-size window and normal-size window don't cause these weird consolidations that could over/underflow/get cut off, or where we have so much empty space (and design smells of the older GUI)? Ideally, we want to make sure we use native macOS components, not custom, or overstyled defaults (overrides). Just normal apple-native look-and-feel". Minimum macOS: "12, nicer on 13+. use the `if #available` or `@available`". |

## Goals / Non-Goals

Goals:

- A new controller or clone can be supported by adding a JSON document, without a Swift change, when its protocol is one of the algorithmic ones or is fully expressible as data.
- One name per concept in code, documents, CLI, GUI and localization.
- SDL, Wine/CrossOver and browsers see a usable gamepad from the default persona.

Non-Goals:

- No runtime upgrader, `ojd migrate`, alias, fallback decoder, compatibility shim, table of earlier names or hint that names a replacement for an earlier word (decisions 2, 3, 13).
- No DriverKit extension for a second virtual backend; `IOHIDUserDevice` stays the only virtual backend (carried over from `release-0-6-0-alpha-1`).
- No parser for controllers that need a new algorithmic protocol; those stay code (GIP authentication, Switch subcommands, Sony CRC, Steam, descriptor interpreters).
- No copying of GPL or other-licensed sources; protocol facts only.

## Decisions

### D1 Target architecture

Layers, each with one owner type. A device is observed, linked, bound to a record mode, driven by a protocol, reduced to canonical state, mapped by the user's profile, and served by one route.

| Layer | Content | Today's problem |
| --- | --- | --- |
| L0 Observation | Raw OS facts: IOHID properties, USB descriptors, BLE advertisement | Observed facts are mixed with identity |
| L1 Link | `kind` (`USB`, `BluetoothClassic`, `BluetoothLE`, `ProprietaryRadioReceiver`), `access` (`HID`, `RawUSB`, `USBExtension`, `GATT`), address | Switch 2 invents locations `0xB1E0_0000` |
| L2 Binding | Model record, `modes[]` chosen by link kind and interface signature, and extra match keys; roles | `DeviceIdentifier` carries VID:PID and location |
| L3 Protocol | A protocol description (data) plus driver code with typed parameters | 25 `ControllerQuirk` tags in `Sources/OpenJoystickDriverKit/Protocol/Catalog/TransportProfiles.swift:99-183` |
| L4 Canonical state | Controls from the vocabulary, motion, touch, battery | Two vocabularies (`ControlID`, `RemappingButton`) |
| L5 Mapping | User profile over canonical state | none |
| L6 Serving | One `ServingRoute` per controller from a pure policy | Decided in several places |

Platform boundary: `OpenJoystickDriverKit` imports only Foundation, Dispatch, Darwin and CryptoKit. It declares the ports a host implements (`PlatformHost`, `AccessControlSystem`, `ApplicationServiceRegistration`, `HIDAccessBackend`, `VirtualHIDDevicePublisher`, `Switch2BluetoothLEWriter`), and `OpenJoystickDriverMacOSPlatform` implements the IOKit, Security, ServiceManagement and `IOHIDUserDevice` ones. The composition roots pass the implementations in. `Scripts/Quality/check_neutral_core_imports.py` fails on any other import in Kit, the CLI or the executable outside `platform`. Neutral means free of macOS device, security and application frameworks (IOKit, GameController, CoreBluetooth, Security, AppKit, ServiceManagement, SystemExtensions); the spec asks for no macOS-only code in the core, not for a build off Apple platforms. Darwin (POSIX calls) and CryptoKit (hashing) ship on every Apple platform the package declares, so the core builds on Apple platforms only. The check runs in `just check-fast`, CI and the release workflow.

Record flow: observed device, then link, then record `modes[]` with match keys (interface signature, manufacturer and product strings, read-only behavioral probes for same-ID clones), then a protocol description, then canonical state, then user mapping, then one serving-route policy, then a persona. Personas are `Generic` `1209:4A4F` (default) and `SDLCompatible` `045E:02FD`, with an OJD-published SDL mapping.

### D2 Record and schema model

A `Controller` record (see `specs/controller-records`) declares:

- `model` (`id`, `name`, `manufacturer`) and `modes[]`. Each mode has `match` keys, `protocol` (an id plus typed `parameters`), `interface` selection (for example the HID interface range 2 to 5 of the Steam Deck as data), and optional `session` steps.
- Declarative input layouts: bit offset and size, signed fields, 10 to 16 bit values, 16-bit triggers, inversion, more than four axes, extra buttons, report ids, trigger rest value -1, hat sources (8-way, directions, and `table` hats mapping a masked value to a direction), `symmetric` axes (signed, divided by the maximum). A layout is carried by `HIDReportLayout` records and by the `XboxXID`, `NintendoSwitchInputOnly` and `VendorFlydigi` protocol descriptions (`defaults.input`); a report may require its exact length (`length: {exactly: N}`).
- Vendor control transfers (`bmRequestType`, `bRequest`, `wValue`, `wIndex`, `wLength`), init, keepalive and settle sequences, acknowledgement rules. These come from issues #38 (ShanWan), #22, #21, #35.
- Output templates: fixed bytes, scale, motor positions, resend interval (the xpad and `HIDReportLayout` rumble cases).
- Multi-identity linking: one model reachable through several VID:PID pairs and several link kinds (wired, dongle, Bluetooth, and a mode switch changing the PID, as the 8BitDo family does).

Declared full, not as deltas. The record carries facts only (no provenance, per `Resources/Schemas/AGENTS.md`).

What stays in code, because it is an algorithm and not a table: GIP authentication, Switch subcommands, Sony CRC, Steam protocol, the `HIDDescriptor` and `HIDReportLayout` interpreters, the USB claim and transfer machinery.

Quirk to typed-parameter conversions (examples; the full table is task 5):

| Old `ControllerQuirk` | New |
| --- | --- |
| `switch-2` | protocol `NintendoSwitch2`, parameter `layout`: `pro`, `joyConLeft`, `joyConRight`, `gameCube` |
| input-only | protocol `NintendoSwitchInputOnly` |
| triton, neptune | protocols `ValveSteamTriton`, `ValveSteamDeck`; interface range is data |
| GameSir `g7ProUSB` | wire-dialect parameter |
| `shield-2015` | `reportRevision` parameter |
| wireless-adapter, strikepad | role and motion-scale parameters |
| `wr007`, `scuf-envision`, `z-rz-brake-left`, `dragonrise` | `input.hidUsageMap` data |
| share-offset | `shareButton: { fromEnd: N }` |
| dpad-pressure | `hatSource` |

Family defaults that lived in Swift (in `MacOSOwnedOutput.swift`, `DeviceCatalog.swift`, `ProtocolClassifier.swift`, `ControllerProfileCapabilities.swift` and `ControllerTuning+Layers.swift`: output behavior, endpoints, controls, timings and tuning) move to `Resources/Protocols/<family>.json`. Python tables (`SDL_IDENTITY_FAMILIES`, `SDL_EXCLUSIONS`, `STEAM_VARIANTS`, `SWITCH_2_IDENTITIES`, `DRIVER_HANDLED_DEVICE_FLAGS` in `Scripts/Catalog/generate_controller_catalog.py` and `generate_xpad_records.py`) become authored data. Remaining VID:PID literals to remove: `USB/Configuration.swift:9-12,18-27`, `VirtualDeviceProfile.swift:36-61`, `Switch2BluetoothLEHub.swift:15-41,49-50`, `PassiveUSBDescriptorProbe.swift:6-8`, `RecordReport.swift:87`.

An equivalence harness builds the driver for every bundled record before and after the change and compares driver type and configuration. It gates the generator and quirk work.

Counts to preserve (families): XboxGIP 210, XboxXUSB 208, VendorPS3ThirdParty 75, SonyDualShock4 62, XboxXID 59, NintendoSwitch1 32, VendorGameSir 26, HIDDescriptor 21, SonyDualSense 21, ValveSteamController 12, nvidia-shield 4, HIDReportLayout 4, flydigi 2, sixaxis 2; 696 generated records plus 54 overrides.

### D3 Control vocabulary and crosswalk

One position-based set. A label never renames an id. Values are UpperCamelCase (decision 2); the schema `$defs/control` is the only definition, and one Swift enum mirrors it.

| OJD id | W3C index | SDL3 | Linux evdev | HID page:usage | Apple GameController |
| --- | --- | --- | --- | --- | --- |
| `South`, `East`, `West`, `North` | 0, 1, 2, 3 | SOUTH (`a`), EAST (`b`), WEST (`x`), NORTH (`y`) | BTN_SOUTH, BTN_EAST, BTN_WEST, BTN_NORTH | Button:1 to 4 | ButtonA, ButtonB, ButtonX, ButtonY |
| `LeftShoulder`, `RightShoulder` | 4, 5 | LEFT_SHOULDER, RIGHT_SHOULDER | BTN_TL, BTN_TR | Button:n | LeftShoulder, RightShoulder |
| `LeftTrigger`, `RightTrigger` (axis 0 to 1) | 6, 7 | LEFT_TRIGGER, RIGHT_TRIGGER | ABS_Z, ABS_RZ | GenericDesktop Z, Rz or Simulation Accelerator, Brake | LeftTrigger, RightTrigger |
| `Back` | 8 | BACK | BTN_SELECT | Button:n | ButtonOptions |
| `Start` | 9 | START | BTN_START | GenericDesktop Start (0x3D) | ButtonMenu |
| `LeftStickClick`, `RightStickClick` | 10, 11 | LEFT_STICK, RIGHT_STICK | BTN_THUMBL, BTN_THUMBR | Button:n | LeftThumbstickButton, RightThumbstickButton |
| `DpadUp`, `DpadDown`, `DpadLeft`, `DpadRight` | 12 to 15 | DPAD_* | BTN_DPAD_* or ABS_HAT0 | GenericDesktop Hat switch | DirectionPad |
| `Guide` | 16 | GUIDE | BTN_MODE | GenericDesktop System Main Menu | ButtonHome |
| `Capture` | none | MISC1 | KEY_RECORD | Consumer page | ButtonShare |
| `Microphone` | none | MISC1 (PS5) | none | Telephony or Consumer mute | none |
| `TouchpadClick` | none | TOUCHPAD | BTN_TOUCH (touch device) | Button:n | TouchpadButton |
| `LeftPaddle1`, `LeftPaddle2`, `RightPaddle1`, `RightPaddle2` | none | LEFT/RIGHT_PADDLE1/2 | BTN_GRIPL, BTN_GRIPL2, BTN_GRIPR, BTN_GRIPR2 | Button:n | XboxPaddleOne to Four |
| `LeftStickTouch`, `RightStickTouch`, `LeftTrackpadClick`, `RightTrackpadClick`, `LeftTrackpadTouch`, `RightTrackpadTouch` | none | none | none | Button:n | none |
| `Auxiliary1` to `Auxiliary8` | none | MISC2 to MISC6 | BTN_TRIGGER_HAPPY1+ | Button:n | none |
| `LeftStickX`, `LeftStickY`, `RightStickX`, `RightStickY` | axes 0 to 3 | LEFTX, LEFTY, RIGHTX, RIGHTY | ABS_X, ABS_Y, ABS_RX, ABS_RY | GenericDesktop X, Y, Rx, Ry | LeftThumbstick, RightThumbstick |

Rules: `Share` and `Options` are not ids. PS4 Share and Xbox View are `Back`; PS Options, Xbox Menu and Switch Plus are `Start`; Xbox Share and Switch Capture are `Capture`. Y axes are positive down (W3C, SDL, Linux agree). Grips are `LeftPaddle2`/`RightPaddle2` and back paddles `LeftPaddle1`/`RightPaddle1`; Joy-Con SL and SR and Steam function buttons are `Auxiliary1` to `Auxiliary6`. A trigger without an analog axis is still `LeftTrigger`/`RightTrigger`, marked by the record capability `digitalTriggers`. The crosswalk data is `Resources/Vocabulary/crosswalk.json`, documentation read by tests, not a schema alias. Labels and glyphs come from a per-model `labels` map. Exact HID usage ids are confirmed against the HID Usage Tables at implementation (the audit did not fetch them). Rumble actuators: `LowFrequency`, `HighFrequency`, `LeftTrigger`, `RightTrigger`, `LeftHaptic`, `RightHaptic`. Keyboard keys use W3C UI Events `KeyboardEvent.code` values.

### D4 Schema set and versioning

Kinds: `Controller`, `ControllerPatch` (RFC 7396 JSON Merge Patch), `Profile`, `VirtualDevice`, `ModPackage`, `ErrorCatalog`, `AccessGrants`, `SupportDiagnostic` (CloudEvents envelope), plus the CLI output and endpoint message kinds, and a `Settings` kind for the new settings file. Shared definitions live in `vocabulary.schema.json`. The old `controller-override` `add` becomes a plain `Controller`; `defaults` becomes a `ControllerPatch` with `selector.all`; `persona` becomes `VirtualDevice`.

Assumed (veto-able) and recorded here:

| Assumption | Reason |
| --- | --- |
| `apiVersion: openjoystickdriver/v1alpha2` (Kubernetes `group/version` grammar, group is the project name) | No domain is owned. Kubernetes alpha means "may break without notice", which matches `0.6.0-alpha.1`. Promote to `v1beta1` when frozen. |
| `$id: https://xsyetopz.github.io/OpenJoystickDriver/schemas/v1alpha2/<kind>.schema.json`, published from flat sources `Resources/Schemas/<kind>.schema.json`, version written in each file, no version folder | Decision 2 (biome.js style). The task prepares the Pages publish; the user turns Pages on. |
| Fields lowerCamelCase, enum values UpperCamelCase, CLI argument values lowercase kebab-case mapped 1:1 (for example `ojd virtual set generic`) | Kubernetes API conventions plus clig.dev. |
| Acronyms stay upper case inside UpperCamelCase values: `XboxGIP`, `HIDDescriptor`, `BluetoothLE`, `USB`, `SDL`, `OJD`, `SDLCompatible`, `VirtualHID`, `ExtensionOwnedUSB`, `SystemHIDVisible`, `RawUSB`, `USBExtension`, `GATT` | One spelling in documents and Swift cases. The CLI mapping splits acronym runs, so no per-type table exists. |
| One kebab function maps a value to its CLI argument: a run of capitals and digits is one acronym, and a word starts at a capital that follows a lowercase letter or is followed by one (`HIDDescriptor` is `hid-descriptor`, `XboxGIP` is `xbox-gip`, `OJDGenericGamepad` is `ojd-generic-gamepad`, `VendorPS3ThirdParty` is `vendor-ps3-third-party`, `W3C` is `w3c`; a digit stays with the word before it). A CLI argument selects the case whose kebab form equals it over `allCases`. The mapping is one-to-one within each type: no two values of one enum share a kebab form, which `CommandLineName.collisions(in:)` reports, and the Swift tests assert none for the enum types that take CLI arguments. The Swift tests of `CommandLineName` read one sample table (`Tests/CommandLineNames/samples.json`) and check that the mapping is injective and round-trips. | "Mapped 1:1" holds by construction, with no hand tables to drift. |
| Protocol description files are named by the kebab form of the family value (`xbox-gip.json` for `XboxGIP`) | The file name and the family value stay one mapping. |
| Each driver states in code the parameter names and family-specific session fields it reads (`readParameters`, `sessionFields`); a description declares exactly those | Swift refuses a description that declares or sets anything else, or lacks a session field, when it loads, and a Swift test pins every bundled description to the code. Python does not compare descriptions: Swift is the only validator, so the bundled files are protected by the Swift load check and that test, and Python checks documents only against the JSON Schema. |
| Names that are not enum values keep their own grammar: controller mode ids (`default`, an RFC 1123 label pattern), `apiVersion`, the CloudEvents attributes of the support report, and the HID usage page names and `$comment` in the crosswalk schema | External formats and names. `Tests/RepositoryScripts/test_schema_naming.py` lists each by schema and JSON pointer with its reason. |
| Values that name a field (tuning keys, protocol parameters, record sections, dotted setting paths such as `notify.controllerConnected`) stay lowerCamelCase and must be a property name of the schema they point at; `launchAtLogin` has an explicit entry because the login-item state is not a settings property | The value is a field, so the field rule applies. The same test checks each such list against its source. |
| `Tests/RepositoryScripts/test_schema_naming.py` walks every `Resources/Schemas/*.schema.json` and fails on an enum value, string constant or enum default that is not UpperCamelCase, and on a property or `required` entry that is not lowerCamelCase. Values that still break the rule sit in `schema_naming_pending.json`, which only shrinks and is empty when the rule holds everywhere | The rule is enforced by a test, not by review. |
| `publisher.kind` values `Signed` and `Platform` are hashed into the short access ID, so the spelling fixes every displayed short access ID; `CHANGELOG.md` records the change | The hashed spelling is the document spelling. |
| Raw bytes are uppercase hex pairs with single spaces, pattern `^[0-9A-F]{2}( [0-9A-F]{2})*$` | Kubernetes uses base64; these bytes are read against USB traces. |
| An unknown or missing `apiVersion` is rejected with a new error code | No runtime upgrade (decision 2). |
| Stored files are not migrated; `U-` and `E-` prefixes may change | Decision 4. |

The 0.5.0-beta.4 audit shows `v1beta1` never shipped, so rewriting the layout breaks only unreleased files. Instances drop `$schema`. The version is one Swift constant, `OpenJoystickDriverAPI.version`, which Python reads through `OJDRepositoryTool facts`, and a test asserts it equals every schema's `apiVersion` const. `Scripts/Quality/validate_schemas.py` extends to `docs/sdk/sample/**`, profile fixtures and access-grant fixtures.

### D5 Serving routes and personas

`ServingRoute` is `NativePassThrough(allowance)`, `VirtualHID(persona)`, `ExtensionOwned`, or `OutputDisabled`, decided once by a pure `ServingPolicy` from record, link, user setting and the controller's allowance (`PhysicalControllerOutputCapabilities`). There is no per-app input: a virtual HID device is a system-wide `IOHIDUserDevice`, and macOS gives the service no way to know which app reads it. Automatic selection in `VirtualHIDProfileSelector` picks `SDLCompatible` (`045E:0B0C`) when the controller's primary controls fit it and `Generic` otherwise.

Decided from hardware evidence (maintainer, 2026-10-22, macOS 27): automatic selection publishes `SDLCompatible` when the controller's primary controls fit it, else `Generic`; `Generic` is the persona a user chooses, per model or per controller. PCSX2 2.8.2 (bundled SDL 3.4.12) and DuckStation (bundled SDL 3.4.16) map every control of `SDLCompatible` as an Xbox pad (A/B/X/Y, LB/RB, View/Menu, sticks, triggers, D-pad, Xbox, both motors) and report "No generic bindings were generated for device 'SDL-0'" for `Generic`. That evidence used `045E:02FD`. Apple's `AppleGameControllerPersonality.kext` lists `045E:02FD` with `GCIOMatchVirtual` true, so GameController took the virtual device as an Xbox pad and read nothing from its GIP reports: Safari listed it as P1 with no input (maintainer, 2026-10-23). `SDLCompatible` therefore publishes `045E:0B0C`, the Xbox Adaptive Controller over Bluetooth. SDL 3.4.16 lists it in `SDL_IsJoystickBluetoothXboxOne` (`SDL_joystick.c:3166-3181`), so its HIDAPI Xbox One driver takes it on macOS (`SDL_hidapi_xboxone.c:370-379`), and no code path of that driver tells it from `02FD` (`:155-183`, `:274-287`); SDL names it "Xbox Adaptive Controller" (`controller_list.h:347`). The kext lists `0B0C` without `GCIOMatchVirtual`; on macOS 27 the virtual device gets `AppleUserHIDEventDriver` and GameController lists no controller for it (`GameControllerPersonalityMatchTests`). Declaring a Bluetooth report 1 next to the GIP reports is rejected: SDL's USB path reads its first bytes as a GIP header (`:1663-1679`, `:1909-1932`), so the rest of the report can parse as a `0x20` input packet. A run of SDL 3.4.18 did not list the persona with default hints, nor with `SDL_JOYSTICK_HIDAPI_XBOX(_ONE)=1`, `SDL_JOYSTICK_MFI=1` or `--gc-prewarm`; it appeared only with `SDL_JOYSTICK_HIDAPI=0`. The apps above are the evidence for the default; that run is not reproduced by them. Steam is untested with this persona (the wiki's Steam failure used `045E:02FD` on macOS 26.7.1; tasks 24.65 and H8).

`GameControllerCompatible` (`045E:0B13`, layout `XboxSeriesBluetooth`) is the persona for apps that read Apple's GameController framework, including Safari and Chrome. Decided from hardware evidence (maintainer, 2026-10-23, macOS 27): GameController binds `SDLCompatible` and reads no input from its GIP reports, although the descriptor names each field with standard usages. Apple's personality kext lists `0B12` without `GCIOMatchVirtual`, and a virtual `0B12` never connects. It lists `0B13` with `GCIOMatchVirtual` true, and Blink read every control of the Xbox Series Bluetooth report on `0B13`. Report 1 uses the real controller's bit positions, which SDL's HIDAPI Xbox One Bluetooth driver and Firefox's `XboxSeriesXRemapper` read. GameController reads Home only from System Main Menu on report 2, so the persona also sends Guide there; it names every control, Share included, and delivers Home only to the frontmost app (24.71). SDL reads any Xbox identity on a `Virtual` transport as GIP, so no single report serves both, and Automatic never picks this persona.

No Microsoft ID appears outside the two Xbox personas: `1209:0001` (SDK sample), `4F4A:4449` (retired) and the 045E values in the HIDTool subcommands are reconciled (the sample uses `1209:0001`, the pid.codes test ID; retired ID removed; HIDTool takes IDs from records).

### D6 SDL, Wine/CrossOver and browsers

| Consumer | `Generic` `1209:4A4F` | `SDLCompatible` `045E:0B0C` | `GameControllerCompatible` `045E:0B13` |
| --- | --- | --- | --- |
| SDL3 app (games, emulators) | Enumerated; gamepad only with OJD's mapping (CRC-less GUID `03000000091200004f4a000008040000`). Supplied by environment variable for apps OJD launches and by a mapping file the CLI prints or exports. PCSX2 2.8.2 (SDL 3.4.12) and DuckStation (SDL 3.4.16) report "No generic bindings were generated for device 'SDL-0'" without it. | Mapped as an Xbox pad with default hints by PCSX2 2.8.2 (SDL 3.4.12), DuckStation (SDL 3.4.16) and Steam, all on `045E:02FD`; SDL reads `0B0C` with the same driver code (H14). | Misread: SDL parses its reports as GIP packets. |
| GameController framework | Seen as a generic HID gamepad. | Not bound: the kext lists `045E:0B0C` without `GCIOMatchVirtual`, and the probe lists no controller for it. On `045E:02FD` it was bound with no input (`live_input=false`). | Names every control once, Share included (`ojd virtual feed`, 24.71). |
| Wine and CrossOver | Seen as a generic HID joystick (task: hardware check, not claimed here). | Seen as Xbox-class where Wine's SDL path lists it. | Misread where Wine's SDL path lists it. |
| Browsers | W3C Gamepad API non-standard mapping unless the browser has a rule for the ID; OJD publishes a W3C-style description. | Standard mapping expected through the Xbox ID. | Standard mapping: Firefox 158 and Safari 27.0.1 give every control its slot but Share; Chrome 156 every control but Guide, Share as B17 (`ojd diagnose browsers`). |

The browser and Wine rows are expectations to verify by the hardware checks, not facts. The mapping line follows the published button usages pinned by `GenericGamepadHIDTests.normalizedButtonsSerializeToTheirPublishedUsages`; SDL accepted the format live, and the button order awaits a hardware re-check:

```text
03000000091200004f4a000008040000,OpenJoystickDriver Generic HID Gamepad,a:b0,b:b1,x:b2,y:b3,leftshoulder:b4,rightshoulder:b5,back:b6,start:b7,leftstick:b8,rightstick:b9,dpup:b10,dpdown:b11,dpleft:b12,dpright:b13,guide:b14,misc1:b15,leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:+a4,righttrigger:+a5,platform:Mac OS X,
```

`ojd virtual show --json` gains `sdl: { guid, mapping }` and `w3c: { ... }`; `ojd virtual export-mapping --format sdl|w3c` writes them. Submitting the mapping to SDL_GameControllerDB or upstream is an outward-facing decision of the user and is not in tasks. A new pid.codes entry for a layout that matches the W3C standard mapping directly is an open question.

### D7 Device matching and same-ID clones

A record `modes[]` entry matches on any of: link kind, interface signature (class, subclass, protocol, endpoint set, HID usage page and usage), manufacturer and product strings, `bcdDevice` range, and read-only probes. A probe is a `getReport` of a named feature report with an expected answer, a stall, or a byte pattern; probes never write.

Live evidence (2026-10-14): two `054C:0268` DS3 (locations `01130000`, `01140000`) have identical strings, `bcdDevice 0100` and 148-byte descriptor, but differ in feature reports:

| Report | Location 01130000 | Location 01140000 |
| --- | --- | --- |
| `0xEF` | stall `0xE0005000` | answers |
| `0x01`, `0xF2`, `0xF5`, `0xF7`, `0xF8` | differ | differ |

Live evidence (2026-10-23): the genuine Sony CECHZC2E, alone on location `00130000`, answers `0xEF` with 49 bytes (`00 EF 04 00 08 03 00 10 …`), so the answering column above is the genuine pad and the stalling column is the clone. With both plugged in, the mode selector picks `feature-ef-answers` for the genuine pad. The clone, alone on the same location `00130000`, stalls `0xEF` at lengths 49, 50 and 64 with `0xE0005000`, which `IOUSBHostFamilyDefinitions.h` names `kUSBHostReturnPipeStalled`. `PhysicalHIDFailure(ioReturn:)` counts that code as `declined`, as it does `kIOUSBPipeStalled` (`0xE000404F`), so the clone's `feature-ef-answers` keys do not hold and the default mode runs. A genuine CECHZC1(E), which has no rumble, alone on `00130000`, answers `0xEF` too (`00 EF 03 00 04 03 01 B0 …`). So an answer marks a genuine Sony pad and a stall marks this clone. The two genuine replies differ in bytes 2 and 4 (`03`/`04` for the CECHZC1, `04`/`08` for the CECHZC2E); with one unit of each, no mode keys on those bytes. The genuine one is the user's unit with rumble; the clone is the "other clone mentioned in wiki" (not GP100). Because decision 5 says clone behavior is hit-or-miss until someone tests, the first task builds the mechanism and the hardware check validates it.

DEXT matching is generated from records whose route is `ExtensionOwned`, limited to the seven granted IDs (`045E:02D1`, `02DD`, `02E3`, `02EA`, `0B00`, `0B0A`, `0B12`). The DriverKit generator (`Sources/DriverKitGenerator/main.swift`, `OutsideGrantError`) rejects an `ExtensionOwned` record outside the set; `Scripts/Signing/configure.py` and `Scripts/Build/driverkit.sh` check the profiles and entitlements. A record asking for the extension outside the set fails `./Scripts/ojd check driverkit`. More IDs need a new Apple request (user's call).

DS3 over Bluetooth: macOS 27 asks for a PIN the DS3 lacks; macOS 12 pairs. The host-address write (`ojd controller pair --host-address auto`) is added and verified on the A1398.

### D8 Identity naming

| New name | Replaces | Meaning |
| --- | --- | --- |
| `ControllerModelID` | model-only use of `DeviceIdentifier`, `RecordIdentity`, `OJDControllerRecordIdentity`, `PhysicalHIDIdentity` | Which record |
| `ControllerHardwareIdentity` | `ControllerIdentity` | Model plus optional serial number |
| `ControllerConnectionAddress` | `locationID`, `interfaceNumber`, `USBTransportServiceIdentity`, Switch 2 synthetic locations | Enum: `ioKit(locationID, interfaceNumber?)`, `usbService(route, serviceID)`, `gattPeripheral(UUID)` |
| `LogicalControllerID` | `DeviceIdentifier` (full use) | Hardware, address, optional role |
| `ControllerSessionToken` | `runtimeIdentifier` (`E-...`), `M-` fallback dropped | One attachment |
| `ControllerPortKey` | `UnitIdentity` (`U-...`), `VirtualHIDProfileOverrideStore.Identity` | Stable user-facing slot |
| `ControllerReference` | `ControllerSelection`, `ControllerSelector`, `RuntimeDeviceSelector` | `.session`, `.port` or `.model`; one parser for CLI, GUI and RPC |

`PhysicalDevice` and `PhysicalInterfaceSignature` keep their names. `UnboundDeviceKey`, `HIDInitializationKey` and `USBTransportModel` are reviewed in the same pass. Footprint: `DeviceIdentifier` 1012 references in 248 files (84 in Sources, 164 in Tests; the CLI audit counted 1022), 22 model-only construction sites, `runtimeIdentifier` 474, `RuntimeDeviceSelector` 105, `ControllerIdentity` 94. The renames go in the dependency order of task groups 3 to 6.

### D9 CLI

Follows clig.dev plus Apple conventions; global flags `--json --plain -q --no-color --no-input --timeout` stay. Existing groups stay: `status`, `permission`, `service`, `controller`, `virtual`, `profile`, `binding`, `config`, `record`, `mod`, `access`, `setting`, `update`, `log`, `diagnose`, `explain`; `extension` becomes `transport-extension`.

| Old | New |
| --- | --- |
| `controller ownership native\|virtual`, `outputOwner macos\|ojd`, record `ownership` | `controller claim <ref>` / `controller release <ref>`, record field `server` |
| `ownership.physical` `driverKitOwnedUSB`, `nativeGamepad`, `nativeHIDVisible` | `ExtensionOwnedUSB`, `SystemGamepad`, `SystemHIDVisible` |
| `extension` command, kind `DriverExtension` | `transport-extension`, kind `TransportExtension` |
| `usbExtension claims\|doesNotClaim` | `transportClaim claimed\|unclaimed` |
| permission ids `input-monitoring`, `accessibility`, `driver-extension` | `input-read`, `input-inject`, `usb-transport` |
| `identityKind team\|apple`, `teamIdentifier` | `publisher.kind Signed\|Platform`, `publisher.id` |
| `--app <bundle-id>`, `bundleIdentifier` | `--app <app-id>`, `appID` |
| modifier names `command`, `option` | `meta`, `alt` |
| `diagnose --bundle` | `diagnose --output` |
| `accessBackend ioHID\|ioUSBHost\|usbDriverKit\|coreBluetoothGATT` | `HID\|RawUSB\|USBExtension\|GATT` |
| `macOSVersion` | `osVersion` plus `osName` |
| `appleGameControllerAudit`, `appleExactDeviceCount`, `appleRecord`, `appleIdentifiers` | `systemGamepadAudit`, `systemExactDeviceCount`, `systemRecord`, `systemIdentifiers` |
| kinds `USBPacket`, `JoyConPair` | `RawReport`, `ControllerPair` |
| socket in `DARWIN_USER_TEMP_DIR` | runtime-directory port |
| endpoint `as: SDLCompatible` | persona ids |

New: `ojd virtual export-mapping`, `ojd setting` keys for every GUI-only switch (per-event notifications, Send Test Notification, Copy Support Report as `diagnose` on stdout, which the GUI copies), a settings file schema (settings move out of `UserDefaults` into layered files), and a single `DataDirectory` port that every store uses. The CLI target imports the Service in 9 files and USB in 2; the neutral core is split from a macOS host adapter so that `Sources/OpenJoystickDriver` has no macOS-only imports outside `platform`. The command tree is checked by a test that lists every command and flags any without a GUI place (D10).

Command-line tool link (open item 4, user decision 2026-10-15): the app owns the link, as other macOS apps that ship a tool do (an Install Command Line Tool action that asks for an administrator password to write `/usr/local/bin`). The app installs and removes it from the Command-Line Tool section of Settings > Advanced; `ojd` does not install or remove it and only reports whether it is installed, in `ojd status`.

Facts that go to docs: `docs/development/wire-protocols.md:20,22` is stale; `source-topology.md` lists a nonexistent `CLI/Catalog/`; the stale backend id `gameControllerHID` is removed.

### D10 Coverage matrix: CLI to menu bar to GUI

The GUI covers every CLI action that a window can naturally perform; the menu bar is a subset of GUI. Commands and options that exist only for terminals and scripts have no GUI place and are listed as CLI-only: `virtual feed` (reads controller frames from standard input), `service start`, `service stop` and `service wait` (the app process hosts the service: a window exists only once its listener is running, so the app cannot start or stop its own service), the options of `controller watch` (`--all`, `--first-press`, `--duration`, `--output`: a window shows one controller's stream continuously), output-only options (`--json`, `--plain`, `--quiet`, `--no-color`, `--no-input`), `--timeout` (bounds how long a terminal command waits for the service; a window has no such wait), the confirmation and preview flags (`--force`, `--dry-run`: a window confirms in a sheet and shows the result), the `--frames` option of `diagnose` (the window of a frame-timing run that a person starts in a terminal and then moves the sticks for), and the terminal's own `help`, `--help` and `--version`. `GUICoverageEntries` lists exactly these, and every other CLI leaf and option names the GUI symbol that performs it. User: "CLI-only. so, things that GUI naturally can not do, will not be in GUI. GUI only covers what CLI<=>GUI can naturally do."

| CLI group | GUI area | Main menu | Status item |
| --- | --- | --- | --- |
| `status`, `transport-extension`, `permission`, `service` | problem banner, Controllers (connected count), Access | none | status line, Open Window |
| `controller`, `virtual`, `config show` | Controllers (list, detail with Test section, persona, serving) | Controller menu | Controllers submenu |
| `profile`, `binding` | Profiles | Profile menu, File > Import/Export Profile | Profiles submenu |
| `record`, `mod` | Library | File > Install Record or Mod | none |
| `access` | Access | none | Grant Access |
| `log`, `diagnose`, `explain` | Activity | File > Save Support Report, Save Activity Log; Help | Help submenu |
| `setting`, `update` | Settings window | App > Settings | Settings |

### D11 GUI

The GUI is redone entirely as an AppKit shell for macOS 12: `NSToolbar`, `NSStatusItem` with `NSMenu`, `NSWindowController` for Settings; SwiftUI content inside `NSHostingController`. `NavigationSplitView`, `MenuBarExtra` and `Window` need macOS 13, and `.inspector` needs macOS 14, so they are not used. `NSToolbarItemGroup` `selectOne` and `NSTrackingSeparatorToolbarItem` (macOS 11) are available.

- Main window: an `NSSplitViewController` whose full-height sidebar (`NSSplitViewItem(sidebarWithViewController:)`) lists the five areas Controllers, Profiles, Library, Access and Activity, each with a symbol; `Command-1` to `Command-5` select them. Controllers, Profiles and Library add a list column between the sidebar and the detail, as in Notes; Access and Activity are one pane. The toolbar holds the sidebar toggle, an `NSTrackingSeparatorToolbarItem` on the sidebar edge, the area title and subtitle (`NSWindow.title` and `subtitle`), and only the selected area's actions. View > Show Sidebar and Hide Sidebar toggle the sidebar; it is shown by default. The content does not repeat the area title. Toolbar segmented controls switch views of one area's content, never areas, as in Photos and Finder. Confirmations are window-modal sheets. Errors use one inline pattern (symbol, text, Details revealing `ojd explain`).
- Problem banner: one line at the top of the window, shown only while the driver or the service has a problem, with Details; it shows no controller counts. The connected-controller count lives in Controllers, which detects controllers automatically and has no Refresh.
- Input Test is the Test section of the Controllers detail: no window, no Open Input Test button. It names the physical controller, shows analog values once, and hides Motion calibration and Lighting for a controller without them.
- Native components only (decision 16): `NSSplitViewController` columns, SwiftUI `Form`, `List`, `Table`, `Toggle`, `Picker`, `Button`, `TextField` with their default styles; no custom cards, tiles, tinted boxes, big in-content headings or custom empty-state blocks. On macOS 13 and later forms use `.formStyle(.grouped)` behind `if #available(macOS 13, *)`; macOS 12 shows the plain `Form`. Both share one structure.
- Columns, never stacking: Controllers, Profiles and Library are three split-view columns (sidebar, list, detail) with minimum widths; the window's minimum size fits all three, and a narrow window collapses the sidebar first. No layout switches to a vertical stack.
- Area actions live in the toolbar (add, install, validate, grant, copy, filter, search), not in the content. Empty lists show one secondary line.
- Area layouts: Controllers list and a form detail (sections; Advanced is a section); Profiles list and editor; Library one list with Records and Mods sections and a detail; Access one form (Permissions rows with status and Open System Settings when missing, Endpoints with switches, Programs, Tokens, Refused recently); Activity a full-height log table with All/Output/Errors, search and Copy in the toolbar. Explain Error Code is a sheet from the Help menu.
- One obvious way: each action and each fact appears once on a screen; capabilities a controller lacks are hidden.
- Unknown values: a value that is unknown, missing or not applicable shows the localized word "None" from one shared helper; fields that can never apply are hidden.
- Sections: each section is a native `Form` `Section` or `List` section with a plain header; an empty section is one compact line.
- Settings window: a preference-style `NSToolbar` (`toolbarStyle = .preference`) of one selectable icon-and-label item per pane, one window width, the height fitting each pane, with panes General (launch at login, show in menu bar, updates), Notifications, Advanced (Command-Line Tool, Xbox USB driver, developer tools).
- Apple HIG pages followed: Sidebars, Split views, Toolbars, Segmented controls, Settings, Windows, The menu bar.
- Known bugs the rebuild must not reproduce: uninstall alert shows repair text (`SetupCard.swift:64-70`); a sidebar toggle labelled "Settings navigation" (`WindowController.swift:196-204`); window titled with app name (`:85`); orphan `saveSupportReport`/`saveSupportLogs` actions (`MenuBarCoordinator+ApplicationMenu.swift:121-142`); hard-coded English `sharingWarning` (`ApplicationServiceLogService.swift:39-41`); `wiki/Using-the-App.md:160` names nonexistent `app login disable`; "Controller Test" button only switches pane; Copy Support Report gives no feedback; CLI-tool uninstall has no confirmation; Bluetooth detected by comparing the English string "Bluetooth" (`ControllerDetailView+Facts.swift:64-66`, `MenuBarCoordinator+Lifecycle.swift:325`); status line built by joining with " · " (`MenuBarViewModel.swift:24-52`).
- Visual design: `/impeccable` passes with 13 reference screen groups (shell with problem banner, Controllers, Input Test, Profiles, Library, Access, Activity, Settings window, status item, main menu, destructive confirmations, errors), each in light and dark, with a subset under Increase Contrast, Reduce Transparency, larger text, VoiceOver, `de-DE` and `ar-SA`. The user judges each visually; no group is called done without that approval.

### D12 Menu bar

Fixed item set; items are disabled, never hidden, except Grant Access, which is shown only while a permission is missing. Status item uses a template image. The state comes from the service by notification, with polling only as a fallback (today: 1 s polling).

```text
Status line
Controllers >  one submenu per connected controller: Suspend/Resume, Test Input..., Active Profile >, Disconnect Wireless Link... (disabled unless wireless), Show in Window
Profiles >     Activate, Deactivate
Grant Access...   (only while a permission is missing)
Open Window
Settings...
Help >         Activity Log..., Explain Error Code..., Report Problem..., Project Website
Quit
```

Main menu: App (About, Settings, Services, Hide, Hide Others, Show All, Quit), File (Import/Export Profile, Install Record or Mod, Save Support Report, Save Activity Log), Edit, View (the five areas `Command-1` to `Command-5`, Full Screen), Controller, Profile, Window, Help.

### D13 Localization

Keep `.strings` and `.stringsdict` (option A). `.xcstrings` is not compiled by SwiftPM (tested with a scratch package), so it is rejected. Namespaces as in decision 6, with examples:

| Prefix | Example key |
| --- | --- |
| `term.*` | `term.controller` |
| `action.*` | `action.disconnect` |
| `status.*` | `status.service.running` |
| `ui.<area>.*` | `ui.controllers.empty.title` |
| `ui.menu.*` | `ui.menu.file.saveSupportReport` |
| `ui.extra.*` | `ui.extra.controllers.suspend` |
| `ui.settings.<pane>.*` | `ui.settings.general.launchAtLogin` |
| `a11y.*` | `a11y.settingsPane.general` |
| `cli.<group>.<command>.*` | `cli.virtual.exportMapping.summary` |
| `error.<code>.*` | `error.E2023.message` |
| `notify.*` | `notify.controller.connected` |
| `platform.<os>.*` | `platform.macos.driverExtension.name` |

Segments are lowerCamelCase. OS-specific words appear only under `platform.*`. Every multi-argument string uses positional specifiers (102 keys lack them today). Every key has a translator comment (none today). The 69 duplicate English values are merged where the meaning is the same, and the roughly 51 Apple-specific values are split into neutral and `platform.*` pairs. Plurals: 5 today; the checker requires a `.stringsdict` entry for every key that takes a count. `crowdin.yml` shape: source `en-US.lproj/*.strings` and `*.stringsdict`; translation `%osx_locale%.lproj/%original_file_name%`. Stop copying `Localizable.template.*` into the bundle. `Scripts/Quality/check_localization_keys.py` is updated for the new prefixes, positional specifiers, plural coverage, comment presence and the key-shape regex. Scale: 1602 keys across 22 bundles (`C`, `en-US` and 20 locales); estimate 3 to 5 engineering days for the re-key alone.

Catalog-wide decisions left open by the earlier review (`06-l10n-review`) go to Open Questions.

### D14 SDK, endpoint and streaming

The public endpoint (today `apiVersion openjoystickdriver.io/v1beta1`, kinds Challenge, Hello, Welcome, Subscription, FeedRequest, FeedSession, Frame, Status; errors E1001 to E1009) moves to `openjoystickdriver/v1alpha2`, gains a `KeepAlive` kind that holds an idle feed open past the 2 s E1009 close without resending a frame, is documented in `docs/sdk/`, and ships with a reference client (the repository already has `Tests/RepositoryScripts/test_endpoint_reference_client.py`). Streaming boundary: `InputSource` produces canonical frames and `OutputSink` consumes them; physical controllers, the virtual HID device and the endpoint are plug-ins on that boundary, compiled in; OJD loads no code at run time. WebRTC is a separate program, the WebRTC bridge in `Tools/WebRTCBridge/`, with its own Swift package that depends on LiveKitWebRTC (`livekit/webrtc-xcframework`, MIT). It is an endpoint client: `FeedRequest` and `RumbleCommand` on the Mac that runs the game, `Subscription` on the player's Mac. The offer and answer travel out of band, so the bridge opens no listening socket, and the root package and `swift test` do not fetch the framework. The bridge code that does not touch WebRTC lives in a dependency-free package, `Tools/BridgeCore`, which the root package's service tests use to run a host bridge against a real in-process `EndpointServer`; `./Scripts/ojd check tools` and CI run the bridge package's `swift test`. Latency and fan-out limits are stated in the spec, and the existing `.bufferingOldest(64)` queue policy from issue #22 is now a per-record tuning value (`tuning.frameQueueCapacity`, newest frame wins, host replies never evicted). Header errors split by medium, one rule each: a file with a missing or unsupported `apiVersion` gets E5001; an endpoint line gets E1010 (unsupported `apiVersion`), E1011 (wrong `kind`) or E1012 (missing or non-string header field), each with `details.supportedAPIVersions`. Retired codes stay in the catalog with `retiredIn`, and `ojd explain` still resolves them.

### D15 Relation to the open issues

Issues the data model must make expressible: #38 (ShanWan vendor control reads, gated by manufacturer string), #41 and #34 (8BitDo Ultimate 2C BLE identify command, mode switching PIDs 301B, 301C, 310A, 310B, 6012, 6013, 901B), #35 and #37 (Flydigi Vader 4 Pro dongle `04B4:2412` vendor report 4), #33, #31, #22 (375 Hz versus 5575 Hz polling, reset loop), #21 (keepalive), #45 (ASUS ROG Raikiri Pro GIP with no packets), #46, #19, #14, #11, #9, #8. Attach and replug robustness (#32, #48, #18, #46, #8) is code, not data. Open pull requests #47, #42, #36 put VID:PID in Swift and are not merged as they stand; #40 and #39 edit generated files and are redone through authored inputs. Facts from other projects are used as facts only.

## Risks / Trade-offs

- [The release is very large and touches nearly every file] -> ordered task groups, each with a Verify line; the equivalence harness comes first.
- [Data-driven records cannot express some protocol] -> keep that protocol as code and give it a typed-parameter record; list it in `protocol-descriptions`.
- [Probe-based clone detection misfires on a firmware revision nobody tested] -> probes are read-only, a failed probe falls back to the model's default mode, and the hardware check covers the two DS3 units.
- [Steam may not read `SDLCompatible`] -> Steam is untested with it (24.65); a user switches to `Generic` per model.
- [Persona change surprises users of 0.5.x] -> it is a breaking release; release notes say so.
- [GUI visual quality cannot be machine-checked] -> user approval gates per screen group.
- [Machine-translated strings drift while keys move] -> re-keying is a mechanical rename first; translation review is a separate task.
- [Apple grants only seven USB IDs] -> the generator refuses extension records outside the set.
- [The hardware list has no Wolverine V1 TE or DS4 v2 in the live run] -> hardware checks list each device; the user plugs them in.

## Migration Plan

None. A stored file that lacks the supported `apiVersion` or does not validate against the current schema is refused like any other invalid file, with the same error code and a message that names the file, the version found (or its absence) and the supported one. No code, test or string knows earlier shapes, names or words. Release notes record what changed and give no conversion steps. Rollback is not offered; the previous release stays installable.

## Open Questions

1. Settled (D7): genuine CECHZC2E and CECHZC1(E) pads answer `0xEF`, and the clone stalls it.
2. Settled 2026-10-15: no request for more `transport.usb` IDs; the extension stays with the seven granted.
3. Settled 2026-10-15 (task 22.6, one commit each): French spacing per locale (fr-FR NBSP before `:` and narrow NBSP before `; ? !`; fr-CA NBSP before `:` only; NBSP inside `« »`), curly `“…”` quotes in `pt-BR` and `es-MX`, `id-ID` instal, `vi-VN` "ở chế độ gốc", a full clause in `tr-TR` `cli.mod.list.discussion`, formal "您" in `zh-HK`/`zh-TW`, `ar-SA` "الخدمة قيد التشغيل", German "Endet mit 1". The choices were left by the review: French spacing before `: ; ? !` and NBSP, `pt-BR`/`es-MX` quotes (guillemets or curly), `id-ID` instal/pasang, `vi-VN` "mot cach goc", `tr-TR` `cli.mod.list.discussion`, `zh-HK`/`zh-TW` informal versus formal "you" in five strings, `ar-SA` running-service split, German "Endet mit 1" versus "Beendet sich mit 1".
4. Settled 2026-10-15: the command-line tool link belongs to the app; `ojd` only reports it (D9).
5. Do the button and axis directions of the `1209:4A4F` mapping hold under real presses? (hardware check)
6. Settled 2026-10-15: no new pid.codes entry; browsers reach the standard mapping through the Xbox ID (SDL consumer table).
7. Settled 2026-10-15: the OJD mapping is not submitted to SDL_GameControllerDB or SDL upstream.
8. Turn on GitHub Pages for the schema `$id` URLs? (outward-facing; the task prepares it)
9. Does a GIP pad need the host keep-alive (`03 20 seq 03 00 00 00` every 4 s in `xbox-gip.json`)? [MS-GIPUSB] v20240916 3.1.5.5.2 defines Status Device (`0x03`) only from device to host, and no recorded source gives the host keep-alive. The GameSir `3537:1010` and Razer `1532:0A15` work with it (maintainer, 2026-10-23), so it stays until a pad shows a fault from it; the check is a record patch with `protocol.keepAlive` set to `false` and 60 s idle with input still arriving.
