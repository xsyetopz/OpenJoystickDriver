# Frequently asked questions

This article gives short answers to common OpenJoystickDriver (OJD) questions.

## Do I need to disable SIP or AMFI?

No. Never disable System Integrity Protection (SIP) or AMFI for OJD. OJD needs neither, and this applies to every build type.

## Do I need the system extension?

Only for Xbox One and Xbox Series controllers on USB with these product IDs: `045E:02D1`, `02DD`, `02E3`, `02EA`, `0B00`, `0B0A`, and `0B12`. Other controllers do not need it. For more information, see [Xbox USB driver extension](../connecting-controllers/xbox-usb-driver-extension.md).

## Can I edit controller data or add my own controller?

Not in the installed app. The controller catalog is inside the app, and a change breaks its signature. The maintainer plans a scripting API for a later beta. It is not scheduled. You can edit and share [profiles](../remapping-controls/about-profiles.md). To ask for a new controller, send a bug report.

## Where is my data stored?

Profiles are in `~/Library/Application Support/OpenJoystickDriver/RemappingProfiles.json`. Logs are in `~/Library/Logs/OpenJoystickDriver/`. Settings are in the `com.openjoystickdriver` preferences domain. For more information, see [Uninstalling OpenJoystickDriver](../updating-and-uninstalling/uninstalling-openjoystickdriver.md).

## Why does my controller work in one app but not another?

Each app reads controllers with its own API. Some apps that use SDL cannot read the virtual controller. For more information, see [Game does not see the controller](game-does-not-see-the-controller.md).

## Does OJD work with Steam?

Not verified to work. One tester saw a phantom controller with no input when Steam read the Xbox virtual profile. With the generic profile, Steam was erratic and slow to respond. For more information, see [Game and app compatibility](../playing-games/game-and-app-compatibility.md).

## Why is my clone controller different?

A clone or fake controller may use different chips and report different data than the original. OJD may work with it, may partly work, or may not work. For more information, see [Clone and fake controllers](../connecting-controllers/clone-and-fake-controllers.md).

## When do I get a fix?

A fix arrives in the next tester build or release. To get it sooner, build the branch yourself. `CHANGELOG.md` lists what each build contains. For more information, see [Updating OpenJoystickDriver](../updating-and-uninstalling/updating-openjoystickdriver.md).

## Do I need Xcode?

Not to use OJD. To build it, you need the Swift compiler and the Xcode command-line tools. A few build steps need full Xcode. Not verified: building with only the Command Line Tools. For more information, see [Build options and limits](../building-from-source/build-options-and-limits.md).

## Further reading

- [Known issues](known-issues.md)
- [Reporting a bug](reporting-a-bug.md)
