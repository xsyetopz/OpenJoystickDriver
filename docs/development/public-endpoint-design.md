# Public Endpoint Design

Status: implemented for read (slice 3.3), with token grants and the WebSocket (slice 3.4). The control stream (milestone 4) is not built yet.

## Goal

Programs that the user approves can read controller events from the service, and later drive a virtual gamepad, without starting `ojd` as a subprocess. Overlays, stream tools, and accessibility tools are the expected clients.

## What Exists Today

- The service listens on `/tmp/com.openjoystickdriver.<uid>.rpc`, a Unix socket with mode `0600` (`LocalServiceRPCTransport.defaultSocketPath`).
- Each connection carries one request and one response, each a 4-byte big-endian length and a JSON frame.
- `LocalServiceRPCServer.authenticatedPeerPID` accepts a peer only when `getpeereid` gives the service's user. `ApplicationServiceServer.isTrustedClient` then accepts only the service's own process, or a process with the same signing identifier and team ID as the service.
- The CLI streams by polling: `ojd controller watch --all` reads each controller every 16 ms and the controller list every 250 ms (`ControllerWatchCommand+All.swift`). `ojd virtual feed` keeps a feed alive with repeated requests, and `VirtualFeedRegistry` closes a feed after its idle timeout. It allows at most 4 feeds.

The internal socket stays as it is. Its one-request-per-connection framing and its code-signature rule do not fit a long-lived stream from a third-party program.

## Threat Model

The endpoint serves the logged-in user's own programs. Remote hosts are out of scope, because the WebSocket listens only on `127.0.0.1`. Other users cannot reach the Unix socket; the WebSocket relies on tokens against them (see Threat Model Additions).

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

The service sends a challenge first, on every connection, and the client answers with `hello`:

```json
{"type":"challenge","nonce":"..."}
{"type":"hello","protocol":1,"scopes":["read"]}
```

The nonce is 32 random bytes from `SecRandomCopyBytes` in unpadded base64url, new for each connection. A signed client ignores it; a token client signs it (see Token Grants).

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

## Token Grants and WebSocket (Slice 3.4)

### Token Grants

`ojd access grant --token NAME --scope read [--origin URL]...` creates a token grant and prints its token once.

- The token is `ojd_` and 32 random bytes from `SecRandomCopyBytes` in base64url. `AccessGrants.json` stores only its SHA-256, in a `tokens` array next to `grants`. The token cannot be shown again; a lost token is revoked and granted again.
- A token grant's ID is `token:NAME`. Names are unique and match `[A-Za-z0-9._-]{1,64}`.
- The client never sends the token. It sends the token's name and a proof in `hello`: `{"type":"hello","protocol":1,"scopes":["read"],"tokenName":"NAME","proof":"..."}`. The proof is the lowercase hex HMAC-SHA256, keyed with the SHA-256 of the token, of four lines that each end with `\n`: `OpenJoystickDriver endpoint hello 1`, the nonce, the normalized `Origin`, and the WebSocket's port. On the Unix socket, the origin and port lines are empty. The service compares the HMAC in constant time.
- Because the proof covers the nonce, origin, and port, a listener that impersonates the service learns no token and can replay no proof to the real service: each connection has its own nonce, and a proof made for one origin or port fails on another.
- With a token, the service skips the signature lookup, so ad-hoc signed tools and scripts work. Any process of the user that reads the token can use it.
- `AccessGrants.json` is a secret. Its SHA-256 hashes are the HMAC keys, so whoever reads the file can sign challenges as any token in it. The service writes it with mode 0600 in a 0700 folder, and the support report does not include it. Keep it out of shared reports, exports, and backups; when it leaks, revoke every token.
- `--origin` binds the token to web pages. A token without origins works on the Unix socket, and on the WebSocket only for a client that sends no `Origin`. The service stores each origin as `scheme://host[:port]`, with `http` or `https` only. `null` is never accepted: any website can make a browser send `Origin: null` from a sandboxed frame or a `data:` URL, so it proves nothing.
- A wrong proof, an unknown token name, or a token used from another origin gets `not-granted`. `ojd access list` shows the refusal by token name only when the proof was right, such as for a missing scope or origin; otherwise it shows an unknown token, so a guessed name is not recorded. Refusals are kept for 24 hours.
- `ojd access revoke token:NAME` removes the grant and closes its connections with `revoked`.

### WebSocket

`ojd access web enable [--port N]` opens a TCP listener on `127.0.0.1`. Without `--port`, it reuses the saved port; the first time, the system picks a free port and the service saves it, so no fixed, well-known port can be taken first by another user. `ojd access status` shows the port. It has its own switch in `AccessGrants.json` (`web.enabled`, `web.port`), off by default and independent of `ojd access enable`. `ojd access web disable` closes it and its connections with `endpoint-disabled`.

