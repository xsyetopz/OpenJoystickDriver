# Command reference

This page lists every `ojd` command. Every command also accepts the global options in [Command line](Command-Line.md#global-options).

## Contents

- [status](#status)
- [controller](#controller)
- [profile](#profile)
- [binding](#binding)
- [virtual](#virtual)
- [record](#record)
- [service](#service)
- [permission](#permission)
- [extension](#extension)
- [setting](#setting)
- [log](#log)
- [diagnose](#diagnose)
- [update](#update)
- [Further reading](#further-reading)

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
- `skippedRecords`: your controller record files that OpenJoystickDriver skipped, each with `file` and `problem`.

Keys that need the service are absent when it is stopped.

With `--plain`, the first field of each line is `service`, `extension`, `permission`, `virtual-device`, `controller`, `unbound`, `pass-through`, or `skipped-record`.

## controller

List connected controllers, inspect them, and test their input and outputs. Every `controller` command needs the service running.

```text
ojd controller list
ojd controller show CONTROLLER
ojd controller watch CONTROLLER [--duration SECONDS] [--first-press] [--output]
ojd controller capture CONTROLLER [--duration SECONDS]
ojd controller rumble CONTROLLER [--left N] [--right N] [--left-trigger N] [--right-trigger N] [--duration SECONDS]
ojd controller light CONTROLLER [--color RRGGBB] [--brightness N]
ojd controller player CONTROLLER 1|2|3|4|off
ojd controller suspend CONTROLLER
ojd controller resume CONTROLLER
ojd controller disconnect CONTROLLER
ojd controller calibrate CONTROLLER [start|pause|reset]
ojd controller pair LEFT RIGHT --profile PROFILE
ojd controller unpair PAIR
```

`CONTROLLER` is an ID from `ojd controller list`, or `VVVV:PPPP`, the hexadecimal vendor and product ID, in either case. A `VVVV:PPPP` that matches two connected controllers is rejected, and the error lists them. Use an ID to pick one. An ID lasts until the service restarts, and it can change when you unplug and replug the controller. By design, IDs from different service runs cannot be linked to the same controller, so scripts should use `VVVV:PPPP` instead of a stored ID. A unit ID (`U-` and 16 characters) also names one controller. It comes from the controller's model, the USB port it uses, and its interface, never its serial number. It stays the same across reconnects and service restarts while the controller uses the same port, and changes when it moves to another port. A controller with no location ID has no unit ID. Scripts can store a unit ID.

- `controller list`: List connected controllers. Each line shows the unit ID after the ID, and with `--json`, `unit` gives each controller's unit ID. With `--plain`, the unit ID is the last field, empty when the controller has none.
- `controller show`: Show a controller's unit ID (`controller.unit` with `--json`), identity, ownership, capabilities, effective record, and virtual gamepad. The Record line says whether the record is bundled or one of your records, and names the file of your record. It reads your records from disk when you run the command, so a controller that connected before you changed a record can still run on the older one until it connects again. With `--json`, `controller.record` has `layer` (`bundled` or `user`) and, for your record, `file`. It is absent when no record matches the controller's model, as for a generic HID controller. The Publication line says whether a virtual gamepad publishes the controller and, when none does, why, such as `native-gamepad` for a controller macOS serves itself. With `--json`, `controller.publication` has `state` (`published`, `not-published`, or `failed`), `reason`, and `target`. The Output checks section lists the commands that exercise each rumble motor and light, with what to observe.
- `controller watch`: Print the controller's input state each time it changes, until you press Control-C. `--duration` stops after that many seconds. `--first-press` prints the first control pressed and exits. It fails when `--duration` passes first. With `--json`, it prints one object per line. Stick Y points up. `--output` also prints what the virtual gamepad sends after stick transfer and remapping, on an `out` line, or `out none` when no virtual gamepad publishes the controller. Its stick Y points down, as in the HID report. With `--json` and `--output`, each object has `input` and, when the controller is published, `output`.
- `controller capture`: Print the raw packets the controller sends and receives, each with its time, direction (`rx` or `tx`), length, and hex bytes. It runs until you press Control-C, or until `--duration` seconds pass. With `--json`, it prints one object per line.
- `controller rumble`: Run the rumble motors. `--left`, `--right`, `--left-trigger`, and `--right-trigger` set each motor's intensity from 0 to 255. With none of them, both main motors run at 180. `--duration` is in seconds, above 0 and at most 5, and is 0.45 by default. Set every intensity to 0 to stop the motors.
- `controller light`: Set the lightbar color with `--color`, as hex such as `FF8000`, or the LED brightness with `--brightness`, from 0 to 255.
- `controller player`: Set the player indicator lights to 1 to 4, or turn them off with `off`.
- `controller suspend`: Stop OpenJoystickDriver from driving the controller until you resume it.
- `controller resume`: Let OpenJoystickDriver drive a suspended controller again.
- `controller disconnect`: Close a Bluetooth controller's connection. The controller stays paired and reconnects when you turn it on again. The command waits at least 6 seconds for Bluetooth to confirm.
- `controller calibrate`: Show the motion calibration of a controller with a gyro. `start` collects gyro drift while the controller lies still, `pause` stops the collection, and `reset` removes the calibration. Motion lean and steering bindings use the calibration. With `--json`, it prints `controller`, `calibrated`, `collecting`, and `offsetDegreesPerSecond` with `x`, `y`, and `z`.
- `controller pair`: Combine a left and a right Joy-Con into one controller that uses `PROFILE`. `PROFILE` must be a paired Joy-Con profile. For more information, see [Sticks, triggers, touchpad, and motion](Sticks-Triggers-Touchpad-and-Motion.md). Hardware behavior of Joy-Con pairing is not verified.
- `controller unpair`: Separate a Joy-Con pair. `PAIR` is the session ID that `controller pair` prints, or the ID of either Joy-Con.

With `--json`, `controller pair` and `controller unpair` print `session`, `left`, `right`, `profile`, and `gyro`.

## profile

Create, change, activate, and move remapping profiles. Every `profile` command needs the service running. For more information, see [Creating a profile](Remapping-Profiles.md).

```text
ojd profile list
ojd profile show PROFILE
ojd profile create NAME --controller CONTROLLER [--app BUNDLE-ID] [--virtual-gamepad disabled|mapped|passthrough] [--physical-input shared|exclusive]
ojd profile duplicate PROFILE NEW-NAME
ojd profile rename PROFILE NEW-NAME
ojd profile delete PROFILE [--force] [--dry-run]
ojd profile activate PROFILE [--allow-empty]
ojd profile deactivate PROFILE
ojd profile edit PROFILE
ojd profile recover [--force] [--dry-run]
ojd profile import FILE|-
ojd profile validate FILE|-
ojd profile export PROFILE [--output FILE]
ojd profile get PROFILE KEY
ojd profile set PROFILE KEY VALUE
```

`PROFILE` is a profile ID, or a profile name in any letter case. A name that two profiles share is rejected, and the error lists their IDs. Use an ID to pick one.

- `profile list`: List each profile with its ID, name, controller model, app scope, and number of bindings, and show which profiles are active. When a saved profile cannot be loaded, it also reports each issue on stderr, followed by "Repair them with 'ojd profile recover'."
- `profile show`: Show a profile's settings and bindings. Bindings use the `SOURCE` and `TARGET` forms of `ojd binding set`.
- `profile create`: Create an empty, inactive profile for one controller model. `--controller` is `VVVV:PPPP` or the ID of a connected controller. The profile applies in every app unless `--app` gives an app's bundle ID. `--virtual-gamepad` sets what the virtual gamepad sends: nothing (`disabled`), bound controls only (`mapped`), or also every control that no binding uses (`passthrough`, the default). `--physical-input` sets whether macOS still sees the controller (`shared`, the default) or OpenJoystickDriver takes it (`exclusive`).
- `profile duplicate`: Copy a profile under a new name. The copy is inactive.
- `profile rename`: Give a profile a new name of 1 to 80 characters.
- `profile delete`: Delete a profile. An active profile stops applying. It asks first on a terminal and needs `--force` otherwise. `--dry-run` (`-n`) prints what would change and changes nothing.
- `profile activate`: Apply a profile. It replaces the active profile of the same controller model and app scope. A profile with the virtual gamepad set to `mapped` or `disabled` and no bindings blocks all input from the controller. To activate such a profile, add `--allow-empty`.
- `profile deactivate`: Stop applying a profile. The controller then sends its own input.
- `profile edit`: Open the profile file in `$VISUAL`, `$EDITOR`, or `vi`, then check and save it. Use it to change chords, sequences, layers, stick and trigger tuning, and the app scope. It needs a terminal. Without one, export the profile, change the file, and import it. For the file format, see [Profile file reference](Profile-File-Reference.md).
- `profile recover`: Repair the problems that `profile list` reports. It acts on each issue: it removes a damaged profile file and resets a damaged active profile list. The service first backs up each file beside the original, under a name that contains `.backup-`. It asks first on a terminal and needs `--force` otherwise. `--dry-run` (`-n`) prints what would change and changes nothing. With `--plain`, it prints one line for each issue, with its ID and kind.
- `profile import`: Add a profile from a file that `profile export` wrote. Use `-` to read the file from stdin. A profile with the same ID as an existing profile replaces it.
- `profile validate`: Check a profile file without importing it. Use `-` to read the file from stdin. It needs no running service and exits 1 when the profile is invalid.
- `profile export`: Print a profile file to stdout, or write it to `--output`. The file is JSON, so `--json` and `--plain` do not change the output.
- `profile get`: Print one value from the profile file. `KEY` is a path of member names and array indexes joined by dots, such as `stickMappings.0.tuning.innerDeadzone`. A string prints alone, and any other value prints as JSON. A key with no value exits 1.
- `profile set`: Change one value in the profile file. `VALUE` is read as JSON, or as a string when it is not JSON, so `0.2` is a number and `space` is a string. To set the string `true`, write `'"true"'`. `null` removes the key or the array item, and the index one past the end of an array adds an item. OJD checks the whole profile before it saves it and refuses a change that makes it invalid or changes `id`. For example, `ojd profile set Racing physicalColor '{"red":255,"green":0,"blue":0}'`.

With `--json`, a profile is an object with `id`, `name`, `controller`, `scope` (`global` or `app:BUNDLE-ID`), `active`, and `bindings`, the number of bindings. `profile list` prints `profiles` and `issues`, each issue with `id`, `kind`, and `message`. `profile show` prints `profile` and `document`, the full profile file. `profile create`, `duplicate`, `rename`, `activate`, `deactivate`, `edit`, and `set` print `profile` and `changed`. `profile get` prints `key` and `value`. `profile delete` prints `deleted` and `dryRun`, `profile recover` prints `recovered`, each with `id`, `kind`, and `message`, and `dryRun`, `profile import` prints `profile` and `replaced`, and `profile validate` prints `valid`, then `id`, `name`, `controller`, and `scope` for a valid profile or `problem` for an invalid one.

## binding

List, set, and clear the bindings of a profile. A binding sends a target when you use a control on the controller. Every `binding` command needs the service running. For more information, see [Assigning buttons and actions](Bindings-and-Actions.md).

```text
ojd binding list PROFILE
ojd binding set PROFILE SOURCE TARGET [options]
ojd binding clear PROFILE SOURCE... [--force] [--dry-run]
ojd binding clear PROFILE --all [--force] [--dry-run]
```

`SOURCE` is one of these forms:

- `button:NAME`, such as `button:south` or `button:left_shoulder`
- `dpad:DIRECTION`
- `axis:NAME`, or `axis:NAME:negative` or `axis:NAME:positive` for one direction, such as `axis:left_stick_x:positive`
- `trigger:NAME:STAGE`
- `motion:lean:DIRECTION`
- `touch:SURFACE:contact`, `touch:SURFACE:grid:COLUMNS:ROWS:COLUMN:ROW`, or `touch:SURFACE:swipe:DIRECTION:DISTANCE`

`TARGET` is one of these forms:

- `key:KEY`, with modifiers as `key:KEY:mods=command,control,option,shift`
- `mouse:BUTTON`, `move:x`, `move:y`, `scroll:x`, or `scroll:y`
- `gamepad:button:NAME`, `gamepad:dpad:DIRECTION`, or `gamepad:axis:NAME`
- `physical:...` for rumble, lights, and adaptive triggers

`ojd profile show` prints bindings in the same forms.

- `binding list`: List a profile's bindings.
- `binding set`: Bind a source to a target. A source has one binding, so this replaces the binding that the source has, and keeps its ID. The options are:
  - `--behavior`: When the target fires: `hold` (the default for a new binding), `toggle`, `tap_on_press`, `tap_on_release`, `pulse`, `press`, or `release`.
  - `--pulse-ms`: How long `pulse` holds the target, 1 to 5000 ms. The default is 100.
  - `--deadzone`, `--gain`, `--invert`, `--response-curve`, and `--digital-threshold`: Tuning for axis sources. The dead zone is 0 to 0.95 (default 0.1), the gain is 0.1 to 10 (default 1), and the response curve is `linear` (the default), `ease_in`, `ease_out`, or `smooth_step`. The digital threshold is the travel that counts as a press for button targets (default 0.5).
  - `--turbo-rate` and `--turbo-duty`: Repeat the target this many times a second while the source is held. The duty is the part of each cycle that the target is held, above 0 and below 1. Turbo cannot be used with `--long-hold` or `--double-tap`.
  - `--long-hold MS:TARGET`: Send another target when the source is held this long, such as `500:key:b`.
  - `--double-tap MS:TARGET`: Send another target when the source is pressed twice in this time, such as `300:key:c`.
  - `--actions-json`: More actions, as a JSON array in the form that `ojd profile export` writes.
- `binding clear`: Remove the bindings of the given sources. It exits with code 1 and changes nothing when a source has no binding. `--all` removes every binding, chord, sequence, and layer. Stick, trigger, touch, motion, and output settings stay. `--all` asks first on a terminal and needs `--force` otherwise. `--dry-run` (`-n`) prints what would change and changes nothing. When the result leaves a profile that is active on a connected controller with no inputs while OJD seizes the physical input, the command prints a warning on stderr that names `ojd binding set` and `ojd profile deactivate`, and still exits with code 0.

With `--json`, a binding is an object with `id`, `source`, `target`, and `behavior`. `binding list` prints `profile` and `bindings`, `binding set` prints `profile`, `binding`, and `replaced`, and `binding clear` prints `profile`, `removed` (the sources), `all`, and `dryRun`.

## virtual

Show and choose the virtual gamepad that OpenJoystickDriver publishes for a controller. A choice applies to every controller of the same model, unless you add `--unit`: then it applies to that controller only, by its unit ID, and wins over its model's choice.

```text
ojd virtual show [CONTROLLER]
ojd virtual set PROFILE CONTROLLER [--unit]
ojd virtual reset [CONTROLLER] [--unit] [--all] [--force] [--dry-run]
ojd virtual feed --as PROFILE
```

- `virtual show`: Show each controller's virtual gamepad and the profiles you can choose. Name a controller to show only that one. With `--json`, `overrideScope` says whether a stored choice is the controller's own (`unit`) or its model's (`model`).
- `virtual set`: Choose the profile for the controller's model. With `--unit`, choose it for that controller only. A controller with no unit ID cannot take `--unit`. The profiles are `hid-xbox-one-s-bt` and `hid-generic`.
- `virtual reset`: Return the controller's model to automatic selection. With `--unit`, it removes only that controller's own choice, so its model's choice applies again. `--unit` cannot be used with `--all`. `--all` returns every model, including models that are not connected. It asks first on a terminal and needs `--force` otherwise. `--dry-run` (`-n`) prints what would change and changes nothing.
- `virtual feed`: Publish a virtual gamepad with the `--as` profile and drive it from standard input. Write one JSON object per line, such as `{"buttons":["south"],"dpad":["up"],"axes":{"left_stick_x":0.5,"right_trigger":1}}`. Buttons, D-pad directions, and stick axes take the names of `button:`, `dpad:`, and `axis:` binding sources, and the triggers are the axes `left_trigger` and `right_trigger`. A missing control is neutral. Sticks run from -1 to 1 with Y up, and triggers run from 0 to 1. The latest line is sent at most every 16 ms. Each rumble command a game sends to the virtual gamepad is printed as one JSON object per line. The gamepad is removed when the input ends, on Control-C, or when the service gets no update for 2 seconds. A line that is not a frame exits with code 64. The service runs at most 4 feeds.

## record

Draft, list, check, install, or remove controller records. Only `record draft` needs the service. For more information, see [Adding or changing a controller record](Controller-Records.md).

```text
ojd record draft CONTROLLER [--duration SECONDS]
ojd record list [--bundled]
ojd record show VVVV:PPPP
ojd record validate FILE|-
ojd record install FILE|-
ojd record remove VVVV:PPPP [--force] [--dry-run]
```

`FILE` is a record file. Use `-` to read the record from stdin.

- `record draft`: Read a connected controller's HID report descriptor, capture its input reports for `--duration` seconds (10 by default) while you press each control, and print a record to start from. The record is an `add` for a model without a bundled record and a `patch` otherwise. It maps the buttons, sticks, triggers, and hat that the descriptor states plainly, with the `hid.report-layout` family, or names `hid.descriptor` when nothing maps. Each report byte that changed during the capture is listed on stderr with its lowest and highest value. It exits with code 1 when nothing maps for a model with a bundled record.
- `record list`: List every controller record, with its model, protocol family, layer (`bundled` or `user`), and file. It names each of your files that OpenJoystickDriver skipped, and why, on stderr. `--bundled` lists the bundled records alone.
- `record show`: Show one model's effective record and the layer of each top-level field. It exits with code 1 when no record exists for the model.
- `record validate`: Check a record without installing it. It shows the operation (`add` or `patch`), the model, the family, the file name, and whether the USB driver extension can claim the controller. It exits with code 1 when the record is not valid.
- `record install`: Check a record and write it to your record folder as `vvvv-pppp.json`. It replaces the record already installed for that model. It exits with code 1 and writes nothing when the record is not valid.
- `record remove`: Delete your record for a model. It asks first on a terminal and needs `--force` otherwise. `--dry-run` (`-n`) prints what would change and changes nothing. It exits with code 1 when you have no record for the model.

With `--json`, `record draft` prints `identity`, `name`, `operation`, `family`, `report` (`id` and `length`, absent when no report was chosen), `capturedReports`, `changedBytes`, each with `byte`, `minimum`, and `maximum`, and `record`. With `--plain`, it prints one line for each changed byte: its offset, lowest value, and highest value. `record list` prints `records`, each with `identity`, `vendorID`, `productID`, `family`, `layer`, and `file`, and `skipped`, each with `file` and `problem`. `skipped` is absent with `--bundled`. `record show` prints `identity`, `family`, `layer`, `file`, `transport` (`hid` or `usb`), `usbExtension` (`claims` or `does-not-claim`, for `usb` only), `fields`, and `record`. `record validate` prints `valid`, and `problem` or the record's `operation`, `identity`, `family`, `fileName`, `transport`, and `usbExtension`. `record install` prints `installed`, `replaced`, and `record`, and `record remove` prints `removed` and `dryRun`.

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
ojd log export FILE [--lines COUNT] [--force]
```

- `log show`: Print the last lines of each service log, 100 by default and at most 10000. On a terminal, the output goes through `$PAGER`, or `less -FRX` when it is unset. Set `PAGER` to an empty value to turn paging off. `--follow` keeps printing new lines until you press Control-C. With `--json` and `--follow`, it prints one object per line, with `stream` and `line`.
- `log path`: Print the log folder. To open it in Finder, run `open "$(ojd log path)"`.
- `log export`: Write the last lines of each service log to `FILE`, 2000 by default and at most 10000, with your home folder shown as `~`. It does not replace an existing file unless you pass `--force`. Review the file before you share it.

## diagnose

Run every check and report what is wrong.

```text
ojd diagnose [--bundle PATH] [--soak SECONDS]
```

The checks are `service`, `extension-bundle`, `extension-registration`, `input-monitoring`, `accessibility`, `controller-records`, `usb-access`, `virtual-device`, and `runtime-health`. Each reports `pass`, `warn`, `fail`, or `skip`. The `controller-records` check warns when OpenJoystickDriver skipped one of your controller record files. Checks that need the service are skipped while it is stopped. The command exits with code 1 when any check fails.

- `--bundle PATH`: Also write a support report to `PATH`. Read it before you share it.
- `--soak SECONDS`: Run the `runtime-health` check. It samples the service's memory, file descriptors, and CPU for 1 to 86400 seconds. Without `--soak`, that check is skipped. `--interval-ms`, `--rss-limit-mib`, and `--footprint-limit-mib` tune the sampling and set failure limits.

With `--json`, the output has `checks`, each with `id`, `status`, and `detail`, and `bundle` when you wrote one.

## update

Check whether a newer release exists.

```text
ojd update check [--prerelease]
```

`--prerelease` includes prerelease versions. The command exits with code 1 when the check fails. With `--json`, it prints `status` (`up-to-date` or `available`), `currentVersion`, `latestVersion`, `includePrereleases`, and `releaseURL` when an update is available.

## Further reading

- [Command line](Command-Line.md)
- [Reporting a bug](Reporting-a-Bug.md)
