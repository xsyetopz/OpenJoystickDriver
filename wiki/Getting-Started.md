# Getting Started

Learn what OpenJoystickDriver is, install it, and use your first controller.

## Contents

- [About OpenJoystickDriver](#about-openjoystickdriver)
- [Installing OpenJoystickDriver](#installing-openjoystickdriver)
- [Quickstart](#quickstart)
- [Further Reading](#further-reading)

## About OpenJoystickDriver

OpenJoystickDriver (OJD) is a macOS menu-bar app that reads game controllers and shows them to macOS games as a standard controller.

### How It Works

OJD is one bundle, `/Applications/OpenJoystickDriver.app`, with no helper app. It runs in your user session. It reads reports from a physical controller over USB, Bluetooth, or a 2.4 GHz dongle. It then publishes a virtual controller that games and apps can read.

The virtual controller uses one of two profiles. One profile is an Xbox Wireless Controller. The other profile is a generic gamepad. OJD selects one automatically. For more information, see [How games see your controller](Playing-Games.md).

OJD can also remap controls. A profile can send controller input as keyboard, pointer, or scroll events. For more information, see [About profiles](Remapping-Profiles.md).

### What OJD Does Not Need

- OJD does not install a kernel extension.
- OJD does not need you to turn off System Integrity Protection (SIP).
- OJD does not need you to turn off Apple Mobile File Integrity (AMFI).

OJD has one driver extension. Its Xbox USB part serves Xbox One and Xbox Series controllers on USB. Other controllers do not use that part. For more information, see [Xbox USB driver extension](Connecting-Controllers.md).

### What OJD Is Not

- OJD is not a guarantee that every game reads the virtual controller. Some apps that use SDL may not read it. For more information, see [Game and app compatibility](Playing-Games.md).
- OJD is beta software. Some controllers are not tested on real hardware. For more information, see [Supported controllers](Supported-Controllers.md).

## Installing OpenJoystickDriver

Install OpenJoystickDriver in the Applications folder, start it, and check the login item.

### Requirements

- macOS 12 (Monterey) or later.
- A Mac with Apple silicon or an Intel processor. The app contains both.
- A controller. For more information, see [Supported controllers](Supported-Controllers.md).

### Install the App

1. Open the OpenJoystickDriver disk image (`.dmg`).
1. Drag **OpenJoystickDriver.app** onto the **Applications** shortcut in the same window.
1. Eject the disk image.
1. Open **OpenJoystickDriver** from the Applications folder.

Release builds use the name `OpenJoystickDriver-VERSION-macOS.dmg`. Tester builds also contain the file `OpenJoystickDriver-TESTER-BUILD.txt` that lists the build details.

> [!NOTE]
> Keep the app in `/Applications`. The commands that manage the login item and the system extension refuse to run from any other location.

### First Start

OJD is a menu-bar app. It has no Dock icon. After it starts, a controller icon appears in the menu bar. Click the icon to open the status menu.

At start, OJD also does these actions:

- On macOS 13 and later, it registers itself as a login item. To turn this off, run the `app login disable` command. Turning off **Start at login** in **Settings** may not last, because OJD registers itself again at the next start. Not verified on a running system. For more information, see [Console and settings](Using-the-App.md#console-and-settings).
- It checks the OJD driver extension. If the extension needs activation, OJD submits one request. macOS may then ask for your approval.

OJD asks for no privacy permission at start. You grant permissions later. For more information, see [Permissions](Permissions-and-Security.md#permissions).

### Approve the Login Item

If macOS asks, allow OJD in **System Settings** > **General** > **Login Items**. Below macOS 13, OJD cannot register a login item. Open the app yourself after you sign in.

## Quickstart

Use your first controller with OpenJoystickDriver in five steps.

### Before You Begin

Install the app first. For more information, see [Installing OpenJoystickDriver](#installing-openjoystickdriver).

### Steps

1. Install and open OpenJoystickDriver from the Applications folder.
1. Grant access.
   1. Click the controller icon in the menu bar.
   1. If the menu shows **Request Access...**, click it. Allow OpenJoystickDriver in the **Input Monitoring** and **Accessibility** lists.
   1. Open the app window. On the **Overview** pane, click **Restart OpenJoystickDriver** if it appears.
1. Connect your controller with USB, Bluetooth, or a 2.4 GHz dongle.
1. Check the controller.
   1. Open the **Controllers** pane.
   1. Select your controller.
   1. Click **Open Input Test...**.
   1. Press buttons and move sticks. The **Live input** group shows each control.
1. Play a game. The game reads the virtual controller that OJD publishes.

If step 4 shows no input, see [Controller not detected](Troubleshooting.md). If the game shows no input, see [Game does not see the controller](Troubleshooting.md).

## Further Reading

- [Security model](Permissions-and-Security.md#security-model)
- [Permissions](Permissions-and-Security.md#permissions)
- [Testing a controller](Testing-a-Controller.md)
- [Supported controllers](Supported-Controllers.md)
- [Xbox USB driver extension](Connecting-Controllers.md)
- [Updating OpenJoystickDriver](Updating-and-Uninstalling.md)
