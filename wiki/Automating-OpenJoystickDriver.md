# Automating OpenJoystickDriver

Use `ojd` in scripts and other programs to read controller state, change [profiles](Glossary.md#terms), and drive a [virtual gamepad](Glossary.md#terms).

## Choose the Interface

`ojd` is the interface for scripts and other programs. Run it as a subprocess, read its `--json` output, and check its exit code. For the global options, output rules, and exit codes, see [Command line](Command-Line.md).

The Swift package `OpenJoystickDriverKit` has an `ApplicationServiceClient`, but the service accepts a connection only from a process with the same code signature as the app. A program you build yourself cannot use it with a released app. Use `ojd` instead.

## Write a Script

1. Start the service and wait until it accepts requests: `ojd service start`.
2. Add `--no-input` to each command, so that a command fails instead of asking a question.
3. Add `--json` to each command whose output you read.
4. Check the exit code of each command. Code 69 means that the service is not running.

Commands that delete or reset data ask first on a terminal. In a script, they need `--force`. Run them first with `--dry-run` to see what they change.

```shell
ojd service start --timeout 30
ojd --no-input --json controller list | jq -r '.items[] | [.id, .name, .unit // ""] | @tsv'
```

## Read JSON Output

Keys and values in `--json` output are stable identifiers, and OJD never translates them. A command that streams, such as `ojd controller watch` or `ojd virtual feed`, prints one JSON object per line.

Each object has `apiVersion`, which is `openjoystickdriver/v1alpha3`, and `kind`, the singular UpperCamelCase name of what the command prints: `ojd controller show` prints `Controller`, or `UnservedController` for a connected device that OJD does not handle, and `ojd status` prints `SystemStatus`. The list commands `controller list`, `permission list`, `setting list`, `binding list`, `profile list`, and `record list` print a `kind` that ends in `List`, such as `ControllerList`, with the entries in `items` and an empty `metadata`. An item has no `apiVersion` or `kind` of its own. `binding list` gives each item a `profile`, the profile it came from. `profile list` and `record list` report the profiles that cannot be loaded and the records that were skipped as warnings on standard error, one line each. A command that changes or removes something and has no object to print, such as `ojd profile delete` or `ojd controller rumble`, prints a `Status`: `status` is `Success`, and `details` holds the command's data. A command that fails prints no JSON: it exits with a non-zero code and writes the error on standard error. Values that OJD defines in output, such as `NotFound` or `BluetoothLE`, are UpperCamelCase with upper-case acronyms. The `status` of a `Status` and the `type` of a watch line keep the Kubernetes spelling.

Enumerated values in `--json` output are UpperCamelCase, such as `NotPublished` and `InputRead`. `--plain` output and command-line arguments spell the same values in lowercase kebab-case, such as `not-published` and `input-read`; this includes routes, [virtual gamepad kinds](Glossary.md#terms) and protocol families (`virtual-hid`, `sdl-compatible`, `xbox-gip`).

[`cli-output.schema.json`](../Resources/Schemas/cli-output.schema.json) describes the output of each command. Each command has one entry in `$defs`, named after its command path in lowerCamelCase: the entry for `ojd controller show` is `controllerShow`. Entries that start with `shared` are shapes that more than one command uses. The schema rejects keys that its release does not print, and a later release can add keys. Validate output against the schema from the same release.

Do not parse the human-readable output. It is translated, and it can change in each release.

## Name a Controller

Commands take a `CONTROLLER` operand. Use one of these forms:

- A unit ID, such as `U-` and 16 characters. It stays the same across reconnects and service restarts while the controller uses the same USB port. It changes when you connect the controller to a different port, and every unit ID changes when the key file `~/Library/Application Support/OpenJoystickDriver/PortKeyInstallation.key` is replaced. Scripts can store it. A controller with no location ID has no unit ID.
- `VVVV:PPPP`, the hexadecimal vendor and product ID. It names a controller model. When two connected controllers have the same model, the command fails and lists them.
- An ID from `ojd controller list`, such as `E-` and 16 characters. It lasts only until the controller disconnects, so do not store it.

`ojd controller list --json` gives the unit ID of each controller in `unit`.

## Watch Controllers

`ojd controller watch --all --json` reports every controller on one stream, so a program does not have to reconnect when a controller comes and goes. Each line is one JSON object with a `type` and an `object`, as in a Kubernetes watch. The line has no `apiVersion` or `kind` of its own. `object` is a `Controller` with its own `apiVersion` and `kind`, and its `id` is the ID from `ojd controller list`:

- `ADDED`: a controller connected. `object` has the fields of an `ojd controller list` entry, including `unit`. The first lines report the controllers already connected.
- `MODIFIED`: the controller's input changed. `object` has the same fields and `input`, the whole input state. With `--output`, `output` has the values of the controller's virtual gamepad.
- `DELETED`: the controller disconnected. `object` is the controller's last state.

```shell
ojd --no-input controller watch --all --json | jq -c 'select(.type != "MODIFIED")'
```

The service is polled every 16 ms for input, and every 250 ms for connected controllers.

## Read the Endpoint

A program that runs all the time can read controller events from the endpoint, a local socket, instead of running `ojd controller watch`. The endpoint is off by default, and it serves only the programs that you grant:

1. Turn on the endpoint: `ojd access enable`.
2. Grant your program: `ojd access grant /Applications/Reader.app`. To find the ID of a program that the endpoint refused, run `ojd access list`.
3. Read the socket path: `ojd --json access status | jq -r .socketPath`. It is in your user's temporary folder, and it exists only while the endpoint is on.

The program sends and receives JSON objects, one per line, each at most 64 KiB:

Each line except a watch line has `apiVersion`, which is `openjoystickdriver/v1alpha3`, and a `kind`:

1. The endpoint sends `{"apiVersion":"openjoystickdriver/v1alpha3","kind":"Challenge","nonce":"…"}` first. A granted program can ignore it; a [token](#use-a-token) client signs it.
2. Within 5 seconds, the program sends `{"apiVersion":"openjoystickdriver/v1alpha3","kind":"Hello","scopes":["Read"]}`.
3. The endpoint answers a `Welcome`, with `version` and the granted `scopes`, or a `Status` with `status` `Failure`, `code`, and `message`, and closes the connection. A line with another `apiVersion` gets `E1009`, a line without `apiVersion` or `kind`, or with one that is `null` or not a string, gets `E1011`, and a `kind` that the endpoint does not accept at that point gets `E1010`.
4. The program sends `{"apiVersion":"openjoystickdriver/v1alpha3","kind":"Subscription","stream":"Controllers"}`. Add `"output":true` for the values of the virtual gamepad.
5. The endpoint sends the same `ADDED`, `MODIFIED`, and `DELETED` watch lines as `ojd controller watch --all --json`.

```python
import json
import socket
import subprocess

status = json.loads(subprocess.check_output(["ojd", "--json", "access", "status"]))
with socket.socket(socket.AF_UNIX) as endpoint:
    endpoint.connect(status["socketPath"])
    lines = endpoint.makefile("rw")
    lines.readline()  # the challenge
    lines.write('{"apiVersion":"openjoystickdriver/v1alpha3","kind":"Hello","scopes":["Read"]}\n')
    lines.flush()
    print(lines.readline(), end="")
    lines.write('{"apiVersion":"openjoystickdriver/v1alpha3","kind":"Subscription","stream":"Controllers"}\n')
    lines.flush()
    for line in lines:
        event = json.loads(line)
        if event["type"] != "MODIFIED":
            print(event["type"], event["object"]["id"])
```

`python3` is signed by Apple, so to run this example, grant `/usr/bin/python3`. Every Python script you run then gets the access. Grant a signed app of your own for regular use.

### Use a Token

A program that cannot be granted by its signature, such as a script, can use a token instead. The program does not send the token. It proves that it has the token by signing the challenge:

1. Create the token: `ojd access grant --token reader`. The command prints the token once, and the service keeps only its SHA-256 hash.
2. Join four lines, each ending with a newline: `OpenJoystickDriver endpoint hello 1`, the challenge's `nonce`, the page's origin, and the WebSocket's port. On the socket, the origin and port lines are empty.
3. Compute the HMAC-SHA256 of those lines, keyed with the SHA-256 of the token, and write it as lowercase hex.
4. Send the token's name and the HMAC in the `Hello`: `{"apiVersion":"openjoystickdriver/v1alpha3","kind":"Hello","scopes":["Read"],"tokenName":"reader","proof":"…"}`.

```python
import hashlib
import hmac
import json

TOKEN = "ojd_…"

nonce = json.loads(lines.readline())["nonce"]
message = "".join(line + "\n" for line in ["OpenJoystickDriver endpoint hello 1", nonce, "", ""])
key = hashlib.sha256(TOKEN.encode()).digest()
proof = hmac.new(key, message.encode(), hashlib.sha256).hexdigest()
hello = {
    "apiVersion": "openjoystickdriver/v1alpha3",
    "kind": "Hello",
    "scopes": ["Read"],
    "tokenName": "reader",
    "proof": proof,
}
lines.write(json.dumps(hello) + "\n")
```

This replaces the `readline` and the first `write` in the example above.

Any program that reads the token can use it, so store it like a password. Remove it with `ojd access revoke token:reader`.

`AccessGrants.plist`, in the OpenJoystickDriver Application Support folder, is secret too. The SHA-256 hashes in it are the HMAC keys, so a program that reads the file can sign challenges as any token in it. The service writes the file so that only your user can read it. Keep it out of support reports, exports, backups, and anything else that you share, and revoke every token if it leaks.

### Use the WebSocket

A web page, such as a stream overlay, can read the endpoint through a WebSocket:

1. Turn on the WebSocket: `ojd access web enable`. It listens on `127.0.0.1`. The first time, the system picks a free port, and the service saves it, so the port stays the same. Choose a port with `--port`. `ojd access status` shows the port. The WebSocket is separate from `ojd access enable`, which turns on only the socket.
2. Grant a token for the page's origin, with the port from `ojd access status`: `ojd access grant --token overlay --origin http://127.0.0.1:PORT`.
3. Put the page in the `Overlays` folder that `ojd access status` shows. The WebSocket's port serves the folder at `http://127.0.0.1:PORT/`, and a folder serves its `index.html`.
4. The page connects to `ws://127.0.0.1:PORT/endpoint` and exchanges the same messages, one JSON object per text message. It signs the challenge with its [token](#use-a-token), its origin, and the port.

```javascript
const token = "ojd_…";
const apiVersion = "openjoystickdriver/v1alpha3";
const encoder = new TextEncoder();

async function proof(nonce) {
  const secret = await crypto.subtle.digest("SHA-256", encoder.encode(token));
  const key = await crypto.subtle.importKey("raw", secret, { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
  ]);
  const lines = ["OpenJoystickDriver endpoint hello 1", nonce, location.origin, location.port];
  const code = await crypto.subtle.sign("HMAC", key, encoder.encode(lines.map((line) => line + "\n").join("")));
  return Array.from(new Uint8Array(code), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

// The page is served from the WebSocket's port, so its origin and port are the ones to sign.
const endpoint = new WebSocket(`ws://${location.host}/endpoint`);
endpoint.onmessage = async (message) => {
  const event = JSON.parse(message.data);
  switch (event.kind) {
    case "Challenge":
      endpoint.send(
        JSON.stringify({
          apiVersion,
          kind: "Hello",
          scopes: ["Read"],
          tokenName: "overlay",
          proof: await proof(event.nonce),
        }),
      );
      break;
    case "Welcome":
      endpoint.send(JSON.stringify({ apiVersion, kind: "Subscription", stream: "Controllers" }));
      break;
    default:
      // A watch line has a type and an object, and no kind. A Status is an error.
      if (event.type === "MODIFIED") {
        console.log(event.object);
      }
      break;
  }
};
```

The WebSocket accepts a page only from an origin that a token is granted for, and the token must be granted for that origin. A page from another origin, such as `http://127.0.0.1:8080`, signs its own origin and the WebSocket's port. It refuses pages opened from a file, whose origin is `null`. Use `127.0.0.1` in the address, not `localhost`, which the WebSocket refuses. When another program already uses the port, `ojd access web enable` fails. When the service starts and finds the port in use, `ojd access status` shows the WebSocket as on but not listening. In both cases, choose another port with `ojd access web enable --port PORT`, and grant tokens for the new origin.

An error line is a `Status` with `status` `Failure` and a `code` from `E1001` to `E1011`. Look up each code, its cause, and its fix on [Error codes](Error-Codes.md). With `E1009`, `E1010` and `E1011`, `details.supportedAPIVersions` lists the `apiVersion` values that the endpoint accepts. The endpoint serves at most 8 socket connections and 8 WebSocket connections at the same time. When a program reads too slowly, the endpoint keeps only the newest `MODIFIED` line of each controller. When 256 lines wait, it sends `E1006` and closes the connection.

[`endpoint.schema.json`](../Resources/Schemas/endpoint.schema.json) describes each line, and the [SDK endpoint reference](../docs/sdk/endpoint.md) documents each message, the errors, the grants, and the versions. To drive a virtual gamepad through the endpoint, see [Drive a Virtual Gamepad Through the Endpoint](#drive-a-virtual-gamepad-through-the-endpoint).

### Use the WebSocket From an App

A sandboxed app cannot connect to the socket: macOS refuses the connection with `EPERM`. It can use the WebSocket instead:

1. Give the app the `com.apple.security.network.client` entitlement.
2. Turn on the WebSocket with `ojd access web enable`, and create a token without `--origin`: `ojd access grant --token myapp`.
3. Connect to `ws://127.0.0.1:PORT/endpoint` without an `Origin` header.
4. Sign the challenge with the token, an empty origin line, and the port.

Any local program that has such a token can use it, also programs of other users on the same Mac, so store it like a password. On the WebSocket, a token without origins works only from a client that sends no `Origin`, and web browsers always send one, so web pages cannot use it.

### Drive a Virtual Gamepad Through the Endpoint

A program with the `control` scope can drive a virtual gamepad through the endpoint, as [`ojd virtual feed`](#drive-a-virtual-gamepad) does:

1. Grant the scope: `ojd access grant --token driver --scope control`. Add `--scope read` to grant both. A token that has `--origin` cannot have `control`, because a web page cannot use it.
2. Send a `Hello` with `"scopes":["Control"]`.
3. After the `Welcome`, send `{"apiVersion":"openjoystickdriver/v1alpha3","kind":"FeedRequest","as":"Generic"}`. The virtual gamepad kind IDs are `Generic`, `SDLCompatible` and `GameControllerCompatible`; every virtual gamepad kind the service publishes is open to a client with the `control` scope. An unknown id is refused with `E1003`, and the message names the id and lists the accepted kinds.
4. The endpoint answers `{"apiVersion":"openjoystickdriver/v1alpha3","kind":"FeedSession","as":"Generic"}` when the virtual gamepad exists.
5. Send one frame per line, each with `apiVersion` and `"kind":"Frame"`. A frame has the keys of an `ojd virtual feed` line, and the service plays frames with the same rules.
6. The endpoint sends each rumble command that a game sends to the virtual gamepad as one `RumbleCommand` line, the same as `ojd virtual feed` prints. Its `type` is `SetRumble` or `StopRumble`. The `virtualFeed` entry of the output schema describes it.

Closing the connection removes the virtual gamepad at once and drops the frames that have not played. After the last frame, send a `{"apiVersion":"openjoystickdriver/v1alpha3","kind":"Drain"}` line and stay connected until the endpoint answers `Drained`, which comes when every frame sent before the `Drain` has played, the last one for its full time. A `Drain` is refused with `E1010` before the `FeedSession`. Each frame plays for its `holdMilliseconds`, and at least 8 ms. While 256 frames wait, the endpoint stops reading lines. When the client sends no frame line for 2 seconds after its last frame has played, the endpoint closes the connection with `E1008` and removes the virtual gamepad, so a stalled client does not hold a button. The 2 seconds start when the queue is empty and the last frame's time has elapsed, so frames that wait or play, and a long hold, never cause the close. Rumble lines that the endpoint sends do not count. To keep the gamepad after the last frame has played, send another line within 2 seconds. The endpoint runs at most 4 virtual gamepads at the same time, and answers another `feed` with `E1007`. When the virtual gamepad does not start, or the service stops it, the endpoint sends `E1008`.

The [reference client](../Scripts/SDK/reference_client.py) presses the south button for 100 ms, prints the rumble commands that the endpoint sends, sends a `Drain` line after the release, and stays connected until the endpoint answers `Drained`. When the endpoint sends an error or closes the connection earlier, it exits with the error. With `E1009`, `E1010`, or `E1011`, it also reports the supported `apiVersion` values. It uses only the Python standard library. Set `OJD_TOKEN` to the token that `ojd access grant` printed, and run `python3 reference_client.py feed`. To subscribe instead, run `python3 reference_client.py watch`. Games and latency with the endpoint are not verified.

### Change a Profile Through the Endpoint

A program with the `control` scope can activate, deactivate or change one profile, as `ojd profile activate`, `deactivate` and `set` do:

1. Grant the scope and send a `Hello` with `"scopes":["Control"]`, as in the section above.
2. After the `Welcome`, send `{"apiVersion":"openjoystickdriver/v1alpha3","kind":"ProfileRequest","action":"Set","profile":"Racing","key":"name","value":"Rally"}`. `action` is `Activate`, `Deactivate` or `Set`. `profile` is the UUID or the name of the profile. `Set` takes a `key` and a `value`, read as in `ojd profile set`; a `value` of `null` removes a member.
3. The endpoint answers a `ProfileResult` with the profile and whether it is active. A request that the service refuses, such as one for a profile that does not exist, gets a `Status` failure with the code that `ojd` prints, such as `E2012`, and the connection stays open for the next request.
4. A `ProfileRequest` may follow another one. A `Subscription` or a `FeedRequest` ends the exchange.

### Rumble, Player Number and Light Through the Endpoint

A program with the `control` scope can drive one controller, as `ojd controller rumble`, `player` and `light` do:

1. Send a `Hello` with `"scopes":["Control"]`, as in the section above.
2. After the `Welcome`, send `{"apiVersion":"openjoystickdriver/v1alpha3","kind":"OutputRequest","controller":"054C:0CE6","action":"Rumble","left":200,"duration":1.5}`. `controller` is a controller id or a `VID:PID` model. `action` is `Rumble`, `Player` or `Light`.
3. `Rumble` takes `left`, `right`, `leftTrigger` and `rightTrigger` (0 to 255) and `duration` in seconds (above 0, at most 5, default 0.45). With no motor named, both main motors run at 180. `Player` takes `player` (0 to 4). `Light` takes a `color` of six hex digits and a `brightness` (0 to 255), at least one of them.
4. The endpoint answers an `OutputResult` with one entry for each command that ran. A controller that lacks the output, or an unknown or ambiguous controller, gets a `Status` failure with the code that `ojd` prints, and the connection stays open. A malformed request gets `E1003` and the connection closes.

The Shortcuts actions Rumble Controller, Set Player Indicator and Set Controller Light run the same code.

### Watch Profiles and Mod Packages Through the Endpoint

A program with the `Read` scope can watch the profile list or the mod package list instead of the controllers:

1. Send a `Hello` with `"scopes":["Read"]`, as in the section above.
2. After the `Welcome`, send `{"apiVersion":"openjoystickdriver/v1alpha3","kind":"Subscription","stream":"Profiles"}`, or `"stream":"Mods"`. These streams refuse `output`.
3. The endpoint answers a `Profiles` line with every profile and whether it is active, or a `Mods` line as for a `ModList`, and sends the whole list again each time it changes. It reads the lists twice a second.
4. Any line after the `Subscription` ends the connection.

### List Mod Packages Through the Endpoint

A program with the `Read` scope can list the installed mod packages, as `ojd mod list --json` does:

1. Send a `Hello` with `"scopes":["Read"]`, as in the section above.
2. After the `Welcome`, send `{"apiVersion":"openjoystickdriver/v1alpha3","kind":"ModList"}`.
3. The endpoint answers `Mods` with one entry for each package: `name`, `files`, and `version` and `author` when the package states them. An entry with a `problem` holds a package that the service does not use. The connection stays open, so a `ModList` may follow a `ModList` or a `ProfileRequest`.

### What ran against the installed build

The messages above ran through the socket against build `8456f9de8665`, with a token that held `Read` and `Control`. The scripts and their output are in [`evidence/scripting/`](../evidence/scripting/):

- `ProfileRequest` activated, renamed (`Set` of `name`), and deactivated a profile, each answered by a `ProfileResult`. A profile that does not exist got `E2012` and the connection stayed open; a `Set` without `value` got `E1003`; a client with only `Read` got `E1002`.
- `ModList` answered an empty `mods` list, then the package after `ojd mod install` on the same connection, then an empty list after `ojd mod remove`.
- The `Profiles` and `Mods` subscriptions sent the whole list at once and again after each change that `ojd` made. `output` on `Profiles` and the stream `Logs` got `E1003`.
- A `FeedRequest` for `Generic`, `SDLCompatible` and `GameControllerCompatible` each got a `FeedSession`, and `Drain` got `Drained`. `DualShock` got `E1003` with the accepted personas.
- `OutputRequest` was tried with an 8BitDo Ultimate 2C on Bluetooth LE, which OpenJoystickDriver serves by its HID descriptor with no rumble, player lights or light color. Each of `Rumble`, `Player` and `Light` got `E2013` with the same text `ojd controller rumble`, `player` and `light` print, and an unknown controller got `E2012`. Rumble, a player number, and a light that a controller carries out are not shown yet.

## Change Profiles

A profile is an XML property list file. [`profile.schema.json`](../Resources/Schemas/profile.schema.json) describes it, and the [Profile file reference](Profile-File-Reference.md) explains its fields. To read one in a script, convert it with `plutil -convert json -o - FILE.plist`.

- `ojd profile get PROFILE KEY` prints one value. `ojd profile set PROFILE KEY VALUE` changes one value. `KEY` is a path of key names and array indexes, joined by dots.
- `ojd profile export PROFILE` prints the whole file. `ojd profile import FILE` adds it again, or replaces the profile with the same ID. Use `-` as `FILE` to read standard input.
- `ojd profile validate FILE` checks a file against the schema and against the rules that span fields. It does not need the service.
- `ojd profile activate PROFILE` and `ojd profile deactivate PROFILE` apply a profile and stop it.

```shell
ojd profile get Racing stickMappings.0.tuning.innerDeadzone
ojd profile set Racing stickMappings.0.tuning.innerDeadzone 0.15
ojd profile export Racing --output racing.plist
ojd profile validate racing.plist
```

To limit a profile to one controller, set `device.unit` to the controller's unit ID. To choose the virtual gamepad for one controller, use `ojd virtual set PROFILE CONTROLLER --unit`.

## Drive a Virtual Gamepad

`ojd virtual feed --as PROFILE` publishes a virtual gamepad and reads one JSON object per line from standard input. Each line gives the state of the whole gamepad. A control that the line does not name is neutral. The virtual gamepad kinds are `sdl-compatible` and `generic`.

```shell
{
  echo '{"buttons":["South"]}'
  sleep 1
  echo '{"axes":{"LeftStickX":-1,"RightTrigger":0.5}}'
  sleep 1
} | ojd virtual feed --as generic
```

This example holds the South button for 1 second, then moves the left stick fully left and pulls the right trigger halfway for 1 second. When the input ends, the virtual gamepad is removed.

To tap a button without waiting in the script, write the press with `holdMilliseconds` and the release after it:

```shell
printf '%s\n' '{"buttons":["South"],"holdMilliseconds":50}' '{}' | ojd virtual feed --as generic
```

- `buttons` and `dpad` list the controls that are pressed. They take the names that `button:` and `dpad:` binding sources use, such as `South` and `up`.
- `axes` maps axis names to values. Sticks, such as `LeftStickX`, go from -1 to 1, with Y down. The triggers, `LeftTrigger` and `RightTrigger`, go from 0 to 1.
- The service plays the lines in order. Each line lasts at least 8 ms, and then until the next line plays. Add `holdMilliseconds`, from 0 to 60000, to keep a line longer.
- When lines arrive faster than every 8 ms, they wait in a queue of at most 256 lines, so a full queue is about 2 seconds behind. A line without `holdMilliseconds` replaces the last waiting line when that one has no `holdMilliseconds` and the same `buttons` and `dpad`. A press or release is never dropped.
- Each rumble command that a game sends to the virtual gamepad prints on standard output as one JSON object per line. The `virtualFeed` entry of the output schema describes it.
- The service removes the virtual gamepad when the input ends and every line has played, when you press Control-C, or when it gets no update for 2 seconds. The command sends updates while it waits for input.
- A line that is not valid stops the command with exit code 64. A line is not valid when it has an unknown key or lists a button or D-pad direction twice.
- The service runs at most 4 feeds from `ojd virtual feed` at the same time. Endpoint clients have 4 more of their own, so they cannot take these.

Games and latency with `ojd virtual feed` are not verified.

### What the virtual gamepad carries

The virtual gamepad is a standard gamepad. Each profile has a fixed set of buttons, so some controls on a physical controller have no output. A control that is not carried does nothing on the virtual gamepad, whether it is passed through or assigned to a gamepad output.

| Control | `generic` | `sdl-compatible` |
| --- | --- | --- |
| South, East, West, North | Carried | Carried |
| Left and right shoulder | Carried | Carried |
| Back, Start | Carried | Carried |
| Left and right stick click | Carried | Carried |
| Guide | Carried | Carried, in its own report |
| D-pad | Carried as a hat and as 4 buttons | Carried as a hat |
| Sticks and triggers | Carried | Carried |
| Capture | Carried | Not carried |
| Touchpad click, microphone | Not carried | Not carried |
| Paddles, grips, and auxiliary buttons | Not carried | Not carried |
| Stick touch, trackpad touch, left trackpad click | Not carried | Not carried |
| Right trackpad click | Right stick click on the classic Steam Controller, otherwise not carried | Right stick click on the classic Steam Controller, otherwise not carried |

- `generic` has 16 buttons and all 16 are in use. Its layout is the published contract for the product ID `1209:4A4F`, so a new button would need a new product ID.
- `sdl-compatible` sends the Xbox One USB packets that SDL's HIDAPI driver reads: an 18-byte input report, and Guide in a second report. They have no field for Capture, and SDL reads no other button from them.
- The right pad of the classic Steam Controller is its right stick, and the controller has no separate right stick click, so its pad click is the right stick click. The Steam Deck and the Steam Triton have a right stick click of their own, so their right pad click is a different control and is not carried.
- The D-pad buttons of `sdl-compatible` stay clear. The D-pad is the hat.

## Use AppleScript or JavaScript for Automation

The app has no AppleScript dictionary. A script runs `ojd` through `do shell script`, whose `PATH` lacks `/usr/local/bin`, so it names the link in full. Turn on the link in Settings first. These examples read another path from the `OJD` environment variable.

```applescript
set ojd to system attribute "OJD"
if ojd is "" then set ojd to "/usr/local/bin/ojd"
set state to do shell script quoted form of ojd & " --no-input --json status | /usr/bin/plutil -extract service.state raw -o - -"
set controllers to do shell script quoted form of ojd & " --no-input --json controller list | /usr/bin/plutil -extract items raw -o - -"
return "Service: " & state & ". Connected controllers: " & controllers & "."
```

`osascript service-state.applescript` prints `Service: Running. Connected controllers: 0.` with no controller connected.

```javascript
const app = Application.currentApplication();
app.includeStandardAdditions = true;
const ojd = app.systemAttribute("OJD") || "/usr/local/bin/ojd";
const status = JSON.parse(app.doShellScript(`'${ojd}' --no-input --json status`));
const lines = status.unboundDevices.map((device) => `${device.name} (${device.connection})`);
`Service ${status.service.state}; ${status.controllers.length} controllers; unbound: ${lines.join(", ") || "none"}`;
```

`osascript -l JavaScript unbound-devices.js` prints `Service Running; 0 controllers; unbound: 8BitDo Ultimate 2C Wireless Controller (USB)` while another program holds that controller. Both scripts and their output are in [`evidence/scripting/`](../evidence/scripting/).

## Use Shortcuts

On macOS 13 or later, the Shortcuts app lists these OpenJoystickDriver actions:

| Action | Takes | Returns |
| --- | --- | --- |
| Get Controllers | Nothing | The connected controllers, each with a name and a model |
| Get Battery Level | A controller | The battery charge in percent |
| Activate Profile | A profile | The profile, now active |
| Deactivate Profile | A profile | The profile, now inactive |
| Set Profile Value | A profile, a key, and a value | The profile, with the value changed |
| Get OpenJoystickDriver Version | Nothing | The version of the installed app |
| List Mod Packages | Nothing | The names of the installed mod packages |
| Install Mod Package | A folder, and whether to replace an installed package of the same name | The name of the installed package |
| Remove Mod Package | A package name | The name of the removed package |
| Rumble Controller | A controller, an intensity (0 to 255), and a duration in seconds | Nothing |
| Set Player Indicator | A controller and a player number (0 to 4) | Nothing |
| Set Controller Light | A controller, a color, and a brightness | Nothing |

The actions run in the app, so the app must be installed. They do not use `ojd`.

When you choose a controller, the list shows each connected controller, and then one entry for each connected model. A shortcut stores the controller in the same forms as `CONTROLLER` in [Name a Controller](#name-a-controller):

- A single controller is stored by its unit ID, or by its `ojd controller list` ID when it has no unit ID. The unit ID changes when you connect the controller to a different USB port, and the list ID changes each time the controller connects.
- A model entry is stored as `VVVV:PPPP`. It finds the connected controller of that model on any port. When two connected controllers have the same model, the action fails and lists them. You can also type `VVVV:PPPP` in the search field.

Get Battery Level fails when the controller reports no battery level. When the controller reports a range, such as `30-39%`, the action returns the lowest value of the range.

To run a shortcut from another program, use the `shortcuts` command or a `shortcuts://` link:

- Raycast: the Shortcuts extension runs a shortcut by name, or a Script Command can run `shortcuts run "Low Battery Check"`.
- Stream Deck: an Open action with the link `shortcuts://run-shortcut?name=Low%20Battery%20Check` runs the shortcut.

None of these actions is verified live in the Shortcuts app yet. `shortcuts list` prints no shortcut, and no command runs an action by name: `shortcuts run` needs a shortcut that you build in the Shortcuts app first.

## Further Reading

- [Command line](Command-Line.md)
- [Command reference](Command-Reference.md)
- [Profile file reference](Profile-File-Reference.md)
- [SDK endpoint reference](../docs/sdk/endpoint.md)
