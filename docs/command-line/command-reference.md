# Command reference

This article lists every user, advanced, and support command of the OpenJoystickDriver command line.

Each command runs as `ojd COMMAND`. For more information about `ojd` and the global options, see [Using the command line](using-the-command-line.md). Commands marked "Advanced" or "Support" are for troubleshooting and testing. Most users do not need them.

## status

Show the driver and runtime status.

```text
status [--json]
app status [--json]
app ready
```

- `status`: Show driver and runtime status.
- `app status`: Show the same status. If the app does not run, both commands show the local permission state.
- `app ready`: Check that the app service is ready. It prints `ready` or an error. Support command.
- `--json`: Print JSON.

## controller

Inspect and control connected controllers.

### List and inspect

```text
controller list
controller state [VID PID] [--device ID] [--json]
```

- `controller list`: List connected controllers.
- `controller state`: Show the latest buttons, sticks, and triggers.
- `VID PID`: Vendor and product ID, in decimal or `0x` hexadecimal. Give both or neither.
- `--device ID`: Select one of several identical controllers.
- `--json`: Print JSON.

### Disconnect and resume

```text
controller disconnect [--vid VID] [--pid PID] [--device ID]
controller resume [--vid VID] [--pid PID] [--device ID]
controller disconnect-wireless [--vid VID] [--pid PID] [--device ID]
```

- `controller disconnect`: Suspend a controller. OpenJoystickDriver stops using it.
- `controller resume`: Resume a suspended controller.
- `controller disconnect-wireless`: Close the link of a Bluetooth controller.
- Give `--vid` and `--pid`, or `--device`, or all three.

### Virtual controller profile

Advanced. Override which virtual controller profile OpenJoystickDriver publishes for a model. For more information, see [How games see your controller](../playing-games/how-games-see-your-controller.md).

```text
controller virtual set PROFILE [--vid VID] [--pid PID] [--device ID]
controller virtual reset [--vid VID] [--pid PID] [--device ID]
controller virtual reset --all
```

- `controller virtual set`: Set the override. `PROFILE` is `hid-xbox-one-s-bt` or `hid-generic`.
- `controller virtual reset`: Return the controller to automatic selection.
- `--all`: Clear every override. Do not combine it with `--vid`, `--pid`, or `--device`.

### Packets and traces

Advanced. Show raw controller data. Give `VID PID` or `--device ID` as for `controller state`.

```text
controller packets [VID PID] [--device ID] [--limit N] [--json]
controller trace [VID PID] [--device ID] [--seconds N]
    [--interval-ms N] [--json-lines]
controller watch [VID PID] [--device ID] [--seconds N]
    [--interval-ms N] [--json-lines]
```

- `controller packets`: Show recent raw packets.
- `controller trace`: Capture raw packets for a set time.
- `controller watch`: Show changes of the normalized state for a set time.
- `--limit N`: Number of packets, 1 to 200. The default is 50.
- `--seconds N`: Duration, 1 to 3600. The default is 10.
- `--interval-ms N`: Sample interval, 8 to 1000. The default is 16.
- `--json`: Print JSON. `--json-lines`: Print one JSON object for each line.

### Physical output

Advanced. Send test output to a physical controller. The commands reject output that the controller driver does not support.

```text
controller output list [--json]
controller output rumble VID PID [--device ID] [--left N]
    [--right N] [--lt N] [--rt N] [--duration-ms N]
controller output player VID PID off|1|2|3|4 [--device ID]
controller output brightness VID PID N [--device ID]
controller output color VID PID RED GREEN BLUE [--device ID]
controller output plan VID PID [--device ID]
```

- `controller output list`: List controllers and the device ID of each. This is the default action.
- `controller output rumble`: Run the motors. `--left` and `--right` are 0 to 255, default 180. `--lt` and `--rt` are 0 to 255, default 0. `--duration-ms` is 0 to 5000, default 450. All values at zero stop the motors.
- `controller output player`: Set the player indicator.
- `controller output brightness`: Set the light brightness, 0 to 255.
- `controller output color`: Set the light color. Each value is 0 to 255.
- `controller output plan`: Show the output plan for the controller.

