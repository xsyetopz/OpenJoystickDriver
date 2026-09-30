# Using the command line

This article explains how to run OpenJoystickDriver commands in Terminal, which options apply to every command, and what the exit codes mean.

## Run a command

The command line is part of the OpenJoystickDriver app. To run a command, call the app binary with `--headless` and the command name.

```shell
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless COMMAND
```

Replace `COMMAND` with a command from the [command reference](command-reference.md). For example, `status` shows the driver status.

Some commands work only when you run the app from the `/Applications` folder. The `app login` and `extension enable` commands give an error when you run them from another folder.

## Create a short alias

The path is long. You can create an optional shell alias named `ojd`. OpenJoystickDriver does not install this alias.

1. Open Terminal.
1. Add this line to your `~/.zshrc` file:

   ```shell
   alias ojd='/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless'
   ```

1. Open a new Terminal window.
1. Run `ojd status` to check the alias.

The other articles use `ojd` in examples.

## Global options

Global options go before the command name.

```text
ojd [--timeout SECONDS] COMMAND
```

- `--timeout SECONDS`: Set how long the command waits for the running app. The value must be greater than 0. The default is 0.5 seconds. Put this option before the command. Do not repeat it.
- `-h`, `--help`: Show the list of commands. Use it alone.
- `-v`, `--version`: Show the version. Use it alone.

For example, this command waits up to 5 seconds:

```shell
ojd --timeout 5 controller list
```

Some commands have their own `--help` text. For example, `ojd map --help`, `ojd app logs --help`, and `ojd permissions help` show help for that command. The `extension`, `diagnose`, and `app login` commands do not show help with `--help`. They exit with code 64. Use `ojd --help` instead.

## Commands that need the running app

Many commands send a request to the running OpenJoystickDriver app. Start the app before you run them. If the app does not respond, the command exits with code 1 and says that it cannot connect to the installed app.

These commands need the running app:

- `controller` commands, including `controller output`.
- `map` commands.
- `app ready`.
- `permissions request`.
- `test`.
- `diagnose runtime`.

These commands also work when the app does not run:

- `status` and `app status` show the permission state from the local system. The output says `direct mode - app service not running`.
- `permissions status` shows the local permission state and exits with code 1.
- `permissions open`, `permissions explain`, `app login`, `app logs`, `extension`, `diagnose catalog`, `diagnose report`, and `update check`.

## Machine-readable output

Some commands accept `--json`. They print JSON to standard output. The command reference lists the commands that accept it.

```shell
ojd status --json
```

The `controller trace` and `controller watch` commands accept `--json-lines` instead. They print one JSON object for each line.

The text output of `test`, `diagnose`, `diagnose catalog`, and `app logs show` goes to standard error. To save it, redirect standard error, for example `2> FILE.txt`. The `diagnose runtime` and `diagnose report` commands print to standard output.

## Identical controllers

Many controller commands select a controller by vendor ID and product ID (`VID` and `PID`). Give the values in decimal or with the `0x` prefix. If you omit both, the command uses the one connected controller.

If two controllers have the same `VID:PID`, the command cannot choose between them. Add `--device ID`. The ID is an opaque value that `controller output list` prints for each controller.

```shell
ojd controller output list
ojd controller state --device ID
```

For more information about how to find a `VID:PID`, see [Finding your controller ID](../connecting-controllers/finding-your-controller-id.md).

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | The command succeeded. |
| 1 | The command failed. |
| 2 | The system blocks a permission request, or a system extension approval is pending. |
| 64 | The command line has an error. The command shows the error and the command list. |

Some details:

- `permissions request` exits with code 2 when access stays blocked.
- `extension enable` and `extension disable` exit with code 2 when the request does not finish in 60 seconds. Approve it in System Settings, then run `extension status`.
- `test` exits with code 1 unless the test passes.
- Argument errors inside some subcommands exit with code 1, not 64.
- `update check` exits with code 1 when the check fails.

## Further reading

- [Command reference](command-reference.md)
- [Reporting a bug](../troubleshooting/reporting-a-bug.md)
