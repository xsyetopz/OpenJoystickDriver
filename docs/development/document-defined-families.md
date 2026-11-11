# Document-defined protocol families

Scope: what a protocol description document needs to register a family that the general layout driver runs. Three families run on it: `XboxXID`, `NintendoSwitchInputOnly`, and `VendorFlydigi` (`Sources/OpenJoystickDriverKit/Protocol/Catalog/ProtocolDriverRegistry.swift:209-218`).

Method: read the source on branch `feat/0.6.0-alpha.3` and searched `Sources/`, `Tests/`, `Resources/`, and `Scripts/` with `grep -rn`. Nothing was built or run. Paths under `Sources/OpenJoystickDriverKit/Protocol/` are shortened to `Protocol/`.

## What the layout driver reads

- The registry builds `ReportLayoutDriver(describedBy:...)` for the three families (`ProtocolDriverRegistry.swift:209-217`).
- That initializer stops with a precondition failure when the description sets no input layouts (`Protocol/Drivers/Generic/ReportLayoutDriver.swift:197-199`).
- A description sets layouts under `defaults.input.layouts` (`Protocol/Classification/ProtocolDescription+Document.swift:63`, `Protocol/Classification/ProtocolDescription.swift:567`).
- A description that sets layouts must list `input` in `recordSections` (`Protocol/Classification/ProtocolDescription+Validation.swift:57`).
- The three existing descriptions do both: `Resources/Protocols/xbox-xid.json:12` and `:46`, `Resources/Protocols/vendor-flydigi.json:9` and `:25`, `Resources/Protocols/nintendo-switch-input-only.json:10` and `:18`.
- The loader looks for one file per case of the enumeration and reports a missing file as a problem (`Protocol/Classification/ProtocolDescription.swift:306`, `:359-370`).
- A file whose stem names no case is refused with E5003 (`Protocol/Classification/ProtocolDescription.swift:380-382`, `:373-374`, `:391`).

A description document alone does not register a family. The enumeration must hold a case first.

## Closed places

Each place lists every family. A family left out of one is refused or does not compile.

### Schemas: 2 closed enumerations

| # | File | Lines | What |
|---|------|-------|------|
| 1 | `Resources/Schemas/controller.schema.json` | 328-349 | `$defs.protocol.properties.family`: `enum` of 19 names (`:330` `HIDDescriptor` to `:348` `NintendoWii`) |
| 2 | `Resources/Schemas/report.schema.json` | 775-796 | `rejectedCandidate.properties.protocolID`: `enum` of the same 19 names (`:777` to `:795`) |

Schema places that follow enumeration 1 by `$ref` and need no edit, 4:

- `Resources/Schemas/protocol-description.schema.json:15-17`.
- `Resources/Schemas/cli-output.schema.json:2197-2198`, `:2263-2264`, `:3393-3394`.

Schema places that name families and are not a full list:

- `Resources/Schemas/cli-output.schema.json:2094-2096`: `enum` of two names, `HIDDescriptor` and `HIDReportLayout`. A layout family is not one of them.
- `Resources/Schemas/protocol-description.schema.json:356-358`: a rule that applies to `XboxXUSB` only.
- `Resources/Schemas/protocol-description.schema.json:1622-1634`: the variant enumeration, 8 names. A layout family that needs no further variant leaves it.

### Swift: the enumeration, 1

- `PhysicalProtocolID` at `Protocol/Classification/ProtocolClassifier.swift:7`. It has 19 cases, `:9` (`hidDescriptor`) to `:49` (`nintendoWii`), and derives `CaseIterable` and `Codable`.

### Swift: `switch` on a family value, 7

Four have no `default`. An added case does not compile until each lists it.