## map

Manage remapping profiles. This is an advanced command group. For the concepts, see [Remapping controls](../remapping-controls/README.md). Most people use the app instead.

A `PROFILE` is a profile UUID or an exact profile name. The name is not case-sensitive. The commands need the running app.

```text
map list [--json]
map show PROFILE [--json]
map create NAME --vid VID --pid PID
    (--target-app BUNDLE-ID | --global)
map update PROFILE [--name NAME] [--vid VID] [--pid PID]
    [--target-app BUNDLE-ID | --global]
map delete PROFILE
map enable PROFILE [--allow-empty]
map disable (--vid VID --pid PID | --profile PROFILE)
map import FILE
map export PROFILE [--output FILE]
map restore-default-input PROFILE
map clear-inputs PROFILE --confirm
```

- `map list`, `map show`: List profiles or show one profile.
- `map create`: Create a profile for one model. Use `--target-app` for one app or `--global`.
- `map update`: Change the name, model, or scope. The same command sets output and motion options. Run `ojd map --help` for the full list.
- `map delete`: Delete a profile.
- `map enable`: Make the profile active. The command refuses a profile that suppresses all controller input. Add `--allow-empty` to override.
- `map disable`: Deactivate the profile for a model, or by name or UUID.
- `map import`: Load a profile file.
- `map export`: Print the profile as JSON. With `--output FILE`, write it to the file and print the path.
- `map restore-default-input`: Restore the default input handling of the profile.
- `map clear-inputs`: Clear all input configuration of the profile. This needs `--confirm`.

Bindings, combinations, and layers:

```text
map bind PROFILE --source SOURCE --target TARGET [OPTIONS]
map unbind PROFILE --source SOURCE
map chord add PROFILE --sources S1,S2 --target TARGET
    [--mode modifier|simultaneous] [--window-ms N]
map chord delete PROFILE --id ID
map sequence add PROFILE --sources S1,S2 --window MS
    --target TARGET
map sequence delete PROFILE --id ID
map layer create PROFILE --name NAME --activator SOURCE
    --mode hold|toggle
map layer delete PROFILE --id ID
map layer bind PROFILE --layer ID --source S --target T
map layer unbind PROFILE --layer ID --source S
map layer list PROFILE
```

- A source looks like `button:NAME`, `dpad:DIRECTION`, or `axis:NAME`. An axis source can end in `:negative` or `:positive`.
- A target looks like `key:KEY`, `mouse:BUTTON`, `move:x`, `move:y`, `scroll:x`, or `scroll:y`. A key can add `:mods=command,control,option,shift`.
- Axis options include `--deadzone`, `--gain`, `--invert`, `--response-curve`, and `--digital-threshold`.
- Turbo options are `--turbo-rate` and `--turbo-duty`. They apply to keyboard and mouse targets only.
- Activation options are `--long-hold MS:TARGET` and `--double-tap MS:TARGET`. They cannot combine with turbo.

Motion, calibration, and Joy-Con:

```text
map calibration status|start|pause|reset
    --controller RUNTIME-ID
map joy-con pair PROFILE --left RUNTIME-ID --right RUNTIME-ID
map joy-con unpair --session SESSION-UUID
map permission status|request
```

- `map calibration`: Control motion calibration for a controller.
- `map joy-con pair`, `map joy-con unpair`: Pair or unpair two Joy-Con controllers.
- `map permission`: Show or request the access that profile output needs.
- The `map create` and `map update` commands also accept stick, trigger, and gyro options such as `--stick-mode` and `--gyro-output`. Run `ojd map --help` for the list.

## permissions

Support. Show, request, or explain the permissions that OpenJoystickDriver needs.

```text
permissions [status]
permissions request
permissions open [input|output]
permissions explain
```

