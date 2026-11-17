# Installer Format: DMG or Package

OJD ships as a DMG because a package cannot do the steps that fail during a driver update, and Apple advises against the one step a package could add.

## What Fails During an Update

After an update of the Xbox USB driver while a matched controller is connected, macOS keeps the replaced driver until the controller reconnects or the Mac restarts. `systemextensionsctl list` then shows two lines for `com.openjoystickdriver.XboxUSBDevice`: the replaced version as `[terminated waiting to uninstall on reboot]`, often first, and the new one as `[activated enabled]`. `ExtensionProbe.installedFacts` reads the `[activated enabled]` line, so the repair banner leaves after one repair (`ProbeTests.readsInstalledVersionFromActiveLineWhenUpgradeLeavesOldLine`).

An Apple engineer states that an upgrade needs no deactivation of the old version, only a new activation request, and that "some devices will need to be disconnected and re-connected to start using the upgraded dext" ([Apple Developer Forums 677040](https://developer.apple.com/forums/thread/677040)).

## What a Package Can and Cannot Do

| Step | Package | DMG |
| --- | --- | --- |
| Put exactly one copy in `/Applications` | Yes, with `BundleIsRelocatable` set to false in the component plist | The user drags the app; a second copy can stay elsewhere |
| Quit the running app before the copy | Yes, in a `preinstall` script | The user quits it |
| Activate the driver | Not advised: Quinn calls activation from a package script "something I actively recommend against" ([Apple Developer Forums 750923](https://developer.apple.com/forums/thread/750923)) | The app's **Repair Xbox USB Driver** sends the request |
| Remove the replaced driver | No: the system extension store is SIP-protected | No |
| End the reboot-deferred state | No: it ends on reconnect or restart | No |
| Keep privacy grants across a signing change | No | No |

Apple's activation check requires the app in an Applications directory and the extension in `Contents/Library/SystemExtensions` ([Installing System Extensions and Drivers](https://developer.apple.com/documentation/systemextensions/installing-system-extensions-and-drivers)). Both formats meet it when the user follows the steps in `wiki/Updating-and-Uninstalling.md`.

For managed Macs, Apple's route is MDM: the `com.apple.system-extension-policy` payload allows the team ID, and `com.apple.TCC.configuration-profile-policy` grants privacy access. Neither needs a package script.

## Prototype

A package built on 2026-11-18 with `pkgbuild --component-plist` (`BundleIsRelocatable` false) and `productsign` with the Developer ID Installer identity was 42.6 MB and carried a trusted timestamp. `ditto` copied an AppleDouble file (`._com.openjoystickdriver.XboxUSBDevice.dext`) into the payload; a package script must copy with `ditto --norsrc` or strip `._*` files. The package was not installed, because installing needs `sudo`, so its install behavior is not verified.

`pkgbuild(1)` sets `BundleIsRelocatable` to false by default only for packages built on macOS 27 or later, so a script sets it explicitly.

## Decision

Keep the DMG. A package would add a second signing identity, a notarization of its own and an install script for one benefit, a single copy in `/Applications`, that the update steps already ask for. Revisit when a user report shows a second copy of the app as the cause of a failure.
