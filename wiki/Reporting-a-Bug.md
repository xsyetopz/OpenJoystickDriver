# Reporting a Bug

Send reports to the [issue tracker](https://github.com/xsyetopz/OpenJoystickDriver/issues) so the maintainer can reproduce the problem.

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

The report leaves out serial numbers, file paths, and packet contents. It includes your controllers' product names. Read it before you share it.

For a stutter or latency report, run the command right after the stutter. The report then holds frame timings.

## Run a Guided Check

If a control doesn't respond, or acts as another control, run **Guided Check** in the Input Test window. Or run `ojd controller check <controller> --json > check.json`. The check asks you to move each control in turn.

When it ends, click **Open Issue**. OJD saves the result and opens the support form with your details filled in. Attach the saved file. See [Testing a Controller](Testing-a-Controller.md#guided-check).

If every control responded, **Validate** offers the result as a community validation.

## Get the Logs

Open **Activity** and choose **Log**, or choose **Help** > **Activity Log**. Or run:

```shell
ojd log show --lines 200
```

Logs may contain device names and paths. Read them before you share them.

## Capture Packets

For a controller that works wrongly or not at all, attach a packet capture. Run this while you press each control, and say in what order:

```shell
ojd controller capture <controller> --duration 10 --json > capture.jsonl
```

Attach the file. Check it before you share it.

## Further Reading

- [Known issues](Known-Issues.md)
- [Command reference](Command-Reference.md)
- [Supported controllers](Supported-Controllers.md)
