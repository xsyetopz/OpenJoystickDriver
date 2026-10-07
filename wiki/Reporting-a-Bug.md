# Reporting a Bug

This page explains what to include in a bug report so the maintainer can reproduce the problem.

> **Note:** This page applies to OpenJoystickDriver 0.6.0-alpha.1 and later. Version 0.5.0-beta.4 and earlier do not have all of the features on this page.

Report issues in the [issue tracker](https://github.com/xsyetopz/OpenJoystickDriver/issues).

## What To Include

1. The controller model, the connection (USB, Bluetooth, or dongle), and the VID:PID. For more information, see [Finding your controller ID](Connecting-Controllers.md).
1. The macOS version and the OJD version.
1. What you did, what you expected, and what happened.
1. A support report.
1. Logs, if the app crashed or showed an error.

If you use a tester build, attach `OpenJoystickDriver-TESTER-BUILD.txt` from the DMG. Say which build you tested. If a newer build fixed the problem, name that build.

## Create a Support Report

Run the following command. It runs every check and writes the report to the file you name.

```shell
ojd diagnose --bundle support-report.json
```

You can also click **Copy Support Report** on the **Xbox USB Driver** card in **Overview**. The app copies the report to the clipboard and shows no confirmation.

The report leaves out serial numbers, file paths, packet payloads, and HID location IDs. It includes controller product names. Read the report before you share it.

## Get the Logs

Open the Console pane and click **Copy All**. To open the pane, use the **Help** submenu of the menu bar item. Or run the following command.

```shell
ojd log show --lines 200
```

Logs may contain device names, identifiers, and paths. Read them before you share them.

## Capture Packets

For a controller that is wrong or missing, attach a packet capture. Find the controller's ID with `ojd controller list`, then run the following command while you press each control. It needs the [`ojd` command](Command-Line.md).

```shell
ojd controller capture <controller> --duration 10 --json > capture.jsonl
```

The command prints one packet per line to Terminal. The `>` redirect saves the output to a file in the current folder. Attach the file to your report.

Say which controls you pressed and in what order. Packet contents differ by controller. Check the file before you share it.

## Further Reading

- [Known issues](Known-Issues.md)
- [Command reference](Command-Reference.md)
- [Supported controllers](Supported-Controllers.md)
