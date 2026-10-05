# Automating OpenJoystickDriver

Use `ojd` in scripts and other programs to read controller state, change profiles, and drive a virtual gamepad.

## Choose the Interface

`ojd` is the interface for scripts and other programs. Run it as a subprocess, read its `--json` output, and check its exit code. For the global options, output rules, and exit codes, see [Command line](Command-Line.md).

The Swift package `OpenJoystickDriverKit` has an `ApplicationServiceClient`, but the service accepts a connection only from a process with the same code signature as the app. A program you build yourself cannot use it with a released app. Use `ojd` instead.

## Write a Script

1. Start the service and wait until it accepts requests: `ojd service start`.
1. Add `--no-input` to each command, so that a command fails instead of asking a question.
1. Add `--json` to each command whose output you read.
1. Check the exit code of each command. Code 69 means that the service is not running.

Commands that delete or reset data ask first on a terminal. In a script, they need `--force`. Run them first with `--dry-run` to see what they change.

```shell
ojd service start --timeout 30
ojd --no-input --json controller list | jq -r '.controllers[] | [.id, .name, .unit // ""] | @tsv'
```

## Read JSON Output

Keys and values in `--json` output are stable identifiers, and OJD never translates them. A command that streams, such as `ojd controller watch` or `ojd virtual feed`, prints one JSON object per line.

[`cli-output.schema.json`](../Resources/Schemas/cli-output.schema.json) describes the output of each command. Each command has one entry in `$defs`, named after its command path in lowerCamelCase: the entry for `ojd controller show` is `controllerShow`. Entries that start with `shared` are shapes that more than one command uses. The schema rejects keys that its release does not print, and a later release can add keys. Validate output against the schema from the same release.

Do not parse the human-readable output. It is translated, and it can change in each release.

## Name a Controller

Commands take a `CONTROLLER` operand. Use one of these forms:

- A unit ID, such as `U-` and 16 characters. It stays the same across reconnects and service restarts while the controller uses the same USB port. It changes when you connect the controller to a different port. Scripts can store it. A controller with no location ID has no unit ID.
- `VVVV:PPPP`, the hexadecimal vendor and product ID. It names a controller model. When two connected controllers have the same model, the command fails and lists them.
- An ID from `ojd controller list`. It lasts only until the service restarts, so do not store it.

`ojd controller list --json` gives the unit ID of each controller in `unit`.

## Watch Controllers

`ojd controller watch --all --json` reports every controller on one stream, so a program does not have to reconnect when a controller comes and goes. Each line is one JSON object with a `type` and the controller's `id` from `ojd controller list`:

- `connected`: a controller connected. `controller` has the fields of an `ojd controller list` entry, including `unit`. The first lines report the controllers already connected.
- `input`: the controller's input changed. `input` is the whole input state. With `--output`, `output` has the values of the controller's virtual gamepad.
- `disconnected`: the controller disconnected.

```shell
ojd --no-input controller watch --all --json | jq -c 'select(.type != "input")'
```

The service is polled every 16 ms for input, and every 250 ms for connected controllers.

## Read the Endpoint

A program that runs all the time can read controller events from the endpoint, a local socket, instead of running `ojd controller watch`. The endpoint is off by default, and it serves only the programs that you grant:

1. Turn on the endpoint: `ojd access enable`.
1. Grant your program: `ojd access grant /Applications/Reader.app`. To find the ID of a program that the endpoint refused, run `ojd access list`.
1. Read the socket path: `ojd --json access status | jq -r .socketPath`. It is in your user's temporary folder, and it exists only while the endpoint is on.

The program sends and receives JSON objects, one per line, each at most 64 KiB:

1. Within 5 seconds, the program sends `{"type":"hello","protocol":1,"scopes":["read"]}`.
1. The endpoint answers `welcome`, with `protocol`, `version`, and the granted `scopes`, or `error`, with `code` and `message`, and closes the connection.
1. The program sends `{"type":"subscribe","stream":"controllers"}`. Add `"output":true` for the values of the virtual gamepad.
1. The endpoint sends the same `connected`, `input`, and `disconnected` lines as `ojd controller watch --all --json`.

```python
import json
import socket
import subprocess

status = json.loads(subprocess.check_output(["ojd", "--json", "access", "status"]))
with socket.socket(socket.AF_UNIX) as endpoint:
    endpoint.connect(status["socketPath"])
    lines = endpoint.makefile("rw")
    lines.write('{"type":"hello","protocol":1,"scopes":["read"]}\n')
    lines.flush()
    print(lines.readline(), end="")
    lines.write('{"type":"subscribe","stream":"controllers"}\n')
    lines.flush()
    for line in lines:
        event = json.loads(line)
        if event["type"] != "input":
            print(event["type"], event["id"])
```

`python3` is signed by Apple, so to run this example, grant `/usr/bin/python3`. Every Python script you run then gets the access. Grant a signed app of your own for regular use.

The error codes are `endpoint-disabled`, `not-granted`, `unsupported-protocol`, `invalid-message`, `too-many-connections`, `revoked`, and `too-slow`. With `unsupported-protocol`, `supported` lists the protocol versions. The endpoint serves at most 8 connections. When a program reads too slowly, the endpoint keeps only the newest `input` line of each controller. When 256 lines wait, it sends `too-slow` and closes the connection.

