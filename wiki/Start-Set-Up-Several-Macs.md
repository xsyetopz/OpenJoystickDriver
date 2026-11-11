# Start: set up OJD on several Macs

Install OJD on more than one Mac by hand, and copy your profiles and controller records between them.

This page covers what the license allows, what Apple documents for macOS, and how to repeat the setup on each Mac.

## What the license allows

OJD is under the PolyForm Noncommercial License 1.0.0, in the file `LICENSE` at the repository root. The license says:

- "Any noncommercial purpose is a permitted purpose."
- "Personal use for research, experiment, and testing for the benefit of public knowledge, personal study, private entertainment, hobby projects, amateur pursuits, or religious observance, without any anticipated commercial application, is use for a permitted purpose."
- "Use by any charitable organization, educational institution, public research organization, public safety or health organization, environmental protection organization, or government institution is use for a permitted purpose regardless of the source of funding or obligations resulting from the funding."
- It grants "a copyright license to distribute copies of the software", and requires that anyone who gets a copy from you also gets "a copy of these terms or the URL for them" and the `Required Notice:` lines.

The license text names no number of copies or computers. It does not grant commercial use. [COMMERCIAL.md](../COMMERCIAL.md) says that use in a product or for a business needs a separate written license from the maintainer. Read the license yourself to decide whether your use is permitted.

## What macOS documents

Apple documents these steps for one Mac. Each Mac needs them.

- Allow a system extension: [If you get an alert about a system extension on Mac](https://support.apple.com/en-us/120363). Apple says you might be able to allow the extension in Login Items & Extensions settings on macOS Sequoia 15 or later, or in Privacy & Security settings on earlier versions.
- Allow an app to read your keyboard, mouse, or trackpad: [Control access to input monitoring on Mac](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac). Apple says to open **System Settings**, click **Privacy & Security**, click **Input Monitoring**, and turn the app on.
- Allow an app to control the Mac: [Allow accessibility apps to access your Mac](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac). Apple says to open **System Settings**, click **Privacy & Security**, click **Accessibility**, and turn the app on.

For what OJD asks for and when, see [Permissions and security](Permissions-and-Security.md#permissions).

## Steps on each Mac

1. Install OJD from the disk image, as in [Start: play a game with a controller](Start-Play-a-Game.md).
2. Grant **Input Monitoring** and **Accessibility** in the **Access** area, and click **Restart OpenJoystickDriver** if it shows. See [Grant Input Monitoring and Accessibility](Permissions-and-Security.md#grant-input-monitoring-and-accessibility).
3. If you use an Xbox controller on USB, approve the Xbox USB driver. See [Xbox USB driver extension](Connecting-Controllers.md#xbox-usb-driver-extension).
4. Check the Mac: run `ojd status`.

## Copy your setup to another Mac

On the first Mac, export each profile:

```shell
ojd profile export PROFILE --output FILE.plist
```

On another Mac, import it:

```shell
ojd profile import FILE.plist
```

In the app, use **Export Profile...** and **Import Profile...** in the **File** menu. To copy a controller record or a mod, run `ojd record install FILE` or `ojd mod install FOLDER` on each Mac. See [Importing and exporting profiles](Remapping-Profiles.md#importing-and-exporting-profiles).

## Further reading

- [Updating and uninstalling](Updating-and-Uninstalling.md)
- [Command line](Command-Line.md)
- [Security model](Permissions-and-Security.md#security-model)
