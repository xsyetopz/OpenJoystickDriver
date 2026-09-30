# Placement

## Contents

- [Target and directory](#target-and-directory)
- [Naming and size](#naming-and-size)

## Target and directory

**Definition.** `Package.swift` declares these dependencies, and the compiler rejects any import outside them:

```text
Kit
USB                  -> Kit
Service              -> Kit, USB
CLI                  -> Kit, USB, Service
Presentation         -> Kit
OpenJoystickDriver   -> Kit, Service, CLI, Presentation   (executable, composition root)
DriverKitGenerator   -> USB
HIDTool              -> Kit, USB
GameControllerProbe  -> Kit
ParserCompatibilityHarness -> Kit, ProtocolPacketFixtures   (./Scripts/ojd test parsers-macos14)
```

Choose the lowest target whose dependencies cover the code:

| Code | Target |
| --- | --- |
| Controller domain, parsers, profiles, policy, RPC contracts | `OpenJoystickDriverKit` |
| IOUSBHost, USBDriverKit, SwifterKit lifetimes | `OpenJoystickDriverUSB` |
| Runtime, RPC server, output dispatch, profile library, status | `OpenJoystickDriverService` |
| Command grammar and commands | `OpenJoystickDriverCLI` |
| AppKit and SwiftUI | `OpenJoystickDriverPresentation` |
| `main.swift`, headless host, bundle resources | `OpenJoystickDriver` |

The capability directories inside each target are listed in `contributing/development/source-topology.md` under "Directory Owners". Tests for `Sources/<Target>/A/B/File.swift` go in `Tests/<Target>Tests/A/B/`. Shared fixtures go in `Tests/OpenJoystickDriverTestSupport/` and `Tests/ProtocolPacketFixtures/`.

**Use when.** Adding a file, or moving a type across directories or targets.

**Do not use when.** Never add a new target without an independent dependency boundary. Record the decision in `source-topology.md` if you do.

**Cost removed.** In a directories-only layout, a Status→CLI dependency appeared without anyone noticing. Target edges make the compiler reject that edge.

**Verify.** `swift build` succeeds. `rg -n '^import OpenJoystickDriver(Service|CLI|USB)' Sources/OpenJoystickDriverPresentation` prints nothing.

## Naming and size

**Definition.** `python3 Scripts/Quality/check_swift_file_length.py` fails when either of these holds:

- A file under `Sources` has more than 500 code lines, or a file under `Tests` has more than 1000. Blank and comment-only lines are not counted. Multiline string content is counted.
- The part of a file name after the last `+` is exactly `Behavior` or `Scenarios`, or ends in a digit (`+Behavior2`, `+OutputScenarios3`).

Extension files are `Type+Concern.swift`, where `Concern` is a noun phrase naming the contents. Examples: `DeviceManager+Queries.swift`, `MenuBarCoordinator+Lifecycle.swift`, and `DriverParseCharacterizationTests+DualShock4Parsing.swift`.

**Use when.** A file nears the limit, or a split is needed.

**Do not use when.** Never split a file only to pass the count. A split that forces `private` state to become `internal` weakens encapsulation. Look first for a cohesive concern to extract, such as a nested type or a sub-state struct.

**Example.** A 620-line `ProfileEditor.swift` that holds validation and layer editing splits into `ProfileEditor+Validation.swift` and `ProfileEditor+Layers.swift`. It does not split into `ProfileEditor+Behavior1.swift`.

**Verify.** The checker prints its success line. `fd -e swift '\+[A-Za-z]+[0-9]+\.swift$' Sources Tests` prints nothing.
