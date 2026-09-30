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

## controller

List connected controllers, inspect them, and test their input and outputs. Every `controller` command needs the service running.

```text
ojd controller list
ojd controller show CONTROLLER
ojd controller watch CONTROLLER [--duration SECONDS] [--first-press]
ojd controller capture CONTROLLER [--duration SECONDS]
ojd controller rumble CONTROLLER [--left N] [--right N] [--left-trigger N] [--right-trigger N] [--duration SECONDS]
ojd controller light CONTROLLER [--color RRGGBB] [--brightness N]
ojd controller player CONTROLLER 1|2|3|4|off
ojd controller suspend CONTROLLER
ojd controller resume CONTROLLER
ojd controller disconnect CONTROLLER
```

`CONTROLLER` is an ID from `ojd controller list`, or `VVVV:PPPP`, the hexadecimal vendor and product ID, in either case. A `VVVV:PPPP` that matches two connected controllers is rejected, and the error lists them. Use an ID to pick one.

- `controller list`: List connected controllers.
- `controller show`: Show a controller's identity, ownership, capabilities, and virtual gamepad. The Output checks section lists the commands that exercise each rumble motor and light, with what to observe.
- `controller watch`: Print the controller's input state each time it changes, until you press Control-C. `--duration` stops after that many seconds. `--first-press` prints the first control pressed and exits. It fails when `--duration` passes first. With `--json`, it prints one object per line. Stick Y points up.
- `controller capture`: Print the raw packets the controller sends and receives, each with its time, direction (`rx` or `tx`), length, and hex bytes. It runs until you press Control-C, or until `--duration` seconds pass. With `--json`, it prints one object per line.
- `controller rumble`: Run the rumble motors. `--left`, `--right`, `--left-trigger`, and `--right-trigger` set each motor's intensity from 0 to 255. With none of them, both main motors run at 180. `--duration` is in seconds, above 0 and at most 5, and is 0.45 by default. Set every intensity to 0 to stop the motors.
- `controller light`: Set the lightbar color with `--color`, as hex such as `FF8000`, or the LED brightness with `--brightness`, from 0 to 255.
- `controller player`: Set the player indicator lights to 1 to 4, or turn them off with `off`.
- `controller suspend`: Stop OpenJoystickDriver from driving the controller until you resume it.
- `controller resume`: Let OpenJoystickDriver drive a suspended controller again.
- `controller disconnect`: Close a Bluetooth controller's connection. The controller stays paired and reconnects when you turn it on again. The command waits at least 6 seconds for Bluetooth to confirm.

## virtual

Show and choose the virtual gamepad that OpenJoystickDriver publishes for a controller. A choice applies to every controller of the same model.

```text
ojd virtual show [CONTROLLER]
ojd virtual set PROFILE CONTROLLER
ojd virtual reset [CONTROLLER] [--all] [--force] [--dry-run]
```

- `virtual show`: Show each controller's virtual gamepad and the profiles you can choose. Name a controller to show only that one.
- `virtual set`: Choose the profile for the controller's model. The profiles are `hid-xbox-one-s-bt` and `hid-generic`.
- `virtual reset`: Return the controller's model to automatic selection. `--all` returns every model, including models that are not connected. It asks first on a terminal and needs `--force` otherwise. `--dry-run` (`-n`) prints what would change and changes nothing.

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
