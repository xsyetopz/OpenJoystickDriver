# Installer Format: DMG or Package

Why OJD comes as a disk image (DMG) you drag to Applications, and not as an installer package (`.pkg`): a package can't do the steps that go wrong when a driver updates.

## What Fails During an Update

With a controller connected, macOS keeps the old Xbox USB driver until the controller reconnects or the Mac restarts. `systemextensionsctl list` shows two lines for `com.openjoystickdriver.XboxUSBDevice`. The old one reads `[terminated waiting to uninstall on reboot]`. The new one reads `[activated enabled]`.

`ExtensionProbe.installedFacts` reads the `[activated enabled]` line, so the repair banner goes away after one repair. While the old line is listed, `ExtensionStatus.replacedVersionPending` is true, and Settings and `ojd transport-extension status` say to reconnect or restart.

Apple confirms "some devices will need to be disconnected and re-connected" ([Apple Developer Forums 677040](https://developer.apple.com/forums/thread/677040)).

## What a Package Can and Cannot Do

| Step | Package | DMG |
| --- | --- | --- |
| Put exactly one copy in `/Applications` | Yes, with `BundleIsRelocatable` set to false in the component plist | The user drags the app; a second copy can stay elsewhere |
| Quit the running app before the copy | Yes, in a `preinstall` script | The user quits it |
| Turn on the driver | Apple advises against it: Quinn calls activation from a package script "something I actively recommend against" ([Apple Developer Forums 750923](https://developer.apple.com/forums/thread/750923)) | The app's **Repair Xbox USB Driver** sends the request |
| Remove the replaced driver | No: the system extension store is SIP-protected | No |
| End the wait for a restart | No: it ends on reconnect or restart | No |
| Keep privacy grants across a signing change | No | No |

Activation requires the app in an Applications directory and the extension in `Contents/Library/SystemExtensions` ([Installing System Extensions and Drivers](https://developer.apple.com/documentation/systemextensions/installing-system-extensions-and-drivers)). Both formats pass if the user follows `wiki/Updating-and-Uninstalling.md`.

On managed Macs, MDM does this: `com.apple.system-extension-policy` allows the team ID, and `com.apple.TCC.configuration-profile-policy` grants privacy access. Neither needs a package script.

## Test Package

A package built on 2026-11-18 (`pkgbuild --component-plist`, `productsign`) was 42.6 MB with a trusted timestamp.

- `ditto` copied an AppleDouble file (`._com.openjoystickdriver.XboxUSBDevice.dext`) into the payload. A package script must use `ditto --norsrc` or strip `._*` files.
- Not checked: what installing does. Installing needs `sudo`.
- `pkgbuild(1)` defaults `BundleIsRelocatable` to false only on macOS 27 or later, so set it explicitly.

## Decision

Keep the DMG. A package needs another signing identity, its own notarization, and an install script. Its only gain is making sure there's one copy in `/Applications`, and the update steps already cover that. Look at this again if a failure is ever caused by a second copy.