- `permissions status`: Show the permission state. This is the default action. If the app does not respond, it shows the local state and exits with code 1.
- `permissions request`: Ask the app to request the required access. It exits with code 2 if access stays blocked, and opens the related privacy pane in System Settings.
- `permissions open`: Open **Input Monitoring** (`input`, the default) or **Accessibility** (`output`) in System Settings.
- `permissions explain`: List every permission that OpenJoystickDriver may request, with the reason.

## app

Manage the login item and read app logs.

```text
app login enable
app login disable
app logs [show|path|open] [--stream STREAM] [--lines N]
    [--json]
```

- `app login enable`: Register OpenJoystickDriver to open at login.
- `app login disable`: Delete the login item.
- `app logs show`: Print the app service logs. This is the default action. The output can contain device names and paths. Review it before you share it.
- `app logs path`: Print the log file paths.
- `app logs open`: Show the log files in Finder.
- `--stream STREAM`: `stdout`, `stderr`, or `both`.
- `--lines N`: Number of lines, 1 to 10000. The default is 100. Only for `show`.
- `--json`: Print JSON. Only for `show`.

The `app login` commands must run from the app in the `/Applications` folder, and the app signature must be valid. The `app status` and `app ready` commands are in [status](#status).

## extension

Support. Manage the optional Xbox USB system extension. For more information, see [Xbox USB driver extension](../connecting-controllers/xbox-usb-driver-extension.md).

```text
extension status
extension enable
extension disable
```

- `extension status`: Show if the extension is present in the app and registered in macOS.
- `extension enable`: Send an activation request. macOS may ask for your approval in System Settings.
- `extension disable`: Send a deactivation request.

The `enable` and `disable` commands wait up to 60 seconds. They exit with code 2 if the request does not finish.

## diagnose

Support. Collect diagnostic information.

```text
diagnose
diagnose runtime [--seconds N] [--interval-ms N]
    [--rss-limit-mib N] [--footprint-limit-mib N] [--json]
diagnose catalog [--all-apple] [--json]
diagnose report [--output FILE]
```

- `diagnose`: Print a summary of the system, extension, permissions, and USB devices.
- `diagnose runtime`: Sample the memory, CPU, file descriptors, and threads of the running app service. It needs the running app.
- `--seconds N`: Duration, 1 to 86400. The default is 60. A run under 60 seconds gives no conclusion.
- `--interval-ms N`: Sample interval, 100 to 60000. The default is 1000.
- `--rss-limit-mib N`, `--footprint-limit-mib N`: Memory limits, 0 to 65536. 0 disables the limit. The footprint default is 512.
- `diagnose catalog`: Compare the OpenJoystickDriver controller records with the controller list of macOS. `--all-apple` also lists every macOS entry.
- `diagnose report`: Write a JSON support report. Without `--output`, it writes a file named `OpenJoystickDriver-support-DATE-TIME.json` in the current folder. Review it before you share it, because it includes device product names.

For more information about the report, see [Reporting a bug](../troubleshooting/reporting-a-bug.md).

## test

Support. Test that the virtual controller delivers input.

```text
test [SECONDS]
```

- `SECONDS`: Test duration. If you omit it, or give a value that is not a positive whole number, the test runs for 5 seconds.
- The command needs the running app. It exits with code 1 unless the test passes.
- `test` does not show help. `test --help` runs the 5-second test.

## update

Check for a new OpenJoystickDriver version.

```text
update check [--prerelease] [--json] [--open]
```

- `update check`: Check GitHub tags for a newer version. The command does not download or install anything.
- `--prerelease`: Include prerelease versions.
- `--json`: Print JSON.
- `--open`: Open the release page only when an update exists.

The command exits with code 1 if the check fails. For more information, see [Updating OpenJoystickDriver](../updating-and-uninstalling/updating-openjoystickdriver.md).

## Further reading

- [Using the command line](using-the-command-line.md)
- [Creating a profile](../remapping-controls/creating-a-profile.md)
- [Reporting a bug](../troubleshooting/reporting-a-bug.md)
