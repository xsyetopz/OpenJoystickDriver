# Reporting a bug

This article explains what to include in a bug report so the maintainer can reproduce the problem.

Report issues in the [issue tracker](https://github.com/xsyetopz/OpenJoystickDriver/issues).

## What to include

1. The controller model, the connection (USB, Bluetooth, or dongle), and the VID:PID. For more information, see [Finding your controller ID](../connecting-controllers/finding-your-controller-id.md).
1. The macOS version and the OJD version.
1. What you did, what you expected, and what happened.
1. A support report.
1. Logs, if the app crashed or showed an error.

If you use a tester build, attach `OpenJoystickDriver-TESTER-BUILD.txt` from the DMG. Say which build you tested. If a newer build fixed the problem, name that build.

## Create a support report

Run the following command. It runs every check and writes the report to the file you name.

```shell
ojd diagnose --bundle support-report.json
```

You can also click **Copy Support Report** on the **Xbox USB Driver** card in **Overview**. The app copies the report to the clipboard and shows no confirmation.

The report leaves out serial numbers, file paths, packet payloads, and HID location IDs. It includes controller product names. Read the report before you share it.

## Get the logs

Open the Console pane and click **Copy All**. To open the pane, use the **Help** submenu of the menu bar item. Or run the following command.

```shell
ojd log show --lines 200
```

Logs may contain device names, identifiers, and paths. Read them before you share them.

## Capture packets

For a controller that is wrong or missing, attach a packet capture. Run the following commands.

```shell
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless controller packets --limit 200 --json > packets.json
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless controller trace --seconds 10 --json-lines > trace.jsonl
```

The commands print to Terminal. The `>` redirect saves the output to a file in the current folder. Attach the files to your report.

Say which controls you pressed and in what order. Packet contents differ by controller. Check the file before you share it.

## Further reading

- [Known issues](known-issues.md)
- [Command reference](../command-line/command-reference.md)
- [Supported controllers](../connecting-controllers/supported-controllers.md)
