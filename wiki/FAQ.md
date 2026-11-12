# Frequently Asked Questions

This page gives short answers to common OpenJoystickDriver (OJD) questions.

## Do I Need to Disable SIP or AMFI?

No. Never disable System Integrity Protection (SIP) or AMFI for OJD. OJD needs neither, and this applies to every build type.

## Do I Need the Xbox USB Driver?

You approve the [Xbox USB driver](Glossary.md#terms) once. It is only for Xbox One and Xbox Series controllers on USB with these product IDs: `045E:02D1`, `02DD`, `02E3`, `02EA`, `0B00`, `0B0A`, and `0B12`. Other controllers do not need it. For more information, see [Xbox USB driver](Connecting-Controllers.md).

## Can I Edit Controller Data or Add My Own Controller?

Not inside the app: the controller catalog is part of the app bundle, and a change breaks its signature. A mod adds a controller record or patches one without touching the bundle; see [Writing controller mods](Writing-Controller-Mods.md). You can edit and share [profiles](Remapping-Profiles.md). To ask for a new controller, send a bug report.

## Where Is My Data Stored?

[Profiles](Glossary.md#terms) are files in `~/Library/Application Support/OpenJoystickDriver/Profiles/`, and the active profiles are listed in `~/Library/Application Support/OpenJoystickDriver/ActiveProfiles.plist`. Logs are in `~/Library/Logs/OpenJoystickDriver/`. Settings are in the `com.openjoystickdriver` preferences domain. For more information, see [Uninstalling OpenJoystickDriver](Updating-and-Uninstalling.md).

## Why Does My Controller Work in One App but Not Another?

Each app reads controllers with its own API. Some apps that use SDL cannot read the [virtual gamepad](Glossary.md#terms). For more information, see [Game does not see the controller](Troubleshooting.md#game-does-not-see-the-controller).

## Does OJD Work with Steam?

Yes, with the Xbox [virtual gamepad kind](Glossary.md#terms) (`SDLCompatible`): the maintainer saw Steam read every control and move the rumble motors on macOS 27. One tester saw a phantom controller with no input when Steam read that kind. With the generic kind, Steam was erratic and slow to respond. For more information, see [Game and app compatibility](Playing-Games.md).

## Why Is My Clone Controller Different?

A clone or fake controller may use different chips and report different data than the original. OJD may work with it, may partly work, or may not work. For more information, see [Clone and fake controllers](Supported-Controllers.md).

## When Do I Get a Fix?

A fix arrives in the next tester build or release. To get it sooner, build the branch yourself. `CHANGELOG.md` lists what each build contains. For more information, see [Updating OpenJoystickDriver](Updating-and-Uninstalling.md).

## Do I Need Xcode?

Not to use OJD. To build it, you need the Swift compiler and the Xcode command-line tools. A few build steps need full Xcode. Not verified: building with only the Command Line Tools. For more information, see [Build options and limits](Building-from-Source.md).

## Further Reading

- [Known issues](Known-Issues.md)
- [Reporting a bug](Reporting-a-Bug.md)
