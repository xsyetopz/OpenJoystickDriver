# Source Topology

OpenJoystickDriver splits the package into SwiftPM targets whose dependencies enforce the layering, and into capability directories inside each target. Source and test paths name durable owners; generated DriverKit output is never source.

## Targets

| Target | Owns |
| --- | --- |
| `OpenJoystickDriverKit` | controller domain, HID/USB ports, parsers, profiles, policy, shared RPC contracts |
| `OpenJoystickDriverMacOSPlatform` | macOS implementations of Kit ports: IOKit HID access and streams, the `IOHIDUserDevice` virtual-device publisher, GameController synthetic HID, access control, login-item registration, code signing identity, physical report descriptors |
| `OpenJoystickDriverUSB` | IOUSBHost/USBDriverKit facade and restricted DEXT configuration |
| `OpenJoystickDriverService` | runtime RPC server, output dispatch, remapping library/routing/system events, status, diagnostics |
| `OpenJoystickDriverCLI` | command grammar and command implementations; neutral, reaches macOS through `PlatformHost` |
| `OpenJoystickDriverPresentation` | AppKit lifecycle and SwiftUI user flows |
| `OpenJoystickDriverMacOSHost` | macOS host adapter: `MacOSPlatformHost` conformance and the headless application host |
| `OpenJoystickDriver` | executable: main, host installation, App Intents, bundle resources |
| `DriverKitGenerator` | build-time generated native-project entry point |
| `OJDRepositoryTool` | development executable that checks controller records, protocol descriptions, profiles and virtual devices and applies built-in patches; not shipped |
| `OpenJoystickDriverHIDTool` | internal hardware investigation executable |
| `OpenJoystickDriverGameControllerProbe` | isolated GameController visibility probe |
| `OpenJoystickDriverGameControllerViewer` | window that shows every GameController input element of each connected controller and prints each change as a JSON line, to test GameController input by hand; not shipped |

`OpenJoystickDriverHIDTool` is internal. `OJDRepositoryTool` is a development tool that neither the app nor `ojd` ships; it needs no localization, because its message text is the Kit error description, and it depends only on Kit. It prints one JSON line `{code, file, message}` for each problem and exits 1 when there is one, and 64 for a call it refuses: `swift run OJDRepositoryTool validate controllers|descriptions <directory>`, `validate profiles|virtual-devices <path>...`, and `apply-patches --controllers <directory> --patches <directory> --out <directory>`.

## Dependency Graph

`Package.swift` declares these dependencies; the compiler rejects any import outside them.

```text
Kit
MacOSPlatform             -> Kit
USB                       -> Kit
Service                   -> Kit, MacOSPlatform, USB
CLI                       -> Kit
Presentation              -> Kit
MacOSHost                 -> Kit, MacOSPlatform, USB, Service, Presentation
OpenJoystickDriver        -> Kit, Service, CLI, Presentation, MacOSHost
DriverKitGenerator        -> USB
OJDRepositoryTool         -> Kit
HIDTool                   -> Kit, MacOSPlatform, USB
GameControllerProbe       -> Kit, MacOSPlatform
GameControllerViewer
```

- Presentation depends on Kit only. It reaches the runtime through its `ApplicationServiceGateway` protocol (implemented by `ApplicationServiceClientGateway` over the Kit RPC client) and injected closures, so it never imports Service, CLI, or USB.
- The CLI depends on Kit only. Kit declares the `PlatformHost` protocol and the `PlatformHosts` registry. The executable installs `MacOSPlatformHost` from `OpenJoystickDriverMacOSHost` at launch, and the CLI calls `PlatformHosts.current` for extension status, activation, USB scanning, entitlement checks, access state, code signing identities, physical report descriptors, and login-item registration. A command run without an installed host stops on a precondition.
- Kit declares the ports a host implements: `PlatformHost`, `AccessControlSystem`, `ApplicationServiceRegistration`, `HIDAccessBackend`, `VirtualHIDDevicePublisher` with `VirtualDeviceBackend`, and `Switch2BluetoothLEWriter`. `OpenJoystickDriverMacOSPlatform` implements the IOKit, Security, ServiceManagement, and `IOHIDUserDevice` ones. The composition roots (`ApplicationServiceRuntime` in Service, `MacOSPlatformHost` in MacOSHost, and the two investigation executables) pass the implementations in, so Kit has no macOS-only framework import.
- Only `OpenJoystickDriverUSB`, `DriverKitGenerator`, and their tests import SwifterKit. Kit owns stable Sendable transport values and protocols; USBDriverKit, IOUSBHost, and SwifterKit lifetimes stay in USB.
- The headless host in the executable owns one `ApplicationServiceRuntime`, which starts the authenticated RPC server; both types live in Service.

## Directory Owners

