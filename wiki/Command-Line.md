# Using the Command Line

Use `ojd`, the OpenJoystickDriver command line, to check status, start or stop the service, and manage controllers and controller records.

> **Note:** This page applies to OpenJoystickDriver 0.5.0-beta.5 and later. Version 0.5.0-beta.4 and earlier do not have all of the features on this page.

This page explains how to run `ojd`, which options apply to every command, how to read its output, and what its exit codes mean.

## Run a Command

The command-line tool is named `ojd`. It is the app's own executable: when it runs under the name `ojd`, it acts as the command line, and under any other name it opens the app.

To install `ojd`, open the app's Settings and click Install Command-Line Tool. The app links `/usr/local/bin/ojd` to its executable, and macOS asks for an administrator password when that folder needs it. Uninstall in the same place removes the link. The app never replaces a file at that path that is not a link.

To link it yourself instead, create the link in a folder on your `PATH`:

```shell
ln -s /Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver /usr/local/bin/ojd
```

Writing to `/usr/local/bin` can need `sudo`. To remove the tool, delete the link: `rm /usr/local/bin/ojd`.

Then run a command:

```shell
ojd status
```

The [command reference](Command-Reference.md) lists every command. `ojd --help` lists them too, and `ojd COMMAND --help` shows the options of one command.

To start, run `ojd status` to check the service, extension, and permissions, `ojd diagnose` to run every check, and `ojd controller list` to list connected controllers.

## Shell Completion

`ojd --generate-completion-script SHELL` prints a completion script for `zsh`, `bash`, or `fish`. For example, in zsh:

```shell
ojd --generate-completion-script zsh > ~/.zfunc/_ojd
```

The folder must be on your `fpath`.

## Global Options

These options work on every command, before or after the command name. `ojd --json status` and `ojd status --json` do the same thing. `ojd --help` lists them, and the help of each command points there instead of repeating them.

- `--json`: Print JSON on standard output.
- `--plain`: Print one record per line on standard output, with tab-separated fields.
- `-q`, `--quiet`: Do not print success messages on standard error.
- `--no-color`: Do not use color.
- `--no-input`: Never ask a question. A command that needs a missing value fails and names the option that gives it.
- `--timeout SECONDS`: How long to wait for each request to the service. The default is 0.5 seconds. For `service`, `virtual set`, and `virtual reset` commands, it bounds the whole command, and the default is 5 seconds. For `permission request`, the default is 10 seconds. The value must be a number above 0.
- `-h`, `--help`: Show help on standard output.
- `--version`: Show the version alone, for example `0.5.0-beta.5`.

`--json` and `--plain` cannot be used together.

## Environment Variables

These variables stand in for a global option that the command line leaves out. A flag beats its variable, and an empty variable counts as unset.

- `OJD_NO_INPUT`: `1`, `true`, or `yes` acts as `--no-input`, and `0`, `false`, or `no` does not, in any letter case.
- `OJD_TIMEOUT`: Seconds, as for `--timeout`.
- `OJD_COLOR`: `auto` follows the rules under [Output](#output), `always` uses color even off a terminal or with `NO_COLOR` set, and `never` acts as `--no-color`.

Any other `OJD_NO_INPUT` value, or an invalid `OJD_TIMEOUT` or `OJD_COLOR` value, is a usage error and exits with code 64.

For contributors: an `ojd` built from the repository hands each command to the installed app's `ojd`. Set `OJD_RUN_REPOSITORY_CLI=1` to run the repository build itself instead.

## The Service

Most commands send requests to the OpenJoystickDriver service, which runs inside the app. No command starts the service by itself. Start it with `ojd service start`, and stop it with `ojd service stop`.

A command that needs the service exits with code 69 when the service is not running. `ojd status` works without the service and reports it as stopped.

## Output

- Data goes to standard output. Progress messages, warnings, and errors go to standard error.
- Human-readable output is translated and can change between releases. Do not parse it in scripts.
- `--json` output is one JSON object. A command that streams, such as `ojd controller watch`, prints one object per line. Keys and values are stable identifiers and are never translated. [`cli-output.schema.json`](../Resources/Schemas/cli-output.schema.json) describes the output of each command. The schema is strict: it lists every key and value that its release prints, and rejects others. Within a major version, the output only gains keys and values: a later release never removes a key, a value, or a command's output, never makes an always-present key optional, and never gives a value a new type such as `null`.
  A program that reads one release's output keeps working with later releases of the same major version.
  Because a later release can add keys and values, validate output against the schema from the same release.
- `--plain` output has one record per line, with tab-separated fields. The first field names the kind of record. Fields are stable identifiers and are never translated.
- Errors use one format: `error[E2004]: WHAT FAILED. HOW TO FIX IT.` The code in the brackets is stable, so a script can branch on it. An error that the service reports for remapping carries an `E3xxx` code. `ojd explain E2004` prints what a code means, and [Error codes](Error-Codes.md) lists them all.
- Color appears only on a terminal. `NO_COLOR`, `TERM=dumb`, `--no-color`, and `OJD_COLOR=never` turn it off. `OJD_COLOR=always` turns it on anywhere, except under `--no-color`.

## Exit Codes

| Code | Meaning |
| --- | --- |
| 0 | Success. |
| 1 | The command failed. |
| 64 | Usage error: an unknown command or option, or an invalid value. |
| 69 | The service is not running. Start it with `ojd service start`. |
| 77 | A macOS permission is missing. |
| 127 | An `ojd` built from the repository could not hand the command to the installed app. |
| 130 | Interrupted with Control-C. |
| 143 | Terminated with SIGTERM. |

## Further Reading

- [Command reference](Command-Reference.md)
- [Automating OpenJoystickDriver](Automating-OpenJoystickDriver.md)
- [Reporting a bug](Reporting-a-Bug.md)
