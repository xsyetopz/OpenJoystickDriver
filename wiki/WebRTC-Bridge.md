# WebRTC Bridge

Play a game on one Mac with a controller plugged into another Mac.

The bridge copies controller input from the first Mac to the second. The game sees a [virtual gamepad](Glossary.md#terms). Rumble from the game goes back to the first Mac, where the bridge prints it. It does not make the controller rumble.

The bridge is a separate program, `ojd-webrtc-bridge`, that you build and run in Terminal on both Macs. The app, the service, and `ojd` have no WebRTC code. The bridge can do only what you allow with `ojd access`.

You need two Macs that can reach each other on one network, with OpenJoystickDriver on both.

> [!WARNING]
> Each Mac runs the bridge with a token, which works like a password. Keep it private. Anyone with a token has its access.

## Choose the Roles

Each Mac runs one bridge with one role.

| Role | Run it on | Token scope | What it does |
| --- | --- | --- | --- |
| `player` | The Mac with the controller | `Read` | Sends one controller's input to the other Mac. Prints each rumble command it gets back. |
| `host` | The Mac that runs the game | `Control` | Shows the input as a virtual gamepad. Sends the game's rumble back. |

## Build the Bridge

1. In Terminal, go to the `Tools/WebRTCBridge` folder of the source tree.
2. Run `swift build -c release`. The first build downloads about 70 MB.
3. The program is `.build/release/ojd-webrtc-bridge`.

## Connect Two Macs

The bridges find each other through two lines of text, an offer and an answer. Copy each line to the other Mac yourself, by a channel you trust. Anyone with both lines can try to join.

1. On each Mac, turn on the endpoint: `ojd access enable`.
2. On the player Mac, create a token that lets the bridge read your controller: `ojd access grant --token bridge --scope read`. The command prints the token once. Keep it.
3. On the host Mac, create a token that lets the bridge drive a virtual gamepad: `ojd access grant --token bridge --scope control`. Keep it.
4. On the player Mac, start the bridge: `OJD_TOKEN=TOKEN ojd-webrtc-bridge --role player`. Replace `TOKEN` with the player token. The bridge prints its offer as one line.
5. Copy the offer to the host Mac. Start the bridge there: `OJD_TOKEN=TOKEN ojd-webrtc-bridge --role host`. Replace `TOKEN` with the host token. Paste the offer and press Return. The bridge prints its answer as one line.
6. Copy the answer to the player Mac, paste it, and press Return.

When the link opens, each bridge connects to the local endpoint socket of its Mac. The virtual gamepad appears on the host Mac. Stop each bridge with Control-C.

## Use the Command Options

Output of `ojd-webrtc-bridge --help`:

```text
usage: ojd-webrtc-bridge --role host|player [--signal offer|answer] [--socket PATH]
       [--token-name NAME] [--controller ID] [--persona Generic|SDLCompatible]
       [--ice-server URL]...
Set OJD_TOKEN to the token that `ojd access grant --token NAME` printed.
The offer and the answer are one line each: the bridge prints its own on stdout and reads the
peer's from stdin. The player offers by default and the host answers.
```

- `--role host|player`: Required.
- `--signal offer|answer`: Choose which bridge offers. The player offers and the host answers by default.
- `--socket PATH`: Path of the endpoint socket. Without it, the bridge runs `ojd --json access status`.
- `--token-name NAME`: Token name. The default is `bridge`.
- `--controller ID`: Controller ID from `ojd controller list`, for `player`. Without it, the player uses the first controller the endpoint reports.
- `--persona Generic|SDLCompatible`: [Virtual gamepad kind](Glossary.md#terms) for `host`. `Generic` is the Generic HID gamepad. `SDLCompatible` is for Steam and SDL games. The default is `Generic`.
- `--ice-server URL`: Add a STUN or TURN server. Repeat it for more. Without it, the bridge uses local addresses, enough for one network.

`OJD_TOKEN` must hold the token, or the bridge refuses to start.

## If the Bridge Does Not Work

- `E1002`: the token is wrong or lacks the scope of the role. Create it again with the right `--scope`, as in [Connect Two Macs](#connect-two-macs). See [Error codes](Error-Codes.md).
- Socket not found: run `ojd access status` and pass the path with `--socket`.
- Macs do not connect: check that both are on one network, or give each bridge a STUN server with `--ice-server`.

## Further Reading

- [WebRTC bridge reference](../docs/sdk/webrtc-bridge.md)
- [Command reference](Command-Reference.md)
- [Permissions and security](Permissions-and-Security.md)
- [Automating OpenJoystickDriver](Automating-OpenJoystickDriver.md)
