# Public Endpoint Design

Status: proposed for milestone 3 (slice 3.2). No code exists yet. Slice 3.3 starts after this note is approved.

## Goal

Programs that the user approves can read controller events from the service, and later drive a virtual gamepad, without starting `ojd` as a subprocess. Overlays, stream tools, and accessibility tools are the expected clients.

## What Exists Today

- The service listens on `/tmp/com.openjoystickdriver.<uid>.rpc`, a Unix socket with mode `0600` (`LocalServiceRPCTransport.defaultSocketPath`).
- Each connection carries one request and one response, each a 4-byte big-endian length and a JSON frame.
- `LocalServiceRPCServer.authenticatedPeerPID` accepts a peer only when `getpeereid` gives the service's user. `ApplicationServiceServer.isTrustedClient` then accepts only the service's own process, or a process with the same signing identifier and team ID as the service.
- The CLI streams by polling: `ojd controller watch --all` reads each controller every 16 ms and the controller list every 250 ms (`ControllerWatchCommand+All.swift`). `ojd virtual feed` keeps a feed alive with repeated requests, and `VirtualFeedRegistry` closes a feed after its idle timeout. It allows at most 4 feeds.

The internal socket stays as it is. Its one-request-per-connection framing and its code-signature rule do not fit a long-lived stream from a third-party program.

## Threat Model

The endpoint serves the logged-in user's own programs. Other users and remote hosts are out of scope, because the socket is same-user only and nothing listens on the network.

A grant is consent, not a security boundary against malware that runs as the user. Any program that the user runs can already start `/Applications/OpenJoystickDriver.app/Contents/MacOS/ojd`, which the service trusts, and read controllers with `ojd controller watch` or drive a gamepad with `ojd virtual feed`. Grants answer a different question: which programs did the user agree to give controller input to, and can the user see and revoke that.

Grants matter for privacy because controller input needs the Input Monitoring permission. Without a grant, the endpoint would pass input to apps that macOS never asked the user about. This is why the endpoint is off by default and every client needs its own grant.

## Transport

- A new Unix socket, separate from the internal one, at `$(getconf DARWIN_USER_TEMP_DIR)com.openjoystickdriver.endpoint.sock`. The per-user temporary folder has mode `0700`, so other users cannot reach the socket path. The socket has mode `0600`.
- The service creates the socket only while the endpoint is enabled, and removes it when it is disabled or the service stops.
- `getpeereid` must give the service's user, as on the internal socket.
- The service identifies the peer by its audit token (`LOCAL_PEERTOKEN`, then `SecCodeCopyGuestWithAttributes` with `kSecGuestAttributeAudit`), not by its PID. A PID can be reused between `accept` and the signature check. The service then checks the client's code with `SecCodeCheckValidity`, so a modified binary fails.
- Messages are UTF-8 JSON objects, one per line, ending in `\n`. A line is at most 64 KiB. JSON lines work with `nc -U`, Python, and Node without a framing library, and match the `--json` output of the CLI.
- Limits: at most 8 connections, a handshake within 5 seconds, and no request from the client until the handshake succeeds.

## Handshake

The client speaks first:

```json
{"type":"hello","protocol":1,"scopes":["read"]}
```

The service answers with one line and then either streams or closes the connection:

```json
{"type":"welcome","protocol":1,"version":"0.5.0-beta.5","scopes":["read"]}
{"type":"error","code":"not-granted","message":"..."}
```

- `protocol` is an integer. The service supports a range of versions. When the client's version is outside it, the service answers `unsupported-protocol` with `supported`, the list of versions it accepts, and closes.
- `scopes` lists the scopes the client asks for. The service grants all of them or refuses with `not-granted`. It never grants a subset silently.
- Error codes are stable identifiers: `endpoint-disabled`, `not-granted`, `unsupported-protocol`, `invalid-message`, `too-many-connections`, `revoked`. `message` is English text for logs, not for parsing.

## Read Stream (Slice 3.3)

After `welcome`, the client sends `{"type":"subscribe","stream":"controllers","output":false}`. The service then sends the same lines as `ojd controller watch --all --json`: `connected`, `input`, and `disconnected`, with `type` and `id`. `output: true` adds `output`, as `--output` does.