```text
Sources/OpenJoystickDriverKit/
  ApplicationService/  shared client, RPC, payload, lifecycle, and remapping contracts
  Bluetooth/           Switch 2 Bluetooth LE routing
  CommandLine/         kebab-case spellings of enum values for command-line output
  Concurrency/         locking and blocking-work helpers
  Platform/            `PlatformHost` protocol and `PlatformHosts` registry
  Device/              identity types (model, hardware, port key, session token, reference),
                       Controller state, Manager, Discovery (HID, USB), PhysicalOutput, Pipeline
  Diagnostics/         support reports, probes, health, build identity, and packet logs
  Errors/              the `ErrorCode` catalog
  HID/                 the `HIDAccessBackend` port, bounded reads, and `HIDManager` over a host backend
  Localization/        string lookup over the bundled locale tables
  Output/              the `VirtualHIDDevicePublisher` port, dispatchers, reports, formats, and profiles
  Packages/            mod package manifest, validation, and the installed-package store
  Permissions/         app permission policy
  Process/             bounded external process runner and the command-line tool link status
  Protocol/            catalog, GIP, parsers, drivers, classification, and physical-output
                       capabilities
  Remapping/           reusable profile and mapping engine
  Resources/           generated controller records (Controllers/), protocol descriptions
                       (Protocols/), virtual devices (VirtualDevices/), and localization tables
  Settings/            the `Settings.plist` store, document, and watcher (defaults, then the user file)
  Storage/             DataDirectory port and its macOS implementation; the only path builder
  Streaming/           `InputSource` and `OutputSink`, the frame boundary every path attaches to
  Update/              release version parsing and update checking

Sources/OpenJoystickDriverMacOSPlatform/
  HID/                 IOHID access backend, device streams, synthetic-device filter, physical
                       report descriptors, and IOReturn failure mapping
  Output/              `IOHIDUserDevice` publisher and virtual-device backend
  Permissions/         `AccessControlSystem` over IOHID access and CoreGraphics post-event access
  ApplicationService/  main-app login-item registration over `SMAppService`
  Security/            code signing identity and socket-peer code checks

Sources/OpenJoystickDriverUSB/
  Configuration.swift  restricted DEXT USB configuration
  PassiveProbe/        passive USB registry and descriptor probing
  Transport/           IOUSBHost and USBDriverKit transports

Sources/OpenJoystickDriverService/
  Remapping/           Profiles (library and persistence), Routing, SystemEvents
                       (CoreGraphics adaptation)
  Runtime/             runtime composition, Automation, Endpoint, OutputDispatch, RPC, file
                       watchers, and virtual device diagnostics
  Status/              SystemExtension submission, probe, and setup client

Sources/OpenJoystickDriverCLI/
  Commands/            one directory per command group: Access, Binding, Config, Controller,
                       Diagnose, Explain, Log, Mod, Permission, Profile, Record,
                       Service, Setting, Status, TransportExtension, Update, Virtual
  Root/                global options, failure and terminal handling, service connection

Sources/OpenJoystickDriverMacOSHost/
  MacOSPlatformHost.swift, HeadlessApplicationHost.swift

Sources/OpenJoystickDriverPresentation/
  Access/  Activity/  Components/  Controllers/  InputCapture/  Library/  MainMenu/  MainWindow/
  MenuBar/  Profiles/  Runtime/  Settings/  SettingsWindow/

Sources/OpenJoystickDriver/
  main.swift, App/ (Info.plist, Host.entitlements), Resources/
  platform/macos/      PlatformHostInstallation.swift and the App Intents (compiled into the app target for discovery)
```

The neutral targets are `Sources/OpenJoystickDriverKit`, `Sources/OpenJoystickDriverCLI`, and the executable's files outside `Sources/OpenJoystickDriver/platform`.
Kit may import CryptoKit, Darwin, Dispatch, and Foundation. Neutral means free of macOS device, security, and application frameworks: Darwin (POSIX calls) and CryptoKit (hashing) ship on every Apple platform the package declares, so Kit builds on Apple platforms only.
The CLI may import ArgumentParser, Darwin, Dispatch, Foundation, Glibc, and Kit; the executable may import Dispatch, Foundation, CLI, and Kit.

Kit `Diagnostics/` holds reports and health types that both the CLI and app read.

## Tests

Each test target mirrors its source target and directory names: `Tests/OpenJoystickDriverKitTests/`, `Tests/OpenJoystickDriverMacOSPlatformTests/`, `Tests/OpenJoystickDriverUSBTests/`, `Tests/OpenJoystickDriverServiceTests/`, `Tests/OpenJoystickDriverCLITests/`, and `Tests/OpenJoystickDriverPresentationTests/`. A test for `Sources/<Target>/A/B/File.swift` lives in `Tests/<Target>Tests/A/B/`. Shared fixtures live in `Tests/OpenJoystickDriverTestSupport/` (depends on Kit; holds the fake `PlatformHost` and the access, registration, and HID backend fakes) and `Tests/ProtocolPacketFixtures/`; `Tests/ParserCompatibilityHarness/` backs `just test-parsers-macos14`. Add behavior tests, not source-text substring tests.

## Naming and Limits

Extension files are `Type+Concern.swift`, where `Concern` is a noun phrase naming the content, such as `+Queries`, `+Parsing`, or `+Lifecycle`. Delete empty extension stubs.

SwiftLint `file_length` fails a Swift file with more than 500 lines under `Sources` and `Tools`, or more than 1000 under `Tests` (`Tests/.swiftlint.yml`). Comment-only and blank lines do not count.

## Rules

- Give each capability one canonical owner; retain no aliases, forwarding files, or old entry points.
- Keep Kit independent of SwifterKit and of app, runtime, and platform composition.
- Put IOUSBHost/DriverKit adaptation in USB; keep parsing in Kit.
- Use IOKit HID (`IOHIDManager`, `IOHIDDevice`, `IOHIDUserDevice`) in `OpenJoystickDriverMacOSPlatform` on every supported macOS; HID has no OS-version branch and the package does not link CoreHID.
- Never edit or commit `.build/driverkit/generated/`; validate generation with `just driverkit-check`. `just driverkit-generate [path]` writes into a missing folder only (default `.build/driverkit/generated/`) and refuses an existing one, so a generated project never mixes with an earlier one; delete the folder first to regenerate it.

## Rejected Alternatives

- Directories only, no target split. Layering stayed unchecked and eroded: a Status to CLI dependency appeared. Target dependencies make the compiler reject such imports.
- More services or processes. No independent deployment or scaling need exists; the app hosts one runtime.
