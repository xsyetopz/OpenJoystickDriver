# Command reference

This article lists every `ojd` command. Every command also accepts the global options in [Using the command line](using-the-command-line.md).

## status

Show the service, the DriverKit extension, macOS permissions, and connected controllers in one summary.

```text
ojd status
```

`ojd status` works when the service is not running. It then reports the service as `stopped`, shows the extension state, and exits with code 0. Permissions and controllers appear only while the service runs.

With `--json`, the output is one object with these keys:

- `service`: `state` (`running` or `stopped`) and `version`.
- `extension`: `bundle` (`present`, `missing`, or `invalid`) and `registration` (`active`, `inactive`, `absent`, or `unavailable`).
- `permissions`: `inputMonitoring` and `accessibility`.
- `virtualDevice`: `enabled`, `status`, and `overrideError`.
- `controllers`: each with `id`, `name`, `vendorID`, `productID`, and `connection`.
- `unboundDevices`: devices that OpenJoystickDriver does not support, each with `vendorID`, `productID`, `connection`, and `reason`.
- `passThroughDevices`: devices that OpenJoystickDriver leaves to macOS.

Keys that need the service are absent when it is stopped.

With `--plain`, the first field of each line is `service`, `extension`, `permission`, `virtual-device`, `controller`, `unbound`, or `pass-through`.

## service

Start or stop the OpenJoystickDriver service, or wait until it accepts requests. With `--timeout`, each command waits at most that many seconds. The default is 5 seconds.

```text
ojd service start
ojd service stop
ojd service wait
```

- `service start`: Open the app in the background and wait until its service accepts requests. It does nothing when the service already runs. It needs the `ojd` inside `OpenJoystickDriver.app`, or a link to it.
- `service stop`: Stop the service and wait until it exits. Connected controllers return to macOS.
- `service wait`: Wait until the service accepts requests. It exits with code 69 when the time runs out.

With `--json`, each command prints `{"state": "running"}` or `{"state": "stopped"}`. With `--plain`, it prints `state` and the state.

## permission

List the macOS permissions OpenJoystickDriver needs, or ask the service to request them.

```text
ojd permission list
ojd permission request [input-monitoring] [accessibility]
```

- `permission list`: Show each permission, its state (`granted`, `denied`, or `unknown`), and what OpenJoystickDriver uses it for. The permissions are `input-monitoring`, `accessibility`, and `driver-extension`. When the service is stopped, `ojd` reads the states itself and says so on stderr.
- `permission request`: Ask the service to request each permission you name, or both `input-monitoring` and `accessibility` when you name none. macOS shows its own prompt. The command never prompts in the terminal. It exits with code 77 when a permission is still not granted.

With `--json`, `permission list` prints `permissions`, each with `id`, `name`, `state`, and `purpose`.

## extension

Show, activate, or deactivate the DriverKit system extension.

```text
ojd extension status
ojd extension activate
ojd extension deactivate
```

- `extension status`: Show whether the extension is in the app (`bundle`: `present`, `missing`, or `invalid`) and registered with macOS (`registration`: `active`, `inactive`, `absent`, or `unavailable`). It works when the service is stopped. It exits with code 1 when the registration is `unavailable`.
- `extension activate`: Ask macOS to activate the extension. macOS can ask you to approve it in System Settings. The command then reports `awaiting-approval` and exits with code 0.
- `extension deactivate`: Ask macOS to deactivate the extension. Connected controllers return to macOS.

`activate` and `deactivate` need the `ojd` inside `/Applications/OpenJoystickDriver.app`, or a link to it. With `--json`, they print `state`: `active`, `inactive`, or `awaiting-approval`.

## setting

List, read, or change app settings. The service applies each setting, so these commands need it running.

```text
ojd setting list
ojd setting get KEY
ojd setting set KEY true|false
```

The keys are `launch-at-login`, `notification-sounds`, `include-prerelease-updates`, and `developer-tools`. `setting get` prints `true` or `false` alone. With `--json`, `setting list` prints `settings`, each with `key`, `value`, and `description`, and `setting get` and `setting set` print `key` and `value`.

## log

Show the service logs or print the folder that holds them.

```text
ojd log show [--lines COUNT] [--follow]
ojd log path
```

- `log show`: Print the last lines of each service log, 100 by default and at most 10000. On a terminal, the output goes through `$PAGER`, or `less -FRX` when it is unset. Set `PAGER` to an empty value to turn paging off. `--follow` keeps printing new lines until you press Control-C. With `--json` and `--follow`, it prints one object per line, with `stream` and `line`.
- `log path`: Print the log folder. To open it in Finder, run `open "$(ojd log path)"`.

## diagnose

Run every check and report what is wrong.

```text
ojd diagnose [--bundle PATH] [--soak SECONDS]
```

The checks are `service`, `extension-bundle`, `extension-registration`, `input-monitoring`, `accessibility`, `usb-access`, `virtual-device`, and `runtime-health`. Each reports `pass`, `warn`, `fail`, or `skip`. Checks that need the service are skipped while it is stopped. The command exits with code 1 when any check fails.

- `--bundle PATH`: Also write a support report to `PATH`. Read it before you share it.
- `--soak SECONDS`: Run the `runtime-health` check. It samples the service's memory, file descriptors, and CPU for 1 to 86400 seconds. Without `--soak`, that check is skipped. `--interval-ms`, `--rss-limit-mib`, and `--footprint-limit-mib` tune the sampling and set failure limits.

With `--json`, the output has `checks`, each with `id`, `status`, and `detail`, and `bundle` when you wrote one.

## update

Check whether a newer release exists.

```text
ojd update check [--prerelease]
```

`--prerelease` includes prerelease versions. The command exits with code 1 when the check fails. With `--json`, it prints `status` (`up-to-date` or `available`), `currentVersion`, `latestVersion`, `includePrereleases`, and `releaseURL` when an update is available.
