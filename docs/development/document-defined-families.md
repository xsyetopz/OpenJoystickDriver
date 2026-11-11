# Document-defined protocol families

Scope: how a protocol description document registers a family that the general layout driver runs, with no Swift change. Three built-in families run on it as well: `XboxXID`, `NintendoSwitchInputOnly`, and `VendorFlydigi`.

Paths under `Sources/OpenJoystickDriverKit/Protocol/` are shortened to `Protocol/`.

## What a family is

- `PhysicalProtocolID` (`Protocol/Classification/ProtocolClassifier.swift`) is a string value. The 19 built-in families are its static members, and `allCases` lists only them.
- A documented family is a description document whose `family` is not a built-in name. `PhysicalProtocolID(rawValue:)` accepts its name while `DocumentedProtocolFamilies` holds the description (`Protocol/Classification/DocumentedProtocolFamilies.swift`), and `isDocumented` is true for it.
- The family name is UpperCamelCase: `^[A-Z][A-Za-z0-9]*$`. `controller.schema.json` (`$defs.protocol.properties.family`) and `report.schema.json` (`rejectedCandidate.properties.protocolID`) state the same pattern, and `protocol-description.schema.json` follows the first by `$ref`.

## What a documented description must set

`ProtocolDescription.decode(_:fileName:)` refuses a documented description that:

- has a name that fails the pattern (E5002);
- has a file stem that differs from the family name (E5003);
- has the name of a built-in family, written as the raw name (`XboxGIP.plist`) (E5002);
- sets no `displayName` (E5002), or sets no `defaults.input.layouts` (E5002).

A built-in description sets no `displayName`; its name is the localized `term.protocolFamily.<segment>` string. A documented family takes its display name from the document (`PhysicalProtocolID.displayName(in:)`).

A documented description has no `sessionKeys`, no `presentSessionFields` and no parameters, because those belong to the built-in families that read them (`generalSessionFields`, `sessionFields`, `readParameters`). It declares endpoints, interface signatures, `recordSections`, `defaults.input.layouts`, a rumble template and tuning defaults.

## Where a documented family is loaded from

`ControllerRecordSet.load(userDirectory:)` calls `DocumentedProtocolFamilies.load(besides:)` before it applies any record. It reads, through `DocumentedProtocolFamilies.read(_:package:)`:

- the `.plist` files of the user's `Protocols` folder, beside `Controllers`;
- the `protocols` list of each installed mod package, from its `Protocols/` folder, in package-name order.

The first definition of a name wins, so a later file with that name is refused. A refused file is listed in `ControllerRecordSet.userFiles` with its E5002 or E5003 reason. `ModPackageStore.validate` runs `read` on each listed file and registers the package's families while it validates the package's Controller files.

## Command line

`ojd protocol validate FILE` runs `DocumentedProtocolFamilies.read` and prints the E5002 or E5003 refusal. `ojd protocol install FILE` runs it, then writes the file bytes to `Protocols/FAMILY.plist` beside the user's `Controllers` folder and replaces a file of that name. `ojd protocol list` prints `PhysicalProtocolID.allCases` and `DocumentedProtocolFamilies.load(besides:).families` with their source. `ProtocolStore.controllers` is the folder that tests replace.

## Where a documented family is read

- `ProtocolClassifier.signatures` adds the interface signatures of every documented description.
- `ProtocolDriverRegistry.makeUnobservedDriver` builds `ReportLayoutDriver(describedBy:)` for a documented family, as for the three built-in layout families.
- `ProtocolDriverRegistry.acceptsInterfaceClass` and `PhysicalProtocolID.physicalPresentation` take the `default` branch: a documented family is not raw USB, and its glyph set is generic.

## Closed places that remain

- The 19 built-in families, one description file each in `Resources/Protocols/` and `Sources/OpenJoystickDriverKit/Resources/Protocols/`, and one `term.protocolFamily.<segment>` key per family in each `.lproj`.
- Each driver of a built-in family names that family to read its own description.
