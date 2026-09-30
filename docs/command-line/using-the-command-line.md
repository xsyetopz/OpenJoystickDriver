# Using the command line

This article explains how to run `ojd`, which options apply to every command, how to read its output, and what its exit codes mean.

## Run a command

The command-line tool is named `ojd`. It is the app's own executable: when it runs under the name `ojd`, it acts as the command line, and under any other name it opens the app.

To run `ojd` without installing it, link it into a folder on your `PATH`:

```shell
ln -s /Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver /usr/local/bin/ojd
```

Writing to `/usr/local/bin` can need `sudo`. To remove the tool, delete the link: `rm /usr/local/bin/ojd`.

Then run a command:

```shell
ojd status
```

The [command reference](command-reference.md) lists every command. `ojd --help` lists them too, and `ojd COMMAND --help` shows the options of one command.

## Global options

These options work on every command, before or after the command name. `ojd --json status` and `ojd status --json` do the same thing.

- `--json`: Print JSON on standard output.
- `--plain`: Print one record per line on standard output, with tab-separated fields.
- `-q`, `--quiet`: Do not print success messages on standard error.
- `--no-color`: Do not use color.
- `--no-input`: Never ask a question. A command that needs a missing value fails and names the option that gives it.
- `--timeout SECONDS`: How long to wait for each request to the service. The default is 0.5 seconds. For `service` commands, it bounds the whole command, and the default is 5 seconds. The value must be a number above 0.
- `-h`, `--help`: Show help on standard output.
- `--version`: Show the version alone, for example `0.5.0-beta.5`.

`--json` and `--plain` cannot be used together.

## The service

Most commands send requests to the OpenJoystickDriver service, which runs inside the app. No command starts the service by itself. Start it with `ojd service start`, and stop it with `ojd service stop`.

A command that needs the service exits with code 69 when the service is not running. `ojd status` works without the service and reports it as stopped.

## Output

- Data goes to standard output. Progress messages, warnings, and errors go to standard error.
- Human-readable output is translated and can change between releases. Do not parse it in scripts.
- `--json` output is one JSON object. Its keys and values are stable identifiers and are never translated. New keys can appear in later releases.
- `--plain` output has one record per line, with tab-separated fields. The first field names the kind of record. Fields are stable identifiers and are never translated.
- Errors use one format: `ojd: WHAT FAILED. HOW TO FIX IT.`
- Color appears only on a terminal. `NO_COLOR`, `TERM=dumb`, and `--no-color` turn it off.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success. |
| 1 | The command failed. |
| 64 | Usage error: an unknown command or option, or an invalid value. |
| 69 | The service is not running. Start it with `ojd service start`. |
| 77 | A macOS permission is missing. |
| 130 | Interrupted with Control-C. |

## Further reading

- [Command reference](command-reference.md)
- [Reporting a bug](../troubleshooting/reporting-a-bug.md)