| # | `file:line` | Switch |
|---|-------------|--------|
| 1 | `Protocol/Classification/ProtocolClassifier.swift:73` | `generalSessionFields`; the listing case is at `:77-79` |
| 2 | `Protocol/Catalog/ProtocolDriverRegistry.swift:196` | `makeUnobservedDriver`; the layout families are at `:209` |
| 3 | `Protocol/Catalog/ProtocolDriverRegistry+InterfaceContract.swift:147` | `acceptsInterfaceClass`; the listing case is at `:157-160` |
| 4 | `Sources/OpenJoystickDriverKit/Output/Profiles/VirtualIdentityPresentation.swift:67` | `physicalPresentation`; the listing case is at `:70-72` |

Three have a `default`. A layout family needs no edit there.

| # | `file:line` | Switch |
|---|-------------|--------|
| 5 | `Protocol/Classification/ProtocolClassifier.swift:55` | `sessionFields` |
| 6 | `Protocol/Classification/ProtocolClassifier.swift:89` | `readParameters` |
| 7 | `Protocol/Classification/ProtocolClassifier.swift:160` | `readsRecordRumbleTemplate` |

Switches on a variant value, not a family: `Protocol/Catalog/ProtocolDriverRegistry.swift:282`, `:336`, and `Sources/OpenJoystickDriverKit/Device/Pipeline/DevicePipeline+Lifecycle.swift:254`.

### Swift: lists and comparisons that name a family case

Three lists:

- `Protocol/Classification/ProtocolClassifier.swift:517`: `[.xboxXUSB, .xboxGIP]`.
- `Protocol/Catalog/ProtocolDriverRegistry+HIDRoles.swift:78`: the three Valve families.
- `Sources/OpenJoystickDriverKit/Diagnostics/ControllerRecordProbePlan.swift:61`: `probeableProtocols`, `[.xboxGIP, .xboxXUSB]`.

Single-family comparisons (none lists a layout family):

- `.hidDescriptor`: `ProtocolClassifier.swift:344`, `:417`, `:432`, `:436`, `:486`; `ProtocolDriverRegistry.swift:145`; `Protocol/Drivers/Generic/HIDDescriptorDriver.swift:62`; `Protocol/Catalog/ControllerRecordDraft.swift:57`; `Protocol/Catalog/ControllerRecordDraft+SDL.swift:57`, `:65`.
- `.xboxGIP`: `ProtocolDriverRegistry.swift:117`; `ProtocolClassifier+DeviceSignature.swift:8`; `ControllerRecordProbePlan.swift:55`; `Protocol/Catalog/TransportProfiles.swift:74-75`; `Sources/OpenJoystickDriverUSB/Configuration.swift:45`.
- `.xboxXUSB`: `ProtocolDriverRegistry+InterfaceContract.swift:26`; `Protocol/Classification/ProtocolDescription+Validation.swift:74`.
- `.vendorGameSir`: `ProtocolDriverRegistry+InterfaceContract.swift:133`.
- `.nintendoSwitch2`: `Protocol/Catalog/ControllerRecordSet.swift:80`.
- `.valveSteamTriton`: `ProtocolDriverRegistry+HIDRoles.swift:47`.

### Swift: every file that names a family case, 32

Found with a search for `\.(hidDescriptor|...|nintendoWii)\b` over `Sources/**/*.swift`. Counts in brackets are matching lines.

Outside `Protocol/Drivers/`, 13 files:

1. `Sources/OpenJoystickDriverUSB/Configuration.swift` [1]
2. `Sources/OpenJoystickDriverKit/Output/Profiles/VirtualIdentityPresentation.swift` [5]
3. `Sources/OpenJoystickDriverKit/Diagnostics/ControllerRecordProbePlan.swift` [2]
4. `Protocol/Catalog/ControllerRecordDraft+SDL.swift` [2]
5. `Protocol/Catalog/ControllerRecordDraft.swift` [1]
6. `Protocol/Catalog/ControllerRecordSet.swift` [1]
7. `Protocol/Catalog/ProtocolDriverRegistry+HIDRoles.swift` [2]
8. `Protocol/Catalog/ProtocolDriverRegistry+InterfaceContract.swift` [9]
9. `Protocol/Catalog/ProtocolDriverRegistry.swift` [19]
10. `Protocol/Catalog/TransportProfiles.swift` [2]
11. `Protocol/Classification/ProtocolClassifier+DeviceSignature.swift` [1]
12. `Protocol/Classification/ProtocolClassifier.swift` [29]
13. `Protocol/Classification/ProtocolDescription+Validation.swift` [1]

