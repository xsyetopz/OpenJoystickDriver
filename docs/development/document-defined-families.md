# Document-Defined Protocol Families

A protocol family is a group of controllers that speak the same language. Usually a family needs Swift code. A protocol description document lets you add a family with only a settings file, which a shared general-purpose driver (the general layout driver) reads; XboxXID and NintendoSwitchInputOnly use it too. The app bundles one documented family, VendorFlydigi.

## What a Family Is

- `PhysicalProtocolID` (ProtocolClassifier.swift) is a string value. Its 18 static members are the built-in families; `allCases` lists only them.
- A documented family is a description whose `family` is not a built-in name, held by `DocumentedProtocolFamilies` (DocumentedProtocolFamilies.swift). `PhysicalProtocolID(rawValue:)` accepts the name; `isDocumented` is true.
- The name is UpperCamelCase: `^[A-Z][A-Za-z0-9]*$`. controller.schema.json (`$defs.protocol.properties.family`) and report.schema.json (`rejectedCandidate.properties.protocolID`) state it; protocol-description.schema.json uses `$ref`.

## What a Documented Description Must Set

`ProtocolDescription.decode(_:fileName:)` refuses a documented description with:

- a name that fails the pattern (E5002);
- a file stem that differs from the family name (E5003);
- the raw name of a built-in family, such as `XboxGIP.plist` (E5002);
- no `displayName` or no `defaults.input.layouts` (E5002).

A built-in family's name is the localized `term.protocolFamily.<segment>` string; a documented family's comes from `displayName` (`PhysicalProtocolID.displayName(in:)`).

It has no `sessionKeys`, `presentSessionFields`, or parameters (built-in families own them). It declares endpoints, interface signatures, `recordSections`, `defaults.input.layouts`, a rumble template, and tuning defaults.

## Where a Documented Family Is Loaded From

`ControllerRecordSet.load(userDirectory:)` calls `DocumentedProtocolFamilies.load(besides:)` before any record. `read(_:package:)` reads, in order:

- the plist files in the user's `Protocols` folder, next to Controllers;
- the `protocols` list of each installed mod package, in package-name order;
- bundled `Resources/Protocols/` files whose stem is a family name (VendorFlydigi.plist); built-in files are kebab-case, so the two do not mix.

The first file to define a name wins. A later file is refused and listed in `ControllerRecordSet.userFiles` with its E5002 or E5003 reason. A user or package file replaces the bundled definition without a refusal: the bundled D7D7:0041 record binds VendorFlydigi, so a user `Protocols/VendorFlydigi.plist` changes how it decodes. `ModPackageStore.validate` runs `read` on each listed file.

## Command Line

| Command | Effect |
| --- | --- |
| `ojd protocol validate FILE` | runs read, and prints why it refuses the file |
| `ojd protocol install FILE` | checks it, then writes `Protocols/FAMILY.plist` next to the user's Controllers folder, replacing a file with that name |
| `ojd protocol list` | prints built-in and documented families with source BuiltIn, Bundled, User, or Package |

Tests swap in their own folder for `ProtocolStore.controllers`.

## Where a Documented Family Is Read

| Symbol | Behavior |
| --- | --- |
| `ProtocolClassifier.signatures` | adds its interface signatures |
| `ProtocolDriverRegistry.makeUnobservedDriver` | builds `ReportLayoutDriver(describedBy:)`, as for the two built-in layout families |
| `acceptsInterfaceClass`, `physicalPresentation` | use the default: not raw USB, and the generic button pictures |

## What Still Needs Swift Code

- The 18 built-in families: one description each in `Resources/Protocols/` and `Sources/OpenJoystickDriverKit/Resources/Protocols/`, and one `term.protocolFamily.<segment>` key each per .lproj folder.
- Each built-in driver names its own family.
