# Source Topology

OpenJoystickDriver splits the package into SwiftPM targets whose dependencies enforce the layering, and into capability directories inside each target. Source and test paths name durable owners; generated DriverKit output is never source.

## Targets

| Target | Owns |
| --- | --- |
| `OpenJoystickDriverKit` | controller domain, HID/USB ports, parsers, profiles, policy, shared RPC contracts |
| `OpenJoystickDriverUSB` | IOUSBHost/USBDriverKit facade and restricted DEXT configuration |
| `OpenJoystickDriverService` | runtime RPC server, output dispatch, remapping library/routing/system events, status, diagnostics |
| `OpenJoystickDriverCLI` | command grammar and command implementations |
| `OpenJoystickDriverPresentation` | AppKit lifecycle and SwiftUI user flows |
| `OpenJoystickDriver` | executable: main, headless host, composition root, bundle resources |
| `DriverKitGenerator` | build-time generated native-project entry point |
| `OpenJoystickDriverHIDTool` | internal hardware investigation executable |
| `OpenJoystickDriverGameControllerProbe` | isolated GameController visibility probe |

## Dependency Graph

`Package.swift` declares these dependencies; the compiler rejects any import outside them.

```text
Kit
USB                       -> Kit
Service                   -> Kit, USB
CLI                       -> Kit, USB, Service
Presentation              -> Kit
OpenJoystickDriver        -> Kit, Service, CLI, Presentation
DriverKitGenerator        -> USB
HIDTool                   -> Kit, USB
GameControllerProbe       -> Kit
```

- Presentation depends on Kit only. It reaches the runtime through its `ApplicationServiceGateway` protocol (implemented by `ApplicationServiceClientGateway` over the Kit RPC client) and injected closures, so it never imports Service, CLI, or USB.
- Only `OpenJoystickDriverUSB`, `DriverKitGenerator`, and their tests import SwifterKit. Kit owns stable Sendable transport values and protocols; USBDriverKit, IOUSBHost, and SwifterKit lifetimes stay in USB.
- The headless host in the executable owns one `ApplicationServiceRuntime`, which starts the authenticated RPC server; both types live in Service.

## Directory Owners

```text
Sources/OpenJoystickDriverKit/
  ApplicationService/  shared client, RPC, payload, lifecycle, and remapping contracts
  Concurrency/         locking and blocking-work helpers
  Device/              controller identity, Manager, Discovery (HID, USB), input state,
                       PhysicalOutput, Pipeline
  Diagnostics/         support reports, probes, health, build identity, and packet logs
  HID/                 availability-selected physical HID access
  Localization/        string lookup over the bundled locale tables
  Output/              availability-selected virtual HID, backends, reports, formats, and profiles
  Permissions/         app permission policy
  Process/             bounded external process runner
  Protocol/            catalog, GIP, parsers, drivers, classification, and physical-output
                       capabilities
  Remapping/           reusable profile and mapping engine
  Resources/           generated controller records (Controllers/) and localization tables
  Update/              release version parsing and update checking

Sources/OpenJoystickDriverUSB/
  Configuration.swift  restricted DEXT USB configuration
  PassiveProbe/        passive USB registry and descriptor probing
  Transport/           IOUSBHost and USBDriverKit transports

Sources/OpenJoystickDriverService/
  Diagnostics/         runtime controller-input diagnostics
  Remapping/           Profiles (library and persistence), Routing, SystemEvents
                       (CoreGraphics adaptation)
  Runtime/             runtime composition, ForegroundOutput, OutputDispatch,
                       authenticated RPC server
  Status/              RuntimeSnapshot and SystemExtension status

Sources/OpenJoystickDriverCLI/
  Catalog/             command catalog and help text
  Commands/            Controller, Diagnostics, Installation, Mapping, Settings

Sources/OpenJoystickDriverPresentation/
  Components/  Controllers/  InputCapture/  MenuBar/  Profiles/  Runtime/  Settings/

Sources/OpenJoystickDriver/
  main.swift, App/ (headless host, Info.plist, Host.entitlements), Resources/
```

Kit `Diagnostics/` holds reports and health types that both the CLI and app read; Service `Diagnostics/` holds diagnostics that need the running runtime.

## Tests

Each test target mirrors its source target and directory names: `Tests/OpenJoystickDriverKitTests/`, `Tests/OpenJoystickDriverUSBTests/`, `Tests/OpenJoystickDriverServiceTests/`, `Tests/OpenJoystickDriverCLITests/`, and `Tests/OpenJoystickDriverPresentationTests/`. A test for `Sources/<Target>/A/B/File.swift` lives in `Tests/<Target>Tests/A/B/`. Shared fixtures live in `Tests/OpenJoystickDriverTestSupport/` (depends on Kit) and `Tests/ProtocolPacketFixtures/`; `Tests/ParserCompatibilityHarness/` backs `./Scripts/ojd test parsers-macos14`. Add behavior tests, not source-text substring tests.

## Naming And Limits

Extension files are `Type+Concern.swift`, where `Concern` is a noun phrase naming the content, such as `+Queries`, `+Parsing`, or `+Lifecycle`. Delete empty extension stubs.

`python3 Scripts/Quality/check_swift_file_length.py` checks every Swift file under `Sources` and `Tests` that Git tracks or that is untracked and not ignored. It fails when:

- a file has more than 500 code lines under `Sources`, or more than 1000 under `Tests`. Code lines are lines with Swift code; blank lines and comment-only lines do not count, and multiline string content does.
- the concern after the last `+` is exactly `Behavior` or `Scenarios`, or ends in a digit (`+Behavior2`, `+Scenarios1`). These names hide what a file owns.

## Rules

- Give each capability one canonical owner; retain no aliases, forwarding files, or old entry points.
- Keep Kit independent of SwifterKit and of app, runtime, and platform composition.
- Put IOUSBHost/DriverKit adaptation in USB; keep parsing in Kit.
- Use IOKit HID (`IOHIDManager`, `IOHIDDevice`, `IOHIDUserDevice`) on every supported macOS; HID has no OS-version branch and the package does not link CoreHID.
- Never edit or commit `.build/driverkit/generated/`; regenerate with `./Scripts/ojd driverkit generate` and validate with `./Scripts/ojd check driverkit`.

## Rejected Alternatives

- Directories only, no target split. Layering stayed unchecked and eroded: a Status to CLI dependency appeared. Target dependencies make the compiler reject such imports.
- More services or processes. No independent deployment or scaling need exists; the app hosts one runtime.