- One poller in the service serves every subscriber. It starts with the first subscriber and stops with the last, so an idle endpoint costs nothing. The polling logic of `watchAll()` moves into `OpenJoystickDriverKit`, so the CLI and the endpoint use the same code.
- A client that reads too slowly gets the latest `input` line for each controller, and earlier ones are dropped. `connected` and `disconnected` lines are never dropped. When 256 lines are waiting, the service closes the connection with the error `too-slow`.
- `cli-output.schema.json` already describes the event lines. A new `endpoint.schema.json` describes `hello`, `welcome`, `error`, and `subscribe`, and refers to the `controllerWatch` events, so the two cannot drift apart.

## Control Stream (Milestone 4)

With the `control` scope, the client sends `{"type":"feed","as":"hid-generic"}`. Each following line is one `ojd virtual feed` input line, and the service sends rumble lines in the `virtualFeed` shape.

- One connection is one feed. Closing the connection removes the virtual gamepad, so this transport needs no heartbeat or idle timeout.
- `VirtualFeedRegistry` is reused unchanged, with its limit of 4 feeds shared with `ojd virtual feed`.
- `control` is never implied by `read`. Each needs its own grant.

## Grants

The service stores grants in `~/Library/Application Support/OpenJoystickDriver/AccessGrants.json`, a new schema-described file. Only the service writes it: `ojd access` asks the service through the internal socket, so a revoke takes effect at once.

A grant is keyed by the client's code signature:

| Client | Key | Why |
| --- | --- | --- |
| Signed with a Developer ID or App Store certificate | signing identifier and team ID | Apple certifies the team ID, so another developer cannot reuse the key. |
| Apple platform binary, such as `/usr/bin/python3` | signing identifier, with the `anchor apple` requirement | The identity is real, but a grant covers every script the interpreter runs. `ojd access grant` warns about this. |
| Ad-hoc signed or unsigned | refused | Anyone can ad-hoc sign a binary with any identifier, so the key proves nothing. |

Each grant has `scopes` (`read`, `control`), the time it was granted, and the path where the client was first seen, for display only.

### Commands

```text
ojd access status                    whether the endpoint is on, its socket path, and live connections
ojd access enable | disable          turn the endpoint on or off; disable closes every connection
ojd access list                      grants, and clients refused in the last 24 hours
ojd access grant CLIENT --scope read [--scope control]
ojd access revoke CLIENT [--scope SCOPE]
```

- `CLIENT` is an app or executable path, such as `/Applications/Overlay.app`, from which `ojd` reads the signature, or the ID of a refused client from `ojd access list`.
- `grant` and `enable` ask for confirmation on a terminal and need `--force` with `--no-input`, like other commands that change what other programs can do. Granting `control` names the risk: the client can press buttons in any game.
- `revoke` closes that client's live connections with the error `revoked`.
- Every command supports `--json`, described in `cli-output.schema.json`.

## Tests (Slice 3.3)

Swift tests run the endpoint on a private socket, as `FakeService` does for the CLI:

- A client without a grant is refused with `not-granted`, and an ad-hoc signed client is refused.
- A granted client receives `connected`, `input`, and `disconnected` lines that validate against the schema.
- A revoked client is disconnected with `revoked`.
- A disabled endpoint has no socket, and a wrong protocol version gets `unsupported-protocol`.

The signature checks need a client signed with a team ID, which a unit test cannot create. The tests inject the identity lookup, as `LocalServiceRPCServer` takes `authentication` today. A live check with a Developer ID signed client is a manual step.

## Decisions

1. Script clients (agreed). Slice 3.3 has signature grants only: a grant for an interpreter covers all its scripts, and ad-hoc signed tools are refused. Token grants come with 3.4, which needs them for browsers anyway: `ojd access grant --token NAME` prints a secret that the client sends in `hello`. Any process of the user that reads the token can use it.
1. The socket path (agreed). The socket goes in the per-user temporary folder, and `ojd access status --json` prints its path. `~/Library/Application Support/OpenJoystickDriver/endpoint.sock` is not used, because a long user name can pass the 104-byte limit of a socket path.
1. Sandboxed clients (open). It is not verified whether a sandboxed app can connect to a socket outside its container without a temporary exception entitlement. Slice 3.3 tests it with a sandboxed client and documents the result. The user decides how to support sandboxed clients after that result.
1. The internal socket (agreed). It identifies its peer by PID, and the same PID-reuse race applies there. Slice 3.3 fixes it: both sockets share one peer check that reads the audit token and checks the code with `SecCodeCheckValidity`.