Inside `Protocol/Drivers/`, 19 files. Each names its own family to read that family's description. A layout family adds none.

14. `Generic/HIDDescriptorDriver.swift` [1]
15. `Nintendo/Switch1Driver.swift` [3]
16. `Nintendo/Switch2Driver.swift` [6]
17. `Nintendo/WiiDriver.swift` [5]
18. `Sony/DualSenseDriver+Reports.swift` [3]
19. `Sony/DualSenseDriver.swift` [1]
20. `Sony/DualShock4Driver+Reports.swift` [1]
21. `Sony/DualShock4Driver.swift` [2]
22. `Sony/SixaxisDriver.swift` [2]
23. `Valve/SteamControllerDriver+Session.swift` [3]
24. `Valve/SteamDeckDriver.swift` [5]
25. `Valve/SteamTritonDriver.swift` [6]
26. `Vendor/GameSirDriver+Protocol.swift` [3]
27. `Vendor/GameSirDriver.swift` [3]
28. `Vendor/NVIDIAShieldDriver.swift` [2]
29. `Vendor/PS3ThirdPartyDriver.swift` [1]
30. `Xbox/GIPDriver+Decoding.swift` [1]
31. `Xbox/GIPDriver.swift` [8]
32. `Xbox/XUSBDriver.swift` [5]

The design text says 15 files (`openspec/changes/0-6-0-alpha-3/design.md:128`). The search above finds 32. The two counts use different patterns, and this list is the exact one.

### Other closed places

| # | Place | `file:line` |
|---|-------|-------------|
| 1 | Description file, two copies. `Resources/Protocols/` and `Sources/OpenJoystickDriverKit/Resources/Protocols/` each hold the same 19 files (`cmp` finds no difference). | `<stem>.json` in both; stem from `Protocol/Classification/ProtocolClassifier.swift:105` |
| 2 | Display-name key `term.protocolFamily.<segment>`, one per family, in each of 22 `*.lproj/Localizable.strings` (19 lines each, counted). | `Protocol/Classification/ProtocolClassifier.swift:114`; `Tests/OpenJoystickDriverKitTests/Localization/LocalizationTests.swift:401-408` requires the key set to equal the family set |
| 3 | Brand-name allowlist of keys equal in every locale. | `Tests/OpenJoystickDriverKitTests/Localization/LocalizationCatalogAudit.swift:9-17` |
| 4 | Table of variants per family, compared with `allCases`. | `Tests/OpenJoystickDriverKitTests/Protocol/Classification/ProtocolDescriptionTests.swift:1020`; loops over `allCases` at `:55`, `:61`, `:334`, `:957` |

## What stays in source for one added layout family

The document supplies the endpoints, interface signatures, `recordSections`, `defaults.input.layouts`, and rumble template. These remain:

| Category | Edits |
|----------|-------|
| Schema enumerations | 2 |
| Enumeration case | 1 |
| Exhaustive switches | 4 (one of them also takes the family into the layout case list at `ProtocolDriverRegistry.swift:209`) |
| Description file copies | 2 |
| Localization catalogs | 22 files, 1 line each |
| Tests that list every family | 2 (`LocalizationTests.swift:401`, `ProtocolDescriptionTests.swift:1020`) |

## Headline numbers

- Closed schema enumerations: 2. Schema `$ref` places that follow: 4.
- Enumeration declarations in Swift: 1 (19 cases).
- `switch` on a family value: 7 (4 exhaustive, 3 with `default`).
- Lists of family cases: 3.
- Swift files naming a family case: 32 (13 outside the drivers, 19 inside).
- Copies of a description file per family: 2. Localization catalogs per family: 22.