[`endpoint.schema.json`](../Resources/Schemas/endpoint.schema.json) describes each line. In a test, a sandboxed app could not connect to the endpoint: macOS refused the connection with `EPERM`, with and without a temporary-exception entitlement for the socket path. The endpoint does not have the `control` scope yet, so a program cannot drive a virtual gamepad through it.

## Change Profiles

A profile is a JSON file. [`profile.schema.json`](../Resources/Schemas/profile.schema.json) describes it, and the [Profile file reference](Profile-File-Reference.md) explains its fields.

- `ojd profile get PROFILE KEY` prints one value. `ojd profile set PROFILE KEY VALUE` changes one value. `KEY` is a path of member names and array indexes, joined by dots.
- `ojd profile export PROFILE` prints the whole file. `ojd profile import FILE` adds it again, or replaces the profile with the same ID. Use `-` as `FILE` to read standard input.
- `ojd profile validate FILE` checks a file against the schema and against the rules that span fields. It does not need the service.
- `ojd profile activate PROFILE` and `ojd profile deactivate PROFILE` apply a profile and stop it.

```shell
ojd profile get Racing stickMappings.0.tuning.innerDeadzone
ojd profile set Racing stickMappings.0.tuning.innerDeadzone 0.15
ojd profile export Racing --output racing.json
ojd profile validate racing.json
```

To limit a profile to one controller, set `device.unit` to the controller's unit ID. To choose the virtual gamepad for one controller, use `ojd virtual set PROFILE CONTROLLER --unit`.

## Drive a Virtual Gamepad

`ojd virtual feed --as PROFILE` publishes a virtual gamepad and reads one JSON object per line from standard input. Each line gives the state of the whole gamepad. A control that the line does not name is neutral. The virtual gamepad profiles are `hid-xbox-one-s-bt` and `hid-generic`.

```shell
{
  echo '{"buttons":["south"]}'
  sleep 1
  echo '{"axes":{"left_stick_x":-1,"right_trigger":0.5}}'
  sleep 1
} | ojd virtual feed --as hid-generic
```

This example holds the south button for 1 second, then moves the left stick fully left and pulls the right trigger halfway for 1 second. When the input ends, the virtual gamepad is removed.

To tap a button without waiting in the script, write the press with `holdMilliseconds` and the release after it:

```shell
printf '%s\n' '{"buttons":["south"],"holdMilliseconds":50}' '{}' | ojd virtual feed --as hid-generic
```

- `buttons` and `dpad` list the controls that are pressed. They take the names that `button:` and `dpad:` binding sources use, such as `south` and `up`.
- `axes` maps axis names to values. Sticks, such as `left_stick_x`, go from -1 to 1, with Y up. The triggers, `left_trigger` and `right_trigger`, go from 0 to 1.
- The service plays the lines in order. Each line lasts at least 8 ms, and then until the next line plays. Add `holdMilliseconds`, from 0 to 60000, to keep a line longer.
- When lines arrive faster than every 8 ms, they wait in a queue of at most 256 lines, so a full queue is about 2 seconds behind. A line without `holdMilliseconds` replaces the last waiting line when that one has no `holdMilliseconds` and the same `buttons` and `dpad`. A press or release is never dropped.
- Each rumble command that a game sends to the virtual gamepad prints on standard output as one JSON object per line. The `virtualFeed` entry of the output schema describes it.
- The service removes the virtual gamepad when the input ends and every line has played, when you press Control-C, or when it gets no update for 2 seconds. The command sends updates while it waits for input.
- A line that is not valid stops the command with exit code 64. The service runs at most 4 feeds at the same time.

Games and latency with `ojd virtual feed` are not verified.

## Use Shortcuts

On macOS 13 or later, the Shortcuts app lists these OpenJoystickDriver actions:

| Action | Takes | Returns |
| --- | --- | --- |
| Get Controllers | Nothing | The connected controllers, each with a name and a model |
| Get Battery Level | A controller | The battery charge in percent |
| Activate Profile | A remapping profile | The profile, now active |
| Deactivate Profile | A remapping profile | The profile, now inactive |
| Get OpenJoystickDriver Version | Nothing | The version of the installed app |

The actions run in the app, so the app must be installed. They do not use `ojd`.

When you pick a controller, the list shows each connected controller, and then one entry for each connected model. A shortcut stores the controller in the same forms as `CONTROLLER` in [Name a Controller](#name-a-controller):

- A single controller is stored by its unit ID, or by its `ojd controller list` ID when it has no unit ID. The unit ID changes when you connect the controller to a different USB port, and the list ID changes when the service restarts.
- A model entry is stored as `VVVV:PPPP`. It finds the connected controller of that model on any port. When two connected controllers have the same model, the action fails and lists them. You can also type `VVVV:PPPP` in the search field.

Get Battery Level fails when the controller reports no battery level. When the controller reports a range, such as `30-39%`, the action returns the lowest value of the range.

To run a shortcut from another program, use the `shortcuts` command or a `shortcuts://` link:

- Raycast: the Shortcuts extension runs a shortcut by name, or a Script Command can run `shortcuts run "Low Battery Check"`.
- Stream Deck: an Open action with the link `shortcuts://run-shortcut?name=Low%20Battery%20Check` runs the shortcut.

None of these actions is verified live in the Shortcuts app yet.

## Further Reading

- [Command line](Command-Line.md)
- [Command reference](Command-Reference.md)
- [Profile file reference](Profile-File-Reference.md)
