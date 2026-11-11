# WebRTC Bridge

The WebRTC bridge, `ojd-webrtc-bridge`, carries one controller between two Macs over a WebRTC data channel. It is a separate program and a client of the [SDK endpoint](endpoint.md). The app, the service and `ojd` do not link WebRTC code, and the bridge gets only the access that `ojd access` grants it.

The source is `Tools/WebRTCBridge/`. It is its own Swift package that depends on [LiveKitWebRTC](https://github.com/livekit/webrtc-xcframework), pinned to 150.7871.03. The root package does not fetch the framework.

## Contents

- [Build](#build)
- [Roles](#roles)
- [Connect two Macs](#connect-two-macs)
- [Data channel messages](#data-channel-messages)
- [Sockets](#sockets)
- [Limits](#limits)

## Build

```shell
cd Tools/WebRTCBridge
swift build -c release
```

The first build downloads the XCFramework, about 70 MB. The program is `.build/release/ojd-webrtc-bridge`.

## Roles

| Role | Runs on | Scope | Endpoint request | Does |
| --- | --- | --- | --- | --- |
| `host` | The Mac that runs the game | `Control` | `FeedRequest` | Sends each `Frame` from the data channel to the virtual gamepad, and each `RumbleCommand` of the endpoint back over the data channel. |
| `player` | The Mac with the controller | `Read` | `Subscription` | Sends the input of one controller over the data channel as `Frame` lines, and prints each `RumbleCommand` that comes back. |

The endpoint has no message that drives the rumble of a physical controller, so the player only prints the rumble commands. The endpoint closes a feed that sends no frame for 2 seconds, so the host sends a `KeepAlive` line every 0.5 seconds while no new frame arrives from the player. The host drops a message from the peer that is longer than 64 KiB or is not a valid `Frame` (unknown members, an unknown control name, a `holdMilliseconds` above 60000, a repeated name), and forwards only the newest frame for each 8 ms. The player prints only a `RumbleCommand` that has the shape of the schema (a `SetRumble` with all six intensities and at most 5000 ms, or a bare `StopRumble`), and a signaling blob longer than 64 KiB is refused.

## Connect two Macs

1. On each Mac, turn on the endpoint with `ojd access enable`, and create a token with `ojd access grant --token bridge --scope control` on the host or `--scope read` on the player.
2. Start the player: `OJD_TOKEN=ojd_… ojd-webrtc-bridge --role player`. It prints its offer as one line on stdout.
3. Copy that line to the host and start the host: `OJD_TOKEN=ojd_… ojd-webrtc-bridge --role host`. Paste the offer on stdin. The host prints its answer as one line.
4. Paste the answer on the player's stdin. When the data channel opens, both bridges connect to their endpoint.

You carry the offer and the answer yourself, by any channel that you trust. Anyone who has the offer and the answer can attempt to join the data channel, and the channel is encrypted with DTLS. The blob is base64 of a JSON object with `type` and `sdp`. The SDP holds the ICE candidates, so no further exchange is needed.

Options:

- `--socket PATH` names the endpoint socket; without it, the bridge runs `ojd --json access status`.
- `--token-name NAME` is the name of the token. The default is `bridge`.
- `--controller ID` (player) is the `id` from the watch lines. Without it, the player uses the first controller that the endpoint reports.
- `--persona Generic|SDLCompatible` (host) is the `as` of the `FeedRequest`.
- `--ice-server URL` adds a STUN or TURN server. Without it, the bridge uses only local candidates, which suffices on one network.
- `--signal offer|answer` swaps who offers. The player offers and the host answers by default.

## Data channel messages

The channel is named `ojd`, ordered and reliable. Each message is one endpoint line as UTF-8 JSON:

- Player to host: a `Frame`. The player converts the `input` of a `MODIFIED` watch line: `pressed` becomes `buttons`, `hat` becomes `dpad`, and the sticks and triggers become `axes`. Controls that have no `Frame` button are dropped.
- Host to player: a `RumbleCommand`, as the endpoint sent it.

## Sockets

The bridge opens no listening socket. The offer and the answer travel on stdout and stdin. ICE binds UDP sockets for the data channel, which do not listen, and TCP candidates are off. The test `testLoopbackPassesAFrameOneWayAndRumbleBack` scans the sockets of the process for the listening state after two bridges have connected, and finds none.

## Limits

- One controller and one peer for each bridge process.
- The channel is reliable and ordered, so a lost packet delays the frames behind it.
- Without a STUN server, the peers need to reach each other directly.

## Test

```shell
cd Tools/WebRTCBridge
swift test
```

The loopback test runs a player and a host in one process, joined by a real data channel, against a fake endpoint on a Unix socket. A frame goes from the player to the host's feed, and a `RumbleCommand` goes back. `just check-tools` and the CI job run this `swift test`.

The endpoint client and the bridge logic (`HostBridge`, `PlayerBridge`, the peer messages) are in `Tools/BridgeCore/`, a Swift package with no dependencies. The root package takes it for its tests only, so it needs no WebRTC code. `EndpointBridgeTests` in the root `swift test` runs a `HostBridge` against an in-process `EndpointServer`: a granted feed reaches the virtual gamepad and stays open on `KeepAlive` lines, and a token without the `control` scope, or an unknown token, gets `E1002` and no gamepad.
