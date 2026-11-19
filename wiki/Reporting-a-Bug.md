# Reporting a Bug

Found a bug? Tell the maintainer on the [issue tracker](https://github.com/xsyetopz/OpenJoystickDriver/issues). Give enough detail that they can make the same bug happen on their own Mac.

- **Who:** anyone who found a bug.
- **What:** what to put in a report so the maintainer can repeat the bug.
- **When:** after you checked [Known Issues](Known-Issues.md) and [Troubleshooting](Troubleshooting.md).
- **Where:** the [issue tracker](https://github.com/xsyetopz/OpenJoystickDriver/issues).
- **Why:** a bug the maintainer can repeat is a bug they can fix.
- **How:** write the steps, then attach a support report from `ojd diagnose`.

```mermaid
flowchart LR
    bug[Bug] -->|"steps to repeat it"| issue[Issue]
    rep["ojd diagnose"] -->|"support report"| issue
    issue -->|"maintainer repeats it"| fix[Fix]
```

## What To Include

1. The controller model, the connection (USB, Bluetooth, or dongle), and the controller's ID, such as `045E:02D1`. See [Finding Your Controller ID](Connecting-Controllers.md#finding-your-controller-id).
2. The macOS version and the OJD version. Choose OpenJoystickDriver > **About OpenJoystickDriver**.
3. What you did, what you expected, and what happened.
4. A support report.
5. Logs, if the app quit or showed an error.

With a tester build, attach `OpenJoystickDriver-TESTER-BUILD.txt` from the DMG. Name the build you tested and any later build that fixed the problem.

## Create a Support Report

Run this in Terminal. It needs the [`ojd` command](Command-Line.md#run-a-command).

```shell
ojd diagnose --output support-report.json
```

Or choose **Help** > **Copy Support Report**.

![The Help menu. A red arrow points to Copy Support Report, which copies facts about your setup without serial numbers or paths](../docs/screenshots/steps/copy-support-report.png)

The report lists facts about your Mac, OJD, and your controllers. It leaves out serial numbers, file paths, and packet contents, but it includes your controllers' product names. Read it before you share it.

Controller stutters or lags? Run the command right after it happens, so the report holds timings of the last moments.

## Run a Guided Check

If a control doesn't respond, or acts as another control, run **Guided Check** in the Input Test window. Or run `ojd controller check <controller> --json > check.json`. The check asks you to move each control in turn.

When it ends, click **Open Issue**. OJD saves the result and opens the support form with your details filled in. Attach the saved file. See [Testing a Controller](Testing-a-Controller.md#guided-check).

If every control responded, **Validate** offers the result as a community validation.

## Get the Logs

The log is OJD's diary, with one line for each thing it did. Open **Activity** and choose **Log**, or choose **Help** > **Activity Log**.

![The Activity area with the log blurred for privacy. A red arrow points to the Log and Diagnostics switch. A second arrow points to the Copy, Save, and Show in Finder buttons, which share the log in a bug report](../docs/screenshots/steps/activity-overview.png)

Or run:

```shell
ojd log show --lines 200
```

Logs may contain device names and paths. Read them before you share them.

## Capture Packets

A controller talks to the Mac in small messages called packets. A packet capture records them, like a voice memo of the controller. If a controller works wrongly or not at all, attach one. Run this while you press each control, and write down the order you pressed them in:

```shell
ojd controller capture <controller> --duration 10 --json > capture.jsonl
```

Attach the file. Check it before you share it.

## Gather Data From Other Systems

The maintainer owns only a few controllers, so for every other model your files are all they have. Windows and Linux show things macOS hides:

- the controller's descriptors, a built-in list of its buttons and sticks
- the first packets it sends after you plug it in
- which driver runs it

Attach each file you can make, and say which mode or switch setting the controller was in.

On macOS:

- The HID report descriptor: `ioreg -r -c IOHIDDevice -l -w0 > ioreg-hid.txt`. The `ReportDescriptor` line of your controller is the descriptor.
- The USB tree: `ioreg -p IOUSB -l -w0 > ioreg-usb.txt`.
- A draft record: `ojd record draft <controller> > draft.plist`, while you press each control.
- Bluetooth packets: PacketLogger from Apple's Additional Tools for Xcode.

On Linux:

- The descriptors: `sudo lsusb -v -d VVVV:PPPP > lsusb.txt`.
- The HID report descriptor and reports: `sudo hid-recorder` from [hid-tools](https://gitlab.freedesktop.org/libevdev/hid-tools). Run it without arguments to list the devices, then pick yours and press each control.
- USB packets: `sudo modprobe usbmon`, then capture the `usbmonX` interface of the controller's bus in Wireshark, from before you plug the controller in. Save it as `.pcapng`.
- The kernel log of the plug-in: `sudo dmesg | tail -50`, and the name of the driver that bound, such as `xpad` or `hid-generic`.

On Windows:

- The hardware IDs: **Device Manager** > the controller > **Properties** > **Details** > **Hardware Ids**.
- The descriptors: a dump from USB Device Tree Viewer.
- USB packets: [USBPcap](https://desowin.org/usbpcap/) with Wireshark. Start the capture on the controller's root hub, then plug the controller in, so the file holds the descriptors and the startup packets.

Also collect what others have found about the controller, with links:

- Its entry in Linux drivers (`xpad.c`, `hid-*.c`), SDL (`controller_list.h`, SDL_GameControllerDB), Steam Input, or other driver projects.
- Issues, forum threads, and reviews about it, with the firmware version and mode they name.
- The maker's manual page on modes and button combinations.
- The firmware version, and the app that updates it.

Links to GPL drivers are welcome. OJD takes facts from them, such as IDs and byte values, and writes its own code.

## Further Reading

- [Known issues](Known-Issues.md)
- [Command reference](Command-Reference.md)
- [Supported controllers](Supported-Controllers.md)
