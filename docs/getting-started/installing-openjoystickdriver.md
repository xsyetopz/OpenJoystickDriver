# Installing OpenJoystickDriver

Install OpenJoystickDriver in the Applications folder, start it, and check the login item.

## Requirements

- macOS 10.15 (Catalina) or later.
- A Mac with Apple silicon or an Intel processor. The app contains both.
- A controller. For more information, see [Supported controllers](../connecting-controllers/supported-controllers.md).

## Install the app

1. Open the OpenJoystickDriver disk image (`.dmg`).
1. Drag **OpenJoystickDriver.app** onto the **Applications** shortcut in the same window.
1. Eject the disk image.
1. Open **OpenJoystickDriver** from the Applications folder.

Release builds use the name `OpenJoystickDriver-VERSION-macOS.dmg`. Tester builds also contain the file `OpenJoystickDriver-TESTER-BUILD.txt` that lists the build details.

> [!NOTE]
> Keep the app in `/Applications`. The commands that manage the login item and the system extension refuse to run from any other location.

## First start

OJD is a menu-bar app. It has no Dock icon. After it starts, a controller icon appears in the menu bar. Click the icon to open the status menu.

At start, OJD also does these actions:

- On macOS 13 and later, it registers itself as a login item. To turn this off, run the `app login disable` command. Turning off **Start at login** in **Settings** may not last, because OJD registers itself again at the next start. Not verified on a running system. For more information, see [Console and settings](../using-the-app/console-and-settings.md).
- It checks the Xbox USB driver extension. If the extension needs activation, OJD submits one request. macOS may then ask for your approval.

OJD asks for no privacy permission at start. You grant permissions later. For more information, see [Permissions](../permissions-and-security/permissions.md).

## Approve the login item

If macOS asks, allow OJD in **System Settings** > **General** > **Login Items**. Below macOS 13, OJD cannot register a login item. Open the app yourself after you sign in.

## Further reading

- [Quickstart](quickstart.md)
- [Xbox USB driver extension](../connecting-controllers/xbox-usb-driver-extension.md)
- [Updating OpenJoystickDriver](../updating-and-uninstalling/updating-openjoystickdriver.md)
