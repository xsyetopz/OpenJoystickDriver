# Automating OpenJoystickDriver

Use `ojd` in scripts and other programs to read controller state, change profiles, and drive a virtual gamepad.

> **Note:** This page applies to OpenJoystickDriver 0.5.0-beta.5 and later. Version 0.5.0-beta.4 and earlier do not have all of the features on this page.

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

1. The endpoint sends `{"type":"challenge","nonce":"…"}` first. A granted program can ignore it; a [token](#use-a-token) client signs it.
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
    lines.readline()  # the challenge
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

### Use a Token

A program that cannot be granted by its signature, such as a script, can use a token instead. The program does not send the token. It proves that it has the token by signing the challenge:

1. Create the token: `ojd access grant --token reader`. The command prints the token once, and the service keeps only its SHA-256 hash.
1. Join four lines, each ending with a newline: `OpenJoystickDriver endpoint hello 1`, the challenge's `nonce`, the page's origin, and the WebSocket's port. On the socket, the origin and port lines are empty.
1. Compute the HMAC-SHA256 of those lines, keyed with the SHA-256 of the token, and write it as lowercase hex.
1. Send the token's name and the HMAC in `hello`: `{"type":"hello","protocol":1,"scopes":["read"],"tokenName":"reader","proof":"…"}`.

```python
import hashlib
import hmac
import json

TOKEN = "ojd_…"

nonce = json.loads(lines.readline())["nonce"]
message = "".join(line + "\n" for line in ["OpenJoystickDriver endpoint hello 1", nonce, "", ""])
key = hashlib.sha256(TOKEN.encode()).digest()
proof = hmac.new(key, message.encode(), hashlib.sha256).hexdigest()
hello = {"type": "hello", "protocol": 1, "scopes": ["read"], "tokenName": "reader", "proof": proof}
lines.write(json.dumps(hello) + "\n")
```

This replaces the `readline` and the first `write` in the example above.

Any program that reads the token can use it, so store it like a password. Remove it with `ojd access revoke token:reader`.

`AccessGrants.json`, in the OpenJoystickDriver Application Support folder, is secret too. The SHA-256 hashes in it are the HMAC keys, so a program that reads the file can sign challenges as any token in it. The service writes the file so that only your user can read it. Keep it out of support reports, exports, backups, and anything else that you share, and revoke every token if it leaks.

### Use the WebSocket

A web page, such as a stream overlay, can read the endpoint through a WebSocket:

1. Turn on the WebSocket: `ojd access web enable`. It listens on `127.0.0.1`. The first time, the system picks a free port, and the service saves it, so the port stays the same. Choose a port with `--port`. `ojd access status` shows the port. The WebSocket is separate from `ojd access enable`, which turns on only the socket.
1. Grant a token for the page's origin, with the port from `ojd access status`: `ojd access grant --token overlay --origin http://127.0.0.1:PORT`.
1. Put the page in the `Overlays` folder that `ojd access status` shows. The WebSocket's port serves the folder at `http://127.0.0.1:PORT/`, and a folder serves its `index.html`.
1. The page connects to `ws://127.0.0.1:PORT/endpoint` and exchanges the same messages, one JSON object per text message. It signs the challenge with its [token](#use-a-token), its origin, and the port.

```javascript
const token = "ojd_…";
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
  switch (event.type) {
    case "challenge":
      endpoint.send(
        JSON.stringify({
          type: "hello",
          protocol: 1,
          scopes: ["read"],
          tokenName: "overlay",
          proof: await proof(event.nonce),
        }),
      );
      break;
    case "welcome":
      endpoint.send(JSON.stringify({ type: "subscribe", stream: "controllers" }));
      break;
    case "input":
      console.log(event);
      break;
  }
};
```

The WebSocket accepts a page only from an origin that a token is granted for, and the token must be granted for that origin. A page from another origin, such as `http://127.0.0.1:8080`, signs its own origin and the WebSocket's port. It refuses pages opened from a file, whose origin is `null`. Use `127.0.0.1` in the address, not `localhost`, which the WebSocket refuses. When another program already uses the port, `ojd access web enable` fails. When the service starts and finds the port in use, `ojd access status` shows the WebSocket as on but not listening. In both cases, choose another port with `ojd access web enable --port PORT`, and grant tokens for the new origin.

The error codes are `endpoint-disabled`, `not-granted`, `unsupported-protocol`, `invalid-message`, `too-many-connections`, `revoked`, `too-slow`, `too-many-feeds`, and `feed-closed`. With `unsupported-protocol`, `supported` lists the protocol versions. The endpoint serves at most 8 connections. When a program reads too slowly, the endpoint keeps only the newest `input` line of each controller. When 256 lines wait, it sends `too-slow` and closes the connection.

[`endpoint.schema.json`](../Resources/Schemas/endpoint.schema.json) describes each line. To drive a virtual gamepad through the endpoint, see [Drive a Virtual Gamepad Through the Endpoint](#drive-a-virtual-gamepad-through-the-endpoint).

### Use the WebSocket From an App

A sandboxed app cannot connect to the socket: macOS refuses the connection with `EPERM`. It can use the WebSocket instead:

1. Give the app the `com.apple.security.network.client` entitlement.
1. Turn on the WebSocket with `ojd access web enable`, and create a token without `--origin`: `ojd access grant --token myapp`.
1. Connect to `ws://127.0.0.1:PORT/endpoint` without an `Origin` header.
1. Sign the challenge with the token, an empty origin line, and the port.

Any local program that has such a token can use it, also programs of other users on the same Mac, so store it like a password. On the WebSocket, a token without origins works only from a client that sends no `Origin`, and web browsers always send one, so web pages cannot use it.

### Drive a Virtual Gamepad Through the Endpoint

A program with the `control` scope can drive a virtual gamepad through the endpoint, as [`ojd virtual feed`](#drive-a-virtual-gamepad) does:

1. Grant the scope: `ojd access grant --token driver --scope control`. Add `--scope read` to grant both. A web page cannot use `control`.
1. Send `hello` with `"scopes":["control"]`.
1. After `welcome`, send `{"type":"feed","as":"hid-generic"}`. The virtual gamepad profiles are `hid-xbox-one-s-bt` and `hid-generic`.
1. The endpoint answers `{"type":"feeding","as":"hid-generic"}` when the virtual gamepad exists.
1. Send one frame per line. A frame has the format of an `ojd virtual feed` line, and the service plays frames with the same rules.
1. The endpoint sends each rumble command that a game sends to the virtual gamepad as one line. The `virtualFeed` entry of the output schema describes it.

Closing the connection removes the virtual gamepad at once and drops the frames that have not played. The endpoint does not report when a frame has played, so stay connected for the sum of the play times of the frames, and a short margin, because the service starts a frame a moment after it arrives. Each frame plays for its `holdMilliseconds`, and at least 8 ms. While 256 frames wait, the endpoint stops reading lines. The endpoint runs at most 4 virtual gamepads at the same time, and answers another `feed` with `too-many-feeds`. When the virtual gamepad does not start, or the service stops it, the endpoint sends `feed-closed`.

This client presses the south button for 100 ms, prints the lines that the endpoint sends, such as rumble commands and errors, and stays connected until the release has played. It uses only the Python standard library. Set `TOKEN` to the token that `ojd access grant` printed:

```python
import hashlib
import hmac
import json
import socket
import subprocess
import sys
import threading
import time

TOKEN = "ojd_…"
TOKEN_NAME = "driver"
FRAMES = [{"buttons": ["south"], "holdMilliseconds": 100}, {}]
MARGIN_SECONDS = 0.25


def proof(token, nonce):
    lines = ["OpenJoystickDriver endpoint hello 1", nonce, "", ""]
    message = "".join(line + "\n" for line in lines)
    key = hashlib.sha256(token.encode()).digest()
    return hmac.new(key, message.encode(), hashlib.sha256).hexdigest()


def hello(nonce):
    return {
        "type": "hello",
        "protocol": 1,
        "scopes": ["control"],
        "tokenName": TOKEN_NAME,
        "proof": proof(TOKEN, nonce),
    }


def play_seconds(frames):
    return sum(max(frame.get("holdMilliseconds", 0), 8) for frame in frames) / 1000


def print_lines(lines):
    for line in lines:
        print(line, end="")


def main():
    status = json.loads(subprocess.check_output(["ojd", "--json", "access", "status"]))
    with socket.socket(socket.AF_UNIX) as endpoint:
        endpoint.connect(status["socketPath"])
        reader = endpoint.makefile("r")
        writer = endpoint.makefile("w")

        def send(message):
            writer.write(json.dumps(message) + "\n")
            writer.flush()

        def receive():
            line = reader.readline()
            if not line:
                sys.exit("The endpoint closed the connection.")
            message = json.loads(line)
            if message["type"] == "error":
                sys.exit(f"{message['code']}: {message['message']}")
            return message

        send(hello(receive()["nonce"]))
        receive()  # welcome
        send({"type": "feed", "as": "hid-generic"})
        receive()  # feeding
        threading.Thread(target=print_lines, args=(reader,), daemon=True).start()
        for frame in FRAMES:
            send(frame)
        # The service starts the first frame a moment after it arrives.
        time.sleep(play_seconds(FRAMES) + MARGIN_SECONDS)
        endpoint.shutdown(socket.SHUT_RDWR)  # The reader thread keeps the socket open.


if __name__ == "__main__":
    main()
```

To run the client, save it as `driver.py` and run `python3 driver.py`. Games and latency with the endpoint are not verified.

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
- A line that is not valid stops the command with exit code 64. A line is not valid when it has an unknown key or lists a button or D-pad direction twice.
- The service runs at most 4 feeds from `ojd virtual feed` at the same time. Endpoint clients have 4 more of their own, so they cannot take these.

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