- WebSocket clients connect to `ws://127.0.0.1:PORT/endpoint`. The upgrade is refused unless `Host` is `127.0.0.1:PORT`, which stops DNS rebinding, and `Origin` is an origin of some token grant. An upgrade without `Origin` is accepted when some token grant has no origins.
- The challenge is the first WebSocket message after the `101`. `hello` must carry the name of a token whose grant names the connection's `Origin`, and a proof over that origin and the port. Without `Origin`, the token's grant must have no origins, and the proof has an empty origin line and the port. The token never goes on the wire, so it stays out of logs, browser history, and any listener that impersonates the service.
- One text frame, or one message split over continuation frames, is one line of the Unix protocol, at most 64 KiB. A binary frame or a longer message ends the connection with `invalid-message`. Client frames must be masked, as RFC 6455 requires.
- The limits of the Unix socket are shared: 8 clients across both transports, a 5-second handshake, and `too-slow` after 256 waiting lines.
- The service implements the upgrade and framing itself on a BSD socket. Network.framework's `NWProtocolWebSocket` shows request headers only to a handler that is shared by every connection, so it cannot tie a connection's `Origin` to the token in its `hello`.

### Overlay Pages

The same listener serves the files in `~/Library/Application Support/OpenJoystickDriver/Overlays/` at `http://127.0.0.1:PORT/`. A page loaded from there has the origin `http://127.0.0.1:PORT`, which a token can name, so local overlays and OBS browser sources need no `null` origin.

- `GET` and `HEAD` only, one request per connection. `/` and folders serve `index.html`; there are no folder listings.
- A path must stay inside the folder after symbolic links are resolved.
- Requests with `Sec-Fetch-Site` other than `same-origin` or `none` are refused, and responses carry `Cross-Origin-Resource-Policy: same-origin`, so another website cannot load a page's script, and the token in it, with a `<script>` tag.
- Every page in the folder shares one origin, so any of them can use a token granted to that origin.

### Threat Model Additions

- The TCP port is reachable by every local user, not only the logged-in one. Only the token protects it; the `Host` and `Origin` checks stop websites, not local programs.
- A token in a page is readable by anything that can read the page's file.
- Another local user can bind the port first, while the WebSocket is off or before the service starts. Pages then talk to that user's listener, which can read their events and send them fake ones, but learns no token, because a page sends only a proof over that listener's nonce. The port is random per Mac, which makes it harder to take first. `ojd access web enable` fails with the port in use, and `ojd access status` shows the WebSocket as on but not listening, so the user sees it; the user then revokes the token and chooses another port. On a Mac with one user, this does not apply.
- Another local user can listen on `[::1]:PORT`, which the service does not bind. `localhost` can resolve to `::1`, so the WebSocket refuses `Host: localhost:PORT`, and pages must use `127.0.0.1`.
- A listener on `0.0.0.0:PORT` does not take loopback connections from the service's `127.0.0.1:PORT`, because macOS gives a connection to the most specific address. The service does not set `SO_REUSEPORT`, so no other socket can bind `127.0.0.1:PORT` while it listens.
- A client must finish `hello` within 5 seconds of connecting, measured from the connection, not from its last byte, so slow clients cannot hold the 8 connection slots.
- The answer to an upgrade, `101` or `403`, tells a local program whether some token is granted for an origin. The origins are not secret.
- Browsers always send `Origin` on a WebSocket upgrade, so a page cannot use a token without origins. A native client can send any `Origin` or none, so for native clients only the token protects the WebSocket, as on the socket.

## Decisions

1. Script clients (agreed). Slice 3.3 has signature grants only: a grant for an interpreter covers all its scripts, and ad-hoc signed tools are refused. Slice 3.4 adds token grants: `ojd access grant --token NAME` prints a secret that the client signs the challenge with in `hello`.
1. The socket path (agreed). The socket goes in the per-user temporary folder, and `ojd access status --json` prints its path. `~/Library/Application Support/OpenJoystickDriver/endpoint.sock` is not used, because a long user name can pass the 104-byte limit of a socket path.
1. Sandboxed clients (open). Slice 3.3 tested an ad-hoc signed app bundle with `com.apple.security.app-sandbox` on macOS 27. Its `connect()` to a socket in the unsandboxed `DARWIN_USER_TEMP_DIR` fails with `EPERM`. It still fails with `com.apple.security.network.client`, and with `com.apple.security.temporary-exception.files.absolute-path.read-write` naming the socket, its `/private` path, or the folder. The same app connects to a socket inside its own container. So a sandboxed client cannot use the socket. A probe in the S5 slice showed that the same kind of app with `com.apple.security.network.client` reaches the WebSocket with a token; without that entitlement, its connection fails. Decision: a sandboxed client uses the WebSocket with a token that has no origins, and sends no `Origin`. Origin-bound tokens stay limited to their pages.
1. The internal socket (agreed). It identifies its peer by PID, and the same PID-reuse race applies there. Slice 3.3 fixes it: both sockets share one peer check that reads the audit token and checks the code with `SecCodeCheckValidity`.
