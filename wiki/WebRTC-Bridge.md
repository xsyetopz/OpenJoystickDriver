# WebRTC bridge

Use `ojd-webrtc-bridge` to play a game on one Mac with a controller that is connected to another Mac.

The bridge is a separate program. It sends the input of one controller over a WebRTC data channel to a [virtual gamepad](Glossary.md#terms) on the other Mac, and sends rumble back. The app, the service, and `ojd` do not include WebRTC code. The bridge gets only the access that you give it with `ojd access`.

For the message formats, the sockets, and the limits, see the [WebRTC bridge reference](../docs/sdk/webrtc-bridge.md).

## Choose the Roles

Each Mac runs one bridge, with one role.

| Role | Run it on | Token scope | What it does |
| --- | --- | --- | --- |
| `player` | The Mac with the controller | `Read` | Sends the input of one controller to the other Mac. It prints each rumble command that comes back. It does not make the controller rumble. |
| `host` | The Mac that runs the game | `Control` | Shows the input as a virtual gamepad, and sends the rumble of the game back. |

## Build the Bridge

The bridge is not part of the app. Build it from the source tree:

1. Open Terminal and go to the `Tools/WebRTCBridge` folder of the source tree.
2. Run `swift build -c release`. The first build downloads about 70 MB.
3. The program is `.build/release/ojd-webrtc-bridge` in that folder.

## Connect Two Macs

You carry two lines of text between the Macs yourself, by any channel that you trust. Anyone who has both lines can try to join the data channel.

1. On each Mac, turn on the endpoint: `ojd access enable`.
2. On the player Mac, create a token: `ojd access grant --token bridge --scope read`. Keep the token that the command prints. It prints the token once.
3. On the host Mac, create a token: `ojd access grant --token bridge --scope control`. Keep the token.
4. On the player Mac, start the bridge: `OJD_TOKEN=TOKEN ojd-webrtc-bridge --role player`. Replace `TOKEN` with the token of the player Mac. The bridge prints its offer as one line.
5. Copy the offer to the host Mac. Start the bridge there: `OJD_TOKEN=TOKEN ojd-webrtc-bridge --role host`. Replace `TOKEN` with the token of the host Mac. Paste the offer and press Return. The bridge prints its answer as one line.
6. Copy the answer to the player Mac, paste it, and press Return.

When the data channel opens, each bridge connects to the endpoint of its Mac. The virtual gamepad appears on the host Mac. Stop each bridge with Control-C.

## Use the Command Options

This is the output of `ojd-webrtc-bridge --help`:

```text
usage: ojd-webrtc-bridge --role host|player [--signal offer|answer] [--socket PATH]
       [--token-name NAME] [--controller ID] [--persona Generic|SDLCompatible]
       [--ice-server URL]...
Set OJD_TOKEN to the token that `ojd access grant --token NAME` printed.
The offer and the answer are one line each: the bridge prints its own on stdout and reads the
peer's from stdin. The player offers by default and the host answers.
```

- `--role host|player`: Choose the role. This option is required.
- `--signal offer|answer`: Choose which bridge makes the offer. The player offers and the host answers by default.
- `--socket PATH`: Give the path of the endpoint socket. Without it, the bridge runs `ojd --json access status` to find the path.
- `--token-name NAME`: Give the name of the token. The default is `bridge`.
- `--controller ID`: Give the controller for the `player` role, as the ID from `ojd controller list`. Without it, the player uses the first controller that the endpoint reports.
- `--persona Generic|SDLCompatible`: Choose how the virtual gamepad of the `host` role appears. The default is `Generic`.
- `--ice-server URL`: Add a STUN or TURN server. You can repeat this option. Without it, the bridge uses only local addresses, which is enough for two Macs on one network.

The environment variable `OJD_TOKEN` must hold the token. The bridge refuses to start without it.

## Fix a Problem

- **The bridge prints an `E1002` error.** The token does not have the scope of the role, or it is wrong. Create the token again with the right `--scope`, as in [Connect Two Macs](#connect-two-macs). See [Error codes](Error-Codes.md).
- **The bridge cannot find the socket.** Run `ojd access status` and pass the path of the socket with `--socket`.
- **The two Macs do not connect.** Both Macs must be on the same network, or you must give each bridge a STUN server with `--ice-server`.

## Further Reading

- [WebRTC bridge reference](../docs/sdk/webrtc-bridge.md)
- [Command reference](Command-Reference.md)
- [Permissions and security](Permissions-and-Security.md)
- [Automating OpenJoystickDriver](Automating-OpenJoystickDriver.md)
