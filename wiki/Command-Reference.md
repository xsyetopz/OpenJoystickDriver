# Command Reference

This page lists every `ojd` command. Every command also accepts the global options in [Command line](Command-Line.md#global-options).

## Contents

- [status](#status)
- [controller](#controller)
- [profile](#profile)
- [binding](#binding)
- [macro](#macro)
- [virtual](#virtual)
- [record](#record)
- [mod](#mod)
- [service](#service)
- [permission](#permission)
- [extension](#extension)
- [setting](#setting)
- [config](#config)
- [access](#access)
- [log](#log)
- [diagnose](#diagnose)
- [update](#update)
- [explain](#explain)
- [Further Reading](#further-reading)

## status

Show the service, the DriverKit extension, macOS permissions, and connected controllers in one summary.

```text
ojd status
```

`ojd status` prints an Input mapping row for each HID controller and unbound device, and `--json` carries the same `inputMapping` as `controller show`; `--plain` prints an `input-mapping` line after the controller or device line.

`ojd status` works when the service is not running. It then reports the service as `Stopped` with `--json`, shows the extension state, and exits with code 0, unless the service left a record of a stopped request listener (below). Permissions and controllers appear only while the service runs.

When the service's request listener stops on a fatal error, the service keeps running and leaves a record beside its socket (`<socket path>.failure.json`, with the writing process and its start time). While the service cannot be reached and that process runs, `ojd status` prints the report, then fails with `E2034` (exit code 69). The report has the `Request listener` row with `E2034`, its text, the error number and the time. With `--json`, `service.listenerFailure` holds `code`, `errno`, `time`, `message` and `current` (`true`); with `--plain`, the row is `listener-failure`, the code, the error number, the time and `current`. A record whose process has ended is not a current failure: the service is not running, `ojd status` exits with code 0, and the same row says that the last listener stopped (`current` is `false`). A record that cannot be used (damaged, of another version or kind, too large, or not your file) is `E2035` in `service.listenerFailureProblem` and a `listener-failure-problem` row, with the file and the reason; `ojd status` then exits with code 1. The app shows `E2034` in its status line and problem banner at once, with a Restart listener action; a listener that starts again, or an orderly quit, deletes the record. If restarting does not work, quit and reopen the app.

With `--json`, the output is one `SystemStatus` object with these keys:

- `service`: `state` (`Running` or `Stopped`) and `version`.
- `extension`: `bundle` (`Present`, `Missing`, or `Invalid`) and `registration` (`Active`, `Inactive`, `Absent`, or `Unavailable`).
- `commandLineTool`: the `ojd` link that the app installs. `state` is `Installed` (a link to this app's executable), `LinkedElsewhere` (a link to another existing file, such as another copy of the app), `Broken` (a link whose target is gone), `BlockedByFile` (a file or folder that is not a link; the app never replaces it), or `Missing` (nothing at `path`). `path` is where the link goes, and `target` is what it points at, when it is a link.
- `permissions`: `inputRead` and `inputInject`.
- `virtualDevice`: `enabled`, `status` (the backend's diagnostic text, with each controller's generations and send times, which `--plain` and `ojd diagnose` also print), `overrideError`, and `published` (the `id` of each connected controller that a virtual gamepad stands for). The `Virtual gamepad` row of the human output says `Off`, the error, or `On` with the names of those controllers.
- `controllers`: each with `id`, `name`, `vendorID`, `productID`, and `connection`.
- `unboundDevices`: devices that OpenJoystickDriver does not support, each with `vendorID`, `productID`, `connection`, and `reason`.
- `passThroughDevices`: devices that OpenJoystickDriver leaves to macOS.
- `skippedRecords`: your controller record files that OpenJoystickDriver skipped, each with `file` and `problem`.
- `ignoredDefaults`: your `Controllers/all.patch.json` when OpenJoystickDriver ignored it whole, with `file` and `problem`. The key is absent when the file is valid or does not exist.
- `skippedVirtualDevices`: your virtual device files that OpenJoystickDriver skipped, each with `file` and `problem`. A `Personas` folder beside `VirtualDevices` that holds files is listed too: OpenJoystickDriver reads virtual device files only from `VirtualDevices`, so move the files there.

Keys that need the service are absent when it is stopped.

With `--plain`, the first field of each line is `service`, `extension`, `command-line-tool`, `permission`, `virtual-device`, `controller`, `unbound`, `pass-through`, `skipped-record`, `ignored-defaults`, or `skipped-virtual-device`.

## controller

List connected controllers, inspect them, and test their input and outputs. Every `controller` command needs the service running.

```text
ojd controller list
ojd controller show CONTROLLER
ojd controller watch CONTROLLER [--duration SECONDS] [--first-press] [--output]
ojd controller watch --all [--duration SECONDS] [--output]
ojd controller capture CONTROLLER [--duration SECONDS]
ojd controller rumble CONTROLLER [--left N] [--right N] [--left-trigger N] [--right-trigger N] [--duration SECONDS]
ojd controller light CONTROLLER [--color RRGGBB] [--brightness N]
ojd controller player CONTROLLER 1|2|3|4|off
ojd controller claim CONTROLLER [--dry-run]
ojd controller release CONTROLLER [--dry-run]
ojd controller suspend CONTROLLER
ojd controller resume CONTROLLER
ojd controller disconnect CONTROLLER
ojd controller calibrate CONTROLLER [start|pause|reset]
ojd controller pair LEFT RIGHT --profile PROFILE
ojd controller unpair PAIR
```

`CONTROLLER` is an ID from `ojd controller list`, or `VVVV:PPPP`, the hexadecimal vendor and product ID, in either case. A `VVVV:PPPP` that matches two connected controllers is rejected, and the error lists them. Use an ID to pick one. An ID (`E-` and 16 characters) is a session token: it lasts until the controller disconnects, and the controller gets a new one each time it connects. By design, tokens from different connections cannot be linked to the same controller, so scripts should use `VVVV:PPPP` or a unit ID instead of a stored token. A unit ID (`U-` and 16 characters) also names one controller. It comes from the controller's model, the USB port it uses, and its interface, never its serial number. It stays the same across reconnects and service restarts while the controller uses the same port, and changes when it moves to another port. A controller with no location ID has no unit ID. Scripts can store a unit ID.

- `controller list`: List connected controllers. Each line shows the unit ID after the ID, and with `--json`, `unit` gives each controller's unit ID. With `--plain`, the unit ID follows the name, empty when the controller has none. Then come `owned-by-another-client` (empty when no other client holds the controller), the process ID and the name of the app that uses the controller directly, each empty when unknown; the human output appends **Used by** and the app name. The battery level and charging state follow it, empty when the service reports no power state, and the last column is `also-listed-by-system` when the system also lists the controller as a second controller that gives no input (`alsoListedBySystem` with `--json`); the human output then tells you to choose the virtual controller of OpenJoystickDriver in games. After it, `waits-for-guide-press` marks a controller that has sent no input since it connected and waits for a press of its home button, the PS button of a DualShock 3 over USB (`waitsForGuidePress` with `--json`); the human output then tells you to press it, and `controller show` gives the input failure reason `guide-not-pressed` (`GuideNotPressed` with `--json`). The human output shows the battery level after the connection.
- `controller show`: Show a controller's unit ID (`unit` with `--json`, which prints a `Controller` object with the controller's fields at the top level), identity, ownership, capabilities, effective record, and virtual gamepad. The Record line says whether the record is bundled or one of your records, and names the file of your record. It reads your records from disk when you run the command, so a controller that connected before you changed a record can still run on the older one until it connects again. With `--json`, `record` has `layer` (`Bundled`, `Package`, or `User`) and, for a record from a package or your own, `file`. `ownership` has `server` (`system` or `ojd`) and `serverSource`, which is the layer that sets `server` (`Bundled`, `Package`, or `User`), or `Default` when no layer sets it. A controller that the system cannot serve, such as one that OJD reads over raw USB, shows `server` `ojd` with `serverSource` `Route`, because its serving route always belongs to OJD. `record` is absent when no record matches the controller's model, as for a generic HID controller. The Input mapping row says where a HID controller's mapping comes from: `record`, "mapped from SDL_GameControllerDB" with the match tier and the GUID, or "standard HID usage map", which also names the reason when OJD rejects a database line. The Unmapped controls row lists the database fields OJD cannot express, such as `dpup` on a button. With `--json`, `inputMapping` has `source` (`Record`, `SDLGameControllerDB`, `StandardHIDUsageMap` or `None`, for a controller that does not bind), `guid`, `match`, `unmapped` and `rejection`, each but `source` and `unmapped` absent when it does not apply. With `--plain`, the `input-mapping` line has the source and the match tier in kebab-case, the GUID, and the unmapped fields joined with commas. See [Mapping source](Supported-Controllers.md#mapping-source). The Battery line shows the battery level, such as `73%`, or a range such as `0-9%` when the controller reports its charge in steps, and the charging state. With `--json`, `power` has `charging` (`Unknown`, `Discharging`, `Charging`, `Full`, or `NotChargeable`), `battery.percentage` as the lowest and highest percentage, absent when the level is unknown, and `wiredPower`, absent when the controller does not report it. `controller list --json` has the same `power` for each controller, and `power` is absent when the service reports no power state. With `--plain`, the `power` line has the charging state, the battery level, and `wiredPower`. The `protocol`, `controls`, `rumble-motors` and `lighting` lines print their values in lowercase kebab-case, such as `xbox-gip`, `sony-dual-shock4` and `left-stick-x`; a protocol family is its name split at every case boundary, which is also the name of its description file, and a binding with a variant adds `:` and the variant spelled the same way, such as `xbox-xusb:receiver`. With `--json`, `protocol` is the binding as the document spells it, such as `XboxXUSB:Receiver`. The Publication line says whether a virtual gamepad publishes the controller and, when none does, why, such as `system-gamepad` for a controller macOS serves itself; `--plain` and the human output print the reason in kebab-case, and the failure text for a `Failed` publication; the app shows the same reason or failure text. With `--json`, `publication` has `state` (`Published`, `NotPublished`, or `Failed`), `reason`, `failure`, and `target`. `reason` is present exactly when the state is `NotPublished` and is one of `OutputDisabled`, `SystemGamepad`, `NativeHIDPassThrough`, `UpstreamVirtualDevice`, `SessionSuspended`, `NoVirtualProfile`, `Suppressed`, or `NoInputYet`. `failure` is the text of the failed send and is present exactly when the state is `Failed`. The Tuning line lists the record's tuning values as applied, such as `stickDeadzone=0.2`, and is absent when the record sets none; with `--json`, `tuning` has the values named as in the record file. With `--json`, `capabilities.outputOwner` is `system` when macOS serves the controller natively, so the rumble and lighting lists hold only what macOS leaves undone, or `ojd` when OJD drives all of its output; the Output owner line appears only for `system`. The Output checks section lists the commands that exercise each rumble motor and light, with what to observe.
- `controller watch`: Print the controller's input state each time it changes, until you press Control-C. `--duration` stops after that many seconds. `--first-press` prints the first control pressed and exits. It fails when `--duration` passes first. With `--json`, it prints one `ControllerState` object per line, or one `ControlPress` object with `--first-press`. Stick Y points down. `--output` also prints what the virtual gamepad sends after stick transfer and remapping, on an `out` line, or `out none` when no virtual gamepad publishes the controller. It reads the virtual gamepad just before the input, so a press can show on the input line one line before it shows on the `out` line. Its stick Y points down, as in the HID report. With `--json` and `--output`, each object has `input` and, when the controller is published, `output`. `--all` watches every controller instead of one. Each line names its controller by its `ojd controller list` ID, and other lines report each controller that connects or disconnects, starting with the controllers already connected. With `--json`, each line is a watch line with `type` (`ADDED`, `MODIFIED`, or `DELETED`) and `object`, a `Controller` with its own `apiVersion` and `kind`, and no `apiVersion` or `kind` on the line. The `object` of an `ADDED` line has the fields of one `ojd controller list` entry, and the `object` of a `MODIFIED` line has the same fields and `input` and, with `--output`, `output`.
- `controller capture`: Print the raw packets the controller sends and receives, each with its time, direction (`Rx` or `Tx` with `--json`), length, and hex bytes. It runs until you press Control-C, or until `--duration` seconds pass. With `--json`, it prints one `RawReport` object per line.
- `controller rumble`: Run the rumble motors. `--left`, `--right`, `--left-trigger`, and `--right-trigger` set each motor's intensity from 0 to 255. With none of them, both main motors run at 180. `--duration` is in seconds, above 0 and at most 5, and is 0.45 by default. Set every intensity to 0 to stop the motors.
- `controller light`: Set the lightbar color with `--color`, as hex such as `FF8000`, or the LED brightness with `--brightness`, from 0 to 255.
- `controller player`: Set the player indicator lights to 1 to 4, or turn them off with `off`.
- `controller claim` and `controller release`: `claim` makes OpenJoystickDriver (`ojd`) serve the controller's model, and `release` gives it back to macOS (`system`). It sets `server` in your record for the model, `vvvv-pppp.json` or `vvvv-pppp.patch.json`, and creates a `ControllerPatch` file when you have none and the bundled catalog or an installed package has a record of the model. It needs the service running to find the controller. It keeps the other fields of the record. The choice applies to every controller of the model, and the running service applies it without a replug. `--dry-run` (`-n`) writes nothing. It exits with code 1 and E2023 for a controller that uses raw USB, for one that macOS does not serve natively, and for a model that has no record at all. For the last case, `ojd record draft` starts a record. `controller show` names the choice and the layer it comes from, and the serving route and persona the serving policy decides (`serving` with `route`, `persona`, and `reason` in `--json`). With `--json`, it prints the `controller`, `identity`, `server` and `previous` (`system` or `ojd`), `file`, `created`, and `dryRun`. For more information, see [Choose who drives the controller](Controller-Records.md#choose-who-drives-the-controller).
- `controller suspend`: Stop OpenJoystickDriver from driving the controller until you resume it.
- `controller resume`: Let OpenJoystickDriver drive a suspended controller again.
- `controller disconnect`: Close a classic Bluetooth controller's connection. The controller stays paired and reconnects when you turn it on again. The command waits at least 6 seconds for Bluetooth to confirm. The service cannot disconnect a Bluetooth Low Energy controller: turn it off or disconnect it in System Settings > Bluetooth.
- `controller calibrate`: Show the motion calibration of a controller with a gyro. `start` collects gyro drift while the controller lies still, `pause` stops the collection, and `reset` removes the calibration. Motion lean and steering bindings use the calibration. With `--json`, it prints a `Calibration` object with `controller`, `calibrated`, `collecting`, and `offsetDegreesPerSecond` with `x`, `y`, and `z`.
- `controller pair`: Combine a left and a right Joy-Con into one controller that uses `PROFILE`. `PROFILE` must be a paired Joy-Con profile. For more information, see [Sticks, triggers, touchpad, and motion](Sticks-Triggers-Touchpad-and-Motion.md). Hardware behavior of Joy-Con pairing is not verified.
- `controller unpair`: Separate a Joy-Con pair. `PAIR` is the session ID that `controller pair` prints, or the ID of either Joy-Con.

With `--json`, `controller pair` and `controller unpair` print a `ControllerPair` object with `session`, `left`, `right`, `profile`, and `gyro`. `controller suspend`, `resume`, and `disconnect` print a `ControllerSession` object. `controller rumble`, `light`, and `player` print a `Status` with `status` `Success`, and `details` has `controller` and `results`. When the controller does not deliver a result, the command prints no JSON: it exits with a non-zero code and writes the error on standard error.

## profile

Create, change, activate, and move remapping profiles. Every `profile` command needs the service running. For more information, see [Creating a profile](Remapping-Profiles.md).

```text
ojd profile list
ojd profile show PROFILE
ojd profile create NAME --controller CONTROLLER [--app BUNDLE-ID] [--virtual-gamepad disabled|mapped|passthrough] [--physical-input shared|exclusive] [--template gyro-stick [--stick left|right] [--activation SOURCE]]
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
- `profile create`: Create an empty, inactive profile for one controller model. `--controller` is `VVVV:PPPP` or the ID of a connected controller. The profile applies in every app unless `--app` gives an app ID. `--virtual-gamepad` sets what the virtual gamepad sends: nothing (`disabled`), bound controls only (`mapped`), or also every control that no binding uses (`passthrough`, the default). `--physical-input` sets whether macOS still sees the controller (`shared`, the default) or OpenJoystickDriver takes it (`exclusive`). `--template gyro-stick` starts from a gyro to stick profile instead: `--stick` picks `left` or `right` (the default), and `--activation SOURCE`, such as `button:left-shoulder`, makes gyro output active only while that control is held; without it gyro output is always on. `--stick` and `--activation` need `--template`. The command fails for a model with no motion sensor and names the model. See [Create a Gyro to Stick Profile](Sticks-Triggers-Touchpad-and-Motion.md#create-a-gyro-to-stick-profile).
- `profile duplicate`: Copy a profile under a new name. The copy is inactive.
- `profile rename`: Give a profile a new name of 1 to 80 characters.
- `profile delete`: Delete a profile. An active profile stops applying. It asks first on a terminal and needs `--force` otherwise. `--dry-run` (`-n`) prints what would change and changes nothing.
- `profile activate`: Apply a profile. It replaces the active profile of the same controller model and app scope. A profile with the virtual gamepad set to `mapped` that sends nothing to the gamepad, keyboard, pointer, or controller and sets no light color produces no output. To activate such a profile, add `--allow-empty`.
- `profile deactivate`: Stop applying a profile. The controller then sends its own input.
- `profile edit`: Open the profile file in `$VISUAL`, `$EDITOR`, or `vi`, then check and save it. Use it to change chords, sequences, layers, stick and trigger tuning, and the app scope. It needs a terminal. Without one, export the profile, change the file, and import it. For the file format, see [Profile file reference](Profile-File-Reference.md).
- `profile recover`: Repair the problems that `profile list` reports. It acts on each issue: it removes a damaged profile file and resets a damaged active profile list. The service first backs up each file beside the original, under a name that contains `.backup-`. It asks first on a terminal and needs `--force` otherwise. `--dry-run` (`-n`) prints what would change and changes nothing. With `--plain`, it prints one line for each issue, with its ID and kind.
- `profile import`: Add a profile from a file that `profile export` wrote. Use `-` to read the file from stdin. A profile with the same ID as an existing profile replaces it. A file that is not a valid profile exits with code 1 and error `E3008`, and one with a missing or unsupported `apiVersion` exits with code 1 and error `E5001`. `profile edit` and `profile set` give the same codes.
- `profile validate`: Check a profile file without importing it. Use `-` to read the file from stdin. It needs no running service. It exits with code 1 and error `E3008` when the profile is not valid, and with `E5001` when its `apiVersion` is missing or unsupported.
- `profile export`: Print a profile file to stdout, or write it to `--output`. The file is JSON, so `--json` and `--plain` do not change the output.
- `profile get`: Print one value from the profile file. `KEY` is a path of member names and array indexes joined by dots, such as `stickMappings.0.tuning.innerDeadzone`. A string prints alone, and any other value prints as JSON. A key with no value exits 1.
- `profile set`: Change one value in the profile file. `VALUE` is read as JSON, or as a string when it is not JSON, so `0.2` is a number and `space` is a string. To set the string `true`, write `'"true"'`. `null` removes the key or the array item, and the index one past the end of an array adds an item. OJD checks the whole profile before it saves it and refuses a change that makes it invalid or changes `id`. For example, `ojd profile set Racing physicalColor '{"red":255,"green":0,"blue":0}'`.

With `--json`, a profile is an object with `id`, `name`, `controller`, `scope` (`global` or `app:BUNDLE-ID`), `active`, and `bindings`, the number of bindings. `profile list` prints a `ProfileList` with `items`, one profile each, and an empty `metadata`. The issues it finds go to stderr as warnings, one line each. `profile show` prints a `Profile` with `profile` and `document`, the full profile file. `profile create`, `duplicate`, `rename`, `activate`, `deactivate`, `edit`, `set`, and `import` print a `Profile` too, with `profile` and `changed` (`replaced` for `import`). `profile get` prints a `ProfileValue` with `key` and `value`. `profile delete` and `profile recover` print a `Status`, and `details` holds `deleted` and `dryRun` for `delete`, and `recovered`, each with `id`, `kind`, `code`, and `message`, and `dryRun` for `recover`. `profile validate` prints a `ProfileValidation` with `valid`, then `id`, `name`, `controller`, and `scope` for a valid profile or `problem` for an invalid one.

## binding

List, set, and clear the bindings of a profile. A binding sends a target when you use a control on the controller. Every `binding` command needs the service running. For more information, see [Assigning buttons and actions](Bindings-and-Actions.md).

```text
ojd binding list PROFILE
ojd binding set PROFILE SOURCE TARGET [options]
ojd binding clear PROFILE SOURCE... [--force] [--dry-run]
ojd binding clear PROFILE --all [--force] [--dry-run]
```

Every part that names a control, direction, key or modifier is lowercase kebab-case: `LeftStickX` is `left-stick-x`, `KeyA` is `key-a` and `DpadUp` is `dpad-up`.

`SOURCE` is one of these forms:

- `button:NAME`, such as `button:south` or `button:left-shoulder`
- `dpad:DIRECTION`
- `axis:NAME`, or `axis:NAME:negative` or `axis:NAME:positive` for one direction, such as `axis:left-stick-x:positive`
- `trigger:NAME:STAGE`
- `motion:lean:DIRECTION`
- `touch:SURFACE:contact`, `touch:SURFACE:grid:COLUMNS:ROWS:COLUMN:ROW`, or `touch:SURFACE:swipe:DIRECTION:DISTANCE`

`TARGET` is one of these forms:

- `key:KEY`, with modifiers as `key:KEY:mods=alt,control,meta,shift`
- `mouse:BUTTON`, `move:x`, `move:y`, `scroll:x`, or `scroll:y`
- `gamepad:button:NAME`, `gamepad:dpad:DIRECTION`, or `gamepad:axis:NAME`
- `physical:...` for rumble, lights, and adaptive triggers
- `macro:NAME` for a macro of the profile, matched without regard to case, and created with `ojd macro set`. It exits with code 1 and changes nothing when the profile has no such macro. `binding list` and `profile show` print the macro's name.

`ojd profile show` prints bindings in the same forms.

- `binding list`: List a profile's bindings.
- `binding set`: Bind a source to a target. A source has one binding, so this replaces the binding that the source has, and keeps its ID. The options are:
  - `--behavior`: When the target fires: `hold` (the default for a new binding), `toggle`, `tap-on-press`, `tap-on-release`, `pulse`, `press`, or `release`.
  - `--pulse-ms`: How long `pulse` holds the target, 1 to 5000 ms. The default is 100.
  - `--deadzone`, `--gain`, `--invert`, `--response-curve`, and `--digital-threshold`: Tuning for axis sources. The dead zone is 0 to 0.95 (default 0.1), the gain is 0.1 to 10 (default 1), and the response curve is `linear` (the default), `ease-in`, `ease-out`, or `smooth-step`. The digital threshold is the travel that counts as a press for button targets (default 0.5).
  - `--turbo-rate` and `--turbo-duty`: Repeat the target this many times a second while the source is held. The duty is the part of each cycle that the target is held, above 0 and below 1. Turbo cannot be used with `--long-hold` or `--multi-tap`.
  - `--turbo-delay MS` and `--turbo-max COUNT`: Wait this many milliseconds (0 to 2500) after the first press before the first repeat, and stop after this many repeats (1 to 500) until the source is released. Both need `--turbo-rate` and `--turbo-duty`.
  - `--long-hold MS:TARGET`: Send another target when the source is held this long, such as `500:key:key-b`.
  - `--multi-tap COUNT:MS:TARGET`: Send another target when the source is tapped COUNT times (2 to 5), each press within MS milliseconds (50 to 1000) of the last release, such as `3:300:key:key-c`. Repeat the option for more counts. The base target waits for the longest window; `ojd binding list` shows it as `tap-delay`.
  - `--actions-json`: More actions, as a JSON array in the form that `ojd profile export` writes.
- `binding clear`: Remove the bindings of the given sources. It exits with code 1 and changes nothing when a source has no binding. `--all` removes every binding, chord, sequence, and layer. Stick, trigger, touch, motion, and output settings stay. `--all` asks first on a terminal and needs `--force` otherwise. `--dry-run` (`-n`) prints what would change and changes nothing. When the result leaves a profile that is active on a connected controller with no inputs while OJD seizes the physical input, the command prints a warning on stderr that names `ojd binding set` and `ojd profile deactivate`, and still exits with code 0.

With `--json`, a binding is an object with `id`, `source`, `target`, and `behavior`. `binding list` prints a `BindingList` with `items`, one binding each, and an empty `metadata`. Each item also has `profile`, the profile it came from. `binding set` prints a `Binding` with `profile`, `binding`, and `replaced`, and `binding clear` prints a `Status`, with `profile`, `removed` (the sources), `all`, and `dryRun` in `details`.

## macro

List, show, set, and remove the macros of a profile. A macro is a named list of steps that a binding runs with the target `macro:NAME`. Every `macro` command needs the service running. Hardware status: Not checked.

```sh
ojd macro list PROFILE
ojd macro show PROFILE NAME
ojd macro set PROFILE NAME --step STEP... [--repeat COUNT|while-held] [--while-running ignore|restart] [--interrupt-on-release]
ojd macro remove PROFILE NAME [--force]
```

A profile holds at most 16 macros, a macro at most 32 steps, and names are 1 to 40 characters and unique without regard to case.

- `macro list`: List a profile's macros with their repeat mode and number of steps.
- `macro show`: Show a macro's options and steps.
- `macro set`: Create a macro, or replace the macro of the same name and keep its ID. A replaced macro keeps the options that you leave out. `--step` is one step, in order, and the option repeats for more steps:
  - `tap:TARGET`, `press:TARGET`, `release:TARGET`: Send the target as a click, a press, or a release. `TARGET` has the forms of `ojd binding set`.
  - `wait:MS`: Wait 0 to 5000 milliseconds.
  - `chord:MS:TARGET+TARGET`: Hold the targets together for MS milliseconds.
  - `--repeat`: How many passes the macro runs, 1 to 500 (the default is 1), or `while-held` to run until the source is released.
  - `--while-running`: What a press of the source does while the macro runs: `ignore` (the default) or `restart`.
  - `--interrupt-on-release` or `--no-interrupt-on-release`: Whether releasing the source stops the macro (the default is no).
- `macro remove`: Remove a macro. It asks first on a terminal and needs `--force` otherwise. It fails and changes nothing while a binding runs the macro; clear or change that binding first.

A step or `--repeat` value that is not in these forms exits with code 64. A macro that does not exist exits with code 1.

With `--json`, a macro is an object with `id`, `name`, `repeat`, `whileRunning` (the profile document value, `Ignore` or `Restart`), `interruptOnRelease`, and `steps`, each in the `--step` form. `macro list` prints a `MacroList` with `items`, each with `profile` and `macro`. `macro show` prints a `Macro` with `profile` and `macro`, and `macro set` prints a `Macro` with `profile`, `macro`, and `replaced`. `macro remove` prints a `Status`, with `profile` and `removed` (the name) in `details`.

## virtual

Show and choose the virtual gamepad that OpenJoystickDriver publishes for a controller. A choice applies to every controller of the same model, unless you add `--unit`: then it applies to that controller only, by its unit ID, and wins over its model's choice.

```text
ojd virtual show [CONTROLLER]
ojd virtual set PROFILE CONTROLLER [--unit]
ojd virtual reset [CONTROLLER] [--unit] [--all] [--force] [--dry-run]
ojd virtual feed --as PROFILE
ojd virtual export-mapping [PROFILE] [--format sdl|w3c]
ojd virtual launch [--sdl-gamecontroller-backend] [--] PROGRAM [ARGUMENTS...]
```

- `virtual show`: Show each controller's virtual gamepad and the profiles you can choose. Name a controller to show only that one. With `--json`, it prints a `VirtualGamepadConfiguration`, and `overrideScope` says whether a stored choice is the controller's own (`Unit`) or its model's (`Model`). A controller with a live profile also carries `sdl` (`guid`, `mapping`, and `worksWithDefaultSDLHints`) and `w3c` (`id`, `buttons`, `axes`), the mapping of that profile as `virtual export-mapping` prints it. When the profile does not work with SDL's default hints, the human output adds a note line under the controller. `GameControllerCompatible` states that it does not work with them; `SDLCompatible` and `Generic` state that they work.
- `virtual export-mapping`: Print how a game reads each virtual gamepad profile. With `--format sdl` (the default), it prints one SDL mapping line per profile, which is a valid SDL mapping file. With `--format w3c`, it prints the W3C Gamepad description: the standard layout's button and axis indices, and the input of the virtual gamepad that supplies each. Name a profile to print only that one. With `--json`, it prints a `VirtualGamepadMapping` with `format` and `mappings`, one entry per profile with `profile` and the requested `sdl` or `w3c`. The mapping is derived from the profile's report descriptor, so it needs no edit when a profile changes. Each `sdl` entry carries `worksWithDefaultSDLHints`, which the profile's record states. A profile that does not work with the default SDL hints gets a note, as a `#` comment line that keeps the output a valid mapping file, before its mapping; the bundled `SDLCompatible` (`045E:0B0C`) and `Generic` (`1209:4A4F`) state that they work, and `GameControllerCompatible` (`045E:0B13`) states that it does not. `Generic` has a GUID with no CRC.
- `virtual launch`: Run a program with the SDL mapping of the connected virtual gamepads. It sets `SDL_GAMECONTROLLERCONFIG` to the mapping line of each profile that a connected controller serves, in the order of `virtual export-mapping`, one line per profile and separated by newlines, so SDL in the program lists those gamepads. A value that `SDL_GAMECONTROLLERCONFIG` already has stays first and the mapping lines follow it. With `--sdl-gamecontroller-backend`, it also sets `SDL_JOYSTICK_MFI=1`, `SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1`, `SDL_JOYSTICK_IOKIT=0`, and `SDL_JOYSTICK_HIDAPI=0`, which make SDL read controllers only through Apple's GameController framework, and each replaces a value that is already set. `SDL_JOYSTICK_HIDAPI=0` switches off every SDL HIDAPI driver, so no further HIDAPI variable is set. A run of SDL 3.4.18 listed the `SDLCompatible` profile only with `SDL_JOYSTICK_HIDAPI=0`, through the GameController framework as `045E:02E0`; PCSX2 2.8.2 (SDL 3.4.12) and DuckStation (SDL 3.4.16) map it with the default hints. Without that option no other variable changes, and with it no variable changes outside the program, no profile choice changes, and no other program is affected. `PROGRAM` is a path, a name that `PATH` finds, or an `.app`, which runs its main executable. The program keeps the terminal and the standard streams of `ojd`, so `--json` and `--plain` do not apply and exit with code 64. Put `--` before `PROGRAM` when its arguments are also `ojd` options. `ojd` exits with the program's exit code, or 128 plus the signal that ended it. Stopping `ojd` with Control-C or SIGTERM stops the program. When no connected controller has a virtual gamepad, it exits with code 1 and error `E2013` and starts nothing; a program that cannot be found or started fails with `E2033`. When a served profile does not work with SDL's default hints, it prints the note on standard error before it starts the program, unless `--quiet` or `--sdl-gamecontroller-backend` is set.
- `virtual set`: Choose the profile for the controller's model. With `--unit`, choose it for that controller only. A controller with no unit ID cannot take `--unit`. The profiles are `sdl-compatible`, `game-controller-compatible`, and `generic`. Automatic selection never picks `game-controller-compatible`, so this command is the only way to publish it.
- `virtual reset`: Return the controller's model to automatic selection. With `--unit`, it removes only that controller's own choice, so its model's choice applies again. A persona file that sets its own `identity`, or one from a package, stays: the command exits with code 1 and names the file (`overrideFileKept`), and you edit or delete that file yourself. `--unit` cannot be used with `--all`. `--all` returns every model, including models that are not connected, and exits with code 1 when a persona file with its own `identity` stays; persona files from packages stay with no error. It asks first on a terminal and needs `--force` otherwise. `--dry-run` (`-n`) prints what would change and changes nothing. With `--json`, `virtual set` and `virtual reset` print a `VirtualGamepadChange`, except `virtual reset --all`, which prints a `Status` with `{"reset":"all"}` in `details`.
- `virtual feed`: Publish a virtual gamepad with the `--as` profile and drive it from standard input. Write one JSON object per line, such as `{"buttons":["South"],"dpad":["DpadUp"],"axes":{"LeftStickX":0.5,"RightTrigger":1}}`. Buttons, D-pad directions, and stick axes take the names of `button:`, `dpad:`, and `axis:` binding sources, and the triggers are the axes `LeftTrigger` and `RightTrigger`. A missing control is neutral. Sticks run from -1 to 1 with Y down, and triggers run from 0 to 1. Frames play in order, each for at least 8 ms; `holdMilliseconds`, from 0 to 60000, keeps a frame longer. The command ends after the last frame has played. Each rumble command a game sends to the virtual gamepad is printed as one `RumbleCommand` object per line, with a `type` of `SetRumble` or `StopRumble`. The gamepad is removed when the input ends, on Control-C, or when the service gets no update for 2 seconds. A line that is not a frame, such as one with an unknown key or a button listed twice, exits with code 64. The service runs at most 4 feeds from this command, and endpoint clients have 4 more of their own.

## record

Draft, list, check, install, or remove controller records. Only `record draft` needs the service. For more information, see [Adding or changing a controller record](Controller-Records.md).

```text
ojd record draft CONTROLLER [--duration SECONDS | --from-sdl]
ojd record list [--bundled]
ojd record show VVVV:PPPP
ojd record validate FILE|-
ojd record install FILE|- [--force] [--dry-run]
ojd record remove VVVV:PPPP [--force] [--dry-run]
ojd record test VVVV:PPPP --packets CAPTURE --expect STATE
```

`FILE` is a record file. Use `-` to read the record from stdin.

- `record draft`: Read a connected controller's HID report descriptor, capture its input reports for `--duration` seconds (10 by default) while you press each control, and print a record to start from. The record is a `Controller` for a model without a bundled record and a `ControllerPatch` otherwise. It maps the buttons, sticks, triggers, and hat that the descriptor states plainly, with the `HIDReportLayout` family, or names `HIDDescriptor` when nothing maps. Each report byte that changed during the capture is listed on stderr with its lowest and highest value. It exits with code 1 when nothing maps for a model with a bundled record. With `--from-sdl`, it captures nothing: it converts the SDL_GameControllerDB line of the connected controller against its HID elements and prints a `Controller` record with the `HIDDescriptor` family and that `hidUsageMap`. It exits with code 1 and `E2012` when the database has no line, `E5008` and the reason when the line does not convert, and `E2013` when the model has a bundled record, the controller cannot be read, or its descriptor fails the `HIDDescriptor` contract.
- `record list`: List every controller record, with its model, protocol family, layer (`Bundled`, `Package`, or `User` with `--json`), and file. It names each of your files that OpenJoystickDriver skipped, and each package record that it ignores, and why, on stderr, also with `--json`. `--bundled` lists the bundled records alone.
- `record show`: Show one model's effective record and the layer of each top-level field. It exits with code 1 when no record exists for the model.
- `record validate`: Check a record without installing it. It shows the kind (`Controller` or `ControllerPatch`), the model, the family, the file name, and whether the USB driver extension can claim the controller. It exits with code 1 when the record is not valid.
- `record install`: Check a record and write it to your record folder as `vvvv-pppp.json`. To replace the record already installed for that model, it asks first on a terminal and needs `--force` otherwise. `--dry-run` (`-n`) checks the record and prints where it would go, and writes nothing. It exits with code 1 and writes nothing when the record is not valid.
- `record remove`: Delete your record for a model. It asks first on a terminal and needs `--force` otherwise. `--dry-run` (`-n`) prints what would change and changes nothing. It exits with code 1 when you have no record for the model.

- `record test`: Replay captured reports through a model's record and compare the parsed controller state with the state you expect. It needs no service. `CAPTURE` is a file of the lines that `ojd controller capture --json` prints, one packet per line, and only received packets count. `STATE` is a JSON file in the shape of one line of `ojd controller watch --json`. The `connection` field is not compared. The state after the last report that carried input is the one compared. On a match it exits with code 0. On a mismatch it prints each field that differs, with its expected and parsed value, and exits with code 1 and error `E2022`. It exits with code 1 and error `E2011` when the capture or the state is not valid, no report in the capture carries input, the parser rejects a report, or the record has no parser that runs without a device. It exits with code 64 when a file cannot be read.

With `--json`, `record test` prints a `RecordTestResult` with `identity`, `matches`, `inputReports`, and `differences`, each with `field`, `expected`, and `actual`. `record draft` prints a `RecordDraft` with `identity`, `name`, `operation`, `family`, `report` (`id` and `length`, absent when no report was chosen), `capturedReports`, `changedBytes`, each with `byte`, `minimum`, and `maximum`, and `record`. With `--plain`, it prints one line for each changed byte: its offset, lowest value, and highest value. `record list` prints a `ControllerRecordList` with `items`, each with `identity`, `vendorID`, `productID`, `family`, `layer`, and `file`, and an empty `metadata`. `record show` prints a `ControllerRecord` with `identity`, `family`, `layer`, `file`, `transport` (`HID` or `USB`), `transportClaim` (`Claimed` or `Unclaimed`, for `USB` only), `fields`, and `record`. `record validate` prints a `RecordValidation` with `valid`, and `problem` or the record's `operation`, `identity`, `family`, `fileName`, `transport`, and `transportClaim`. `record install` prints a `ControllerRecord` with `installed`, `replaced`, `dryRun`, and `record`, and `record remove` prints a `Status`, with `removed` and `dryRun` in `details`.

## mod

Validate, install, list, or remove mod packages. A package is a folder with a `mod.json` manifest. None of these commands needs the service. For more information, see [Writing controller mods](Writing-Controller-Mods.md).

```text
ojd mod validate FOLDER
ojd mod install FOLDER [--force] [--dry-run]
ojd mod list
ojd mod remove NAME [--force] [--dry-run]
```

- `mod validate`: Check a package folder without installing it: the manifest, whether `requires` includes this version, the listed files, and clashes with your files and other packages. It exits with code 1 and the `E4xxx` or `E5001` code when the package is refused.
- `mod install`: Check the package and install it to `Packages/NAME` in the OpenJoystickDriver folder. The running service applies it. A package of the same name that is installed is refused with E4005 unless you pass `--force`. `--force` never overrides `requires`, a clash, or an invalid file. `--dry-run` (`-n`) checks the package and writes nothing.
- `mod list`: List each installed package with its version, author, and files. A package that OpenJoystickDriver does not use, such as one whose `requires` leaves out this version, shows the reason and its code.
- `mod remove`: Delete one installed package. It asks first on a terminal and needs `--force` otherwise. `--dry-run` (`-n`) changes nothing. It exits with code 1 and E4006 when the package is not installed.

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

With `--json`, each command prints a `Service` object, `{"state": "running"}` or `{"state": "stopped"}` besides `apiVersion` and `kind`. With `--plain`, it prints `state` and the state.

## permission

List the macOS permissions OpenJoystickDriver needs, or ask the service to request them.

```text
ojd permission list
ojd permission request [input-read] [input-inject]
```

- `permission list`: Show each permission, its state (`Granted`, `Denied`, or `Unknown` with `--json`; `granted`, `denied`, or `unknown` with `--plain`), and what OpenJoystickDriver uses it for. The permissions are `input-read`, `input-inject`, `usb-transport`, and `post-event` (`InputRead`, `InputInject`, `USBTransport`, and `PostEvent` with `--json`). `post-event` is the access that lets remapped keyboard, pointer, and scroll events reach other apps; its state is `granted`, or `denied` when it is not authorized. When the service is stopped, `ojd` reads the states itself and says so on stderr; it cannot tell then whether the active profile needs `post-event`.
- `permission request`: Ask the service to request each permission you name, or both `input-read` and `input-inject` when you name none. macOS shows its own prompt. The command never prompts in the terminal. It exits with code 77 when a permission is still not granted.

With `--json`, `permission list` prints a `PermissionList` with `items`, each with `id`, `name`, `state`, and `purpose`. The `PostEvent` item also has `requiredByActiveProfile` (`true` or `false`) when the service reported it. With `--plain`, the `post-event` row has a third column, `required` or `not-required`, under the same condition.

## extension

Show, activate, or deactivate the DriverKit system extension.

```text
ojd transport-extension status
ojd transport-extension activate
ojd transport-extension deactivate
```

- `transport-extension status`: Show whether the extension is in the app (`bundle`: `Present`, `Missing`, or `Invalid` with `--json`) and registered with macOS (`registration`: `Active`, `Inactive`, `Absent`, or `Unavailable`). It works when the service is stopped. It exits with code 1 when the registration is `Unavailable`.
- `extension activate`: Ask macOS to activate the extension. macOS can ask you to approve it in System Settings. The command then reports that it awaits approval (`AwaitingApproval` with `--json`) and exits with code 0.
- `extension deactivate`: Ask macOS to deactivate the extension. Connected controllers return to macOS.

`activate` and `deactivate` need the `ojd` inside `/Applications/OpenJoystickDriver.app`, or a link to it. With `--json`, `status`, `activate`, and `deactivate` print a `TransportExtension`, and `activate` and `deactivate` have `state`: `Active`, `Inactive`, or `AwaitingApproval`.

## setting

List, read, or change app settings. The service applies each setting, so these commands need it running.

```text
ojd setting list
ojd setting get KEY
ojd setting set KEY true|false
ojd setting reset [--force]
ojd setting test-notification
```

The keys are:

- `launchAtLogin`: the macOS login item. `get` reads it from macOS, so it includes changes made in System Settings, and `set` registers or unregisters the item. A change made with `ojd setting` or in the app also records whether you opted out, so OJD does not register itself again at the next start. A change made only in System Settings records nothing.
- `showInMenuBar`: show the OJD item in the menu bar. It is on by default.
- `showInDock`: always show the OJD icon in the Dock. With it off, the icon shows only while a window (main, Settings, Input Test) is open. It is off by default. `showInMenuBar` and `showInDock` cannot both be off: the change that would turn off the last one fails.
- `notify.controllerConnected`: notify when a controller connects or needs attention.
- `notify.controllerDisconnected`: notify when a controller disconnects.
- `notify.profileActivated`: notify when a profile is activated or switched.
- `notify.profileDeactivated`: notify when the active profile is turned off.
- `notify.sounds`: play a sound with notifications. `showInMenuBar` is also on by default; every other key is off by default.
- `updates.checkAutomatically`: check for updates when the app starts.
- `updates.includePrereleases`: include prereleases when checking for updates.
- `developerTools`: show the developer tools.

Settings live in `Settings.json`. A setting your file at `~/Library/Application Support/OpenJoystickDriver/Settings.json` leaves out takes its built-in default. `setting set` writes that file. A file with an unsupported `apiVersion` is refused with `E5001`. A file that is damaged, or that turns off both `showInMenuBar` and `showInDock` (for example `{"showInMenuBar": false}`, because `showInDock` is off by default), is refused too, and the app shows an alert for it at launch. `setting reset` moves `Settings.json` to the Trash so every setting returns to its default; it asks for confirmation unless you pass `--force`, works on the file itself so it needs no running service, and with no file it changes nothing. With `--json` it prints a `Status` with `details` holding `file` and `moved`. `setting test-notification` asks the service to announce a test notification to the open app, which shows it, the same as **Send Test Notification** in **Settings**, and waits for the app to report. The first app to ask the service for news takes the announcement; no app taking it within 3 seconds, or the app not reporting within 30 seconds, fails with `E2036` and exit status 69. Without `--timeout` the command waits up to 38 seconds for the service's answer, the 3 and the 30 plus 5 for the reply; `--timeout` sets that limit. Notifications that are not allowed for OJD fail with `E2037` and exit status 77; allow them in the system notification settings. A delivery the system rejects fails with `E2006` and the system's reason, and a stopped service with `E2004`. With `--json` it prints a `Status` with `details` holding `outcome` (`Shown`), and `--plain` prints `shown`. `setting get` prints `true` or `false` alone. With `--json`, `setting list` prints a `SettingList` with `items`, each with `key`, `value`, and `description`, and `setting get` and `setting set` print a `Setting` with `key` and `value`.

## config

Show the effective tuning values and the layer that set each one. It works without the service, which adds only the profile rows.

```text
ojd config show [--controller VVVV:PPPP]
```

Without `--controller`, it shows `Controllers/all.patch.json` against the driver defaults, and marks each key with the protocol families whose drivers read it, such as `read by: SonyDualShock4, SonySixaxis` for `inputLivenessTimeoutMs`. The families come from the controller records, so they follow the catalog. When the service runs with a controller connected and `all.patch.json` sets a key that no connected controller reads, it prints one warning for that key on stderr, which `--json` and `--plain` leave out of stdout. When some record ignores a key that `Controllers/all.patch.json` sets but the service is not running or no controller is connected, it prints one note on stderr that the check was skipped. With `--controller`, it shows the record for that model: each value comes from `driver`, `global`, `bundled`, or `user`. When the service runs and a profile is active for that model, it adds one `profile` row per stick mapping, keyed as `profile get` names it, such as `stickMappings.0.tuning.innerDeadzone`. A profile value calibrates that mapping and does not replace the record's `stickDeadzone`. See [Set a Default for Every Controller](Controller-Records.md#set-a-default-for-every-controller). With `--json`, it prints a `Configuration` with `profile` (the active profile's name, when it shows rows), `defaultsFile`, `defaultsProblem` when the file is invalid, and `values`, each with `key`, `layer`, `value` when set, and `families` (the reading families) without `--controller`. `--plain` prints `key`, `value`, and `layer` per line, plus the families joined by commas without `--controller`.

Set or remove one tuning key in your own records, with the Swift record writer the app uses.

```text
ojd config set KEY VALUE [--controller VVVV:PPPP]
ojd config unset KEY [--controller VVVV:PPPP]
```

With `--controller`, `set` writes the key to your record of that model: your Controller file when you have one, else the ControllerPatch file `vvvv-pppp.patch.json`, which patches the bundled record or an installed package's record. Without it, `set` writes `Controllers/all.patch.json`, which applies to every controller. `VALUE` must be valid as it is in a record: `stickDeadzone` is more than 0 and less than 1, and an integer key takes a whole number. A value the record refuses, a name that is not a tuning key, a key the model's driver does not read, and a model without a record all change nothing and print an error. `unset` removes the key and the `tuning` section with its last key. It removes a patch file left with no key, and it refuses a key your records do not set. The service applies the change to connected controllers without a replug. `ojd config show` then prints the value in the `user` layer, or `global` for `all.patch.json`.

## access

Turn on the endpoint and choose which programs may read controllers or drive a virtual gamepad through it. The endpoint is a local socket that granted programs use, and an optional WebSocket for web pages. For its protocol, see [Read the Endpoint](Automating-OpenJoystickDriver.md#read-the-endpoint). These commands need the service running.

```text
ojd access status
ojd access enable [--force]
ojd access disable
ojd access list
ojd access grant CLIENT [--scope read|control]... [--force]
ojd access grant --token NAME [--origin URL]... [--scope read|control]... [--force]
ojd access revoke CLIENT|token:NAME [--scope read|control]...
ojd access web enable [--port PORT] [--automatic] [--force]
ojd access web disable
```

- `access status`: Show whether the endpoint is on, the path of its socket, and the connected clients. It also shows the WebSocket and the number of tokens. With `--json`, it prints an `EndpointAccess` with `enabled`, `socketPath`, `connections`, `grants`, `refused`, `web`, `tokens`, and `refusedTokens`, and `access enable` and `access disable` print the same kind. `access web enable` and `access web disable` print a `WebAccess`, and `access list` prints an `AccessSummary`. A grant and a refused client have a `publisher` with a `kind` (`Signed`, `Platform`, or `AdHoc`) and an `id`. Each connection has a `transport`: `Socket` or `Web`.
- `access enable`: Turn on the endpoint. It asks first. In a script, it needs `--force`. The endpoint is off until you run this command.
- `access disable`: Turn off the endpoint and close its connections. The grants stay.
- `access list`: List the granted clients and tokens, and the clients and tokens that the endpoint refused in the last 24 hours. Each client has an 8-character ID, and each token has the ID `token:NAME`.
- `access grant`: Allow a program to use the endpoint. `CLIENT` is the path of the program's app bundle or executable, or an ID from `access list`. `--scope` is `read` by default. The grant names the program's signature, so it stays valid when the program is updated or moved. It asks first, and in a script it needs `--force`.
- `access grant --token`: Create a token named `NAME` instead of granting a program. The command prints the token once; the service keeps only its hash. A client signs the service's challenge with the token in its `hello` and does not send the token. Each `--origin`, such as `http://127.0.0.1:8080`, lets web pages from that origin use the token on the WebSocket. A token without `--origin` works on the socket, and on the WebSocket from a program that sends no `Origin` header, such as a sandboxed app. With `--json`, it prints an `AccessToken` with `token` and `grant`. `access grant` without `--token` prints an `AccessGrant`.
- `access revoke`: Remove a client's or a token's grant. With `--scope`, it removes only those scopes. The endpoint closes each connection that loses a scope. With `--json`, it prints a `Status`.
- `access web enable`: Turn on the WebSocket on `127.0.0.1`. Without `--port`, it uses the saved port; the first time, the system picks a free port. `--port` names another from 1024 to 65535; `--automatic` lets the system pick a free port even when one is saved, and cannot be combined with `--port`. The port is saved, and `access status` shows it. It asks first, and in a script it needs `--force`. It is independent of `access enable`.
- `access web disable`: Turn off the WebSocket and close its connections. The tokens stay.

`access grant` accepts only a program signed with a Developer ID or Apple Development certificate, or signed by Apple. It refuses an ad-hoc signed or unsigned program, because any program can claim that signature. For a program that Apple signed, such as `python3`, every script that the program runs gets the access.

The `control` scope lets a program drive a virtual gamepad, so it can press buttons in any game. `read` does not include it, and `control` does not include `read`. A granted program uses `control` on the socket. On the WebSocket, only a token without `--origin` can use it, from a program that sends no `Origin` header; a web page cannot. `access grant --token` refuses `--origin` together with `--scope control`. When a grants file from an earlier build holds that combination, the service ignores the `control` scope of that token. See [Drive a virtual gamepad through the endpoint](Automating-OpenJoystickDriver.md#drive-a-virtual-gamepad-through-the-endpoint).

Any local program that reads a token can use it, including programs of other users on the same Mac when the WebSocket is on. Treat a token as a password, and revoke it when you no longer need it.

## log

Show the service logs or print the folder that holds them.

```text
ojd log show [--lines COUNT] [--follow]
ojd log path
ojd log export FILE [--lines COUNT] [--force]
```

- `log show`: Print the last lines of each service log, 100 by default and at most 10000. On a terminal, the output goes through `$PAGER`, or `less -FRX` when it is unset. Set `PAGER` to an empty value to turn paging off. `--follow` keeps printing new lines until you press Control-C. With `--json`, it prints a `LogSnapshot`, and with `--follow` one `LogEntry` per line, with `stream` and `line`.
- `log path`: Print the log folder. To open it in Finder, run `open "$(ojd log path)"`.
- `log export`: Write the last lines of each service log to `FILE`, 2000 by default and at most 10000, with your home folder shown as `~`. It does not replace an existing file unless you pass `--force`. Review the file before you share it. With `--json`, `log path` prints a `LogLocation` and `log export` prints a `Status` with `lines` and `path` in `details`.

## diagnose

Run every check and report what is wrong.

```text
ojd diagnose [--output PATH] [--soak SECONDS] [--frames SECONDS]
```

The checks are `service`, `transport-extension-bundle`, `transport-extension-registration`, `input-read`, `input-inject`, `controller-records`, `input-mapping`, `switch-placeholder-serial`, `config-files`, `usb-access`, `virtual-device`, `hid-input-drops`, and `runtime-health`. Each reports `Pass`, `Warn`, `Fail`, or `Skip` with `--json`, and `pass`, `warn`, `fail`, or `skip` with `--plain`. The `controller-records` check warns when OpenJoystickDriver skipped one of your controller record files. The `input-mapping` check warns, with `E5008`, for each connected controller whose SDL_GameControllerDB line was rejected, and names the reason; that controller keeps the standard HID usage map. The `switch-placeholder-serial` check warns for each connected `057E:2009` controller that reports serial `000000000001`, the identity and serial of a Nintendo Switch Pro Controller, and is skipped when no such controller is connected; it does not change the driver that binds the controller. The `config-files` check warns when it ignored your `Controllers/all.patch.json`, skipped one of your virtual device files, or found a `Personas` folder with files that it does not read. The `hid-input-drops` check warns when the system dropped input reports of a controller before the service read them, and names the controller and the count. Checks that need the service are skipped while it is stopped. While the service cannot be reached and left a record that its request listener stopped, the `service` check fails with `E2034`, its text, the error number and the time; a record whose process has ended only warns that the last listener stopped; a record that cannot be used also fails it, as `E2035` with the file and the reason. The command exits with code 1 when any check fails.

- `--output PATH`: Also write a support report to `PATH`. Read it before you share it.
- `--soak SECONDS`: Run the `runtime-health` check. It samples the service's memory, file descriptors, and CPU for 1 to 86400 seconds. Without `--soak`, that check is skipped. `--interval-ms`, `--rss-limit-mib`, and `--footprint-limit-mib` tune the sampling and set failure limits.
- `--frames SECONDS`: Summarize only the frames read in the last `SECONDS` seconds, from 1 to 15. The command writes a line to the error output that tells you to keep the sticks moving, waits `SECONDS` seconds, then asks the service once for the frames read in the last `SECONDS` seconds of its uptime clock; the human output names that window above the timing blocks. Only `--frames` measures `read-to-read` and stalls; without it, the summary covers the whole window of up to 15000 frames and has the stage gaps alone. A controller that reports only when an input changes, such as the Razer Wolverine V1 Tournament Edition, sends nothing while you hold the sticks still, so each pause in input counts as a stall: move the sticks the whole time `--frames` waits.

With `--json`, the output is a `Diagnosis` with `checks`, each with `id`, `status`, and `detail`, and `output` when you wrote one.

Each connected controller also lists the timing of its newest frames. Every frame carries a time in nanoseconds on the service's monotonic uptime clock for each stage it reached: `Read`, `Parse`, `Dispatch`, `DeliveryVirtualDevice`, and `DeliveryEndpoint`. The list shows the newest 8 frames of each controller, and it is empty while the service is stopped. `DeliveryVirtualDevice` is present only when the report reached the virtual device, so a failed or suppressed publish leaves it out. The endpoint polls the controller state, so `DeliveryEndpoint` goes on the controller's newest frame when the poll runs, and a frame replaced by a newer one before the poll gets none. With `--json`, the timings are `timings`, each with `controller`, `name`, `summary`, and `frames`. With `--plain`, each stage is a row of `timing`, controller, frame sequence, stage in kebab-case (`delivery-virtual-device`), and nanoseconds. Without either, each frame is one line after the checks. `--output` writes the same frames and summary to `data.frameTimings` of the support report, with the same stage names and nanoseconds, and an empty list while the service is stopped.

Eight frames are a few dozen milliseconds at a report rate of 125 to 1000 Hz, too short to show a stutter. So the service also keeps a window of each controller's newest 15000 frames, 15 seconds at 1000 Hz, and `ojd diagnose` summarizes it. To measure stutter, run `ojd diagnose --frames 10` and sweep the sticks while it waits, so the summary covers only that time. The summary has the number of frames in the window and the time from its first to its last `Read` stamp. For each gap it has the number of samples, the median (`p50`), the 99th percentile (`p99`, nearest rank) and the maximum: `read-to-parse`, `parse-to-dispatch`, `dispatch-to-delivery-virtual-device` and `dispatch-to-delivery-endpoint` for the stages a frame reached, and, with `--frames`, `read-to-read` for the time between the `Read` stamps of two consecutive frames. A gap that no frame measured is left out. A stall is a read interval longer than 3 times the median read interval of the window, so the threshold follows the report rate: it is 24 ms for a steady 125 Hz (8 ms between reports) and 3 ms for a steady 1000 Hz (1 ms). With `--frames`, the summary counts the stalls and gives the threshold. The whole window, the app and the support report have no read interval and no stall count, because they hold the pauses before and after the input. A `--frames` window with fewer than two frames has none either. A report that a newer one replaced before dispatch is no frame, so its interval joins the next one.

With `--json`, `summary` has `lastSeconds` (the seconds of `--frames`, absent without it), `frames`, `spanNanoseconds`, `gaps` (each with `gap`, `samples`, `p50Nanoseconds`, `p99Nanoseconds` and `maxNanoseconds`) and `stalls` (`thresholdNanoseconds` and `count`). With `--plain`, the rows start with `timing-summary` and the controller, then a name and the columns that name has, in nanoseconds:

| Name | Columns after the name |
| --- | --- |
| `window` | frames in the window, time span, seconds of `--frames` (empty without it) |
| a gap name in kebab-case | samples, median, 99th percentile, maximum |
| `stalls` | threshold, read intervals longer than the threshold (only with `--frames`) |

Without either flag, each controller gets one block before its frames: a header line, one line per gap in milliseconds, and the stall line.

## update

Check whether a newer release exists.

```text
ojd update check [--prerelease]
```

`--prerelease` includes prerelease versions. The command exits with code 1 when the check fails. With `--json`, it prints an `UpdateCheck` with `status` (`UpToDate`, `Available`, or `AheadOfLatestRelease` when the running version is newer than the latest release), `currentVersion`, `latestVersion`, `includePrereleases`, and `releaseURL` when an update is available.

## explain

Explain an error code.

```text
ojd explain CODE
```

`CODE` is an error code such as `E2004`, in any letter case.
The command works offline.
It prints the code, its area (endpoint, command line, or remapping), what it means, and the exit code of a command-line code or the wire value of a remapping code.
An unknown code is a usage error.
With `--json`, the output is an `ErrorExplanation` with `code`, `area`, `explanation`, and `exitCode` or `wire`.

## Further Reading

- [Command line](Command-Line.md)
- [Automating OpenJoystickDriver](Automating-OpenJoystickDriver.md)
- [Reporting a bug](Reporting-a-Bug.md)
