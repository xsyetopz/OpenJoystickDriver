import Foundation
import WebRTCBridgeCore

/// Prints the text to standard error and exits with status 1.
func fail(_ text: String) -> Never {
  FileHandle.standardError.write(Data((text + "\n").utf8))
  exit(1)
}

/// The usage text of the tool.
let usage = BridgeCommandLine.usage

/// The `--name value` options of the command line.
let options: [String: [String]]
switch BridgeCommandLine.parse(Array(CommandLine.arguments.dropFirst())) {
case .help:
  print(usage)
  exit(0)
case .invalid:
  fail(usage)
case .options(let parsed):
  options = parsed
}
guard let role = options["role"]?.first, role == "host" || role == "player" else { fail(usage) }
guard let token = ProcessInfo.processInfo.environment["OJD_TOKEN"], !token.isEmpty else {
  fail("Set OJD_TOKEN to the endpoint token.")
}
/// The signaling role: `--signal`, else `offer` for the player and `answer` for the host.
let signal =
  SignalingRole(rawValue: options["signal"]?.first ?? (role == "player" ? "offer" : "answer"))
guard let signal else { fail(usage) }

/// The endpoint socket path: `--socket`, else the `socketPath` of `ojd --json access status`.
///
/// Exits with an error text when `ojd` cannot run or reports no path.
func socketPath() -> String {
  if let path = options["socket"]?.first { return path }
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["ojd", "--json", "access", "status"]
  let pipe = Pipe()
  process.standardOutput = pipe
  guard (try? process.run()) != nil else { fail("Cannot run `ojd`; pass --socket PATH.") }
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  guard let status = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let path = status["socketPath"] as? String
  else { fail("`ojd --json access status` gave no socketPath; pass --socket PATH.") }
  return path
}

/// Reads the peer's blob, one line, from standard input.
///
/// Exits with an error text when the line is missing or empty.
func readPeerBlob() -> String {
  FileHandle.standardError.write(Data("Paste the peer's blob, then press Return.\n".utf8))
  guard let line = readLine(), !line.isEmpty else { fail("No blob on stdin.") }
  return line
}

/// Exchanges the blobs, waits for the data channel, and runs the bridge of the role until it ends.
///
/// The offerer prints its blob first; the answerer reads the peer's blob first.
func run() async throws {
  let link = try PeerLink(role: signal, iceServers: options["ice-server"] ?? [])
  if signal == .offer {
    print(try await link.localBlob())
    fflush(stdout)
    try await link.accept(readPeerBlob())
  } else {
    try await link.accept(readPeerBlob())
    print(try await link.localBlob())
    fflush(stdout)
  }
  await link.waitUntilOpen()
  let credentials = EndpointCredentials(
    socketPath: socketPath(),
    token: token,
    tokenName: options["token-name"]?.first ?? "bridge"
  )
  let ended = AsyncStream<Void>.makeStream()
  let report: @Sendable (Error?) -> Void = { error in
    if let error { FileHandle.standardError.write(Data("\(error)\n".utf8)) }
    ended.continuation.yield()
  }
  if role == "host" {
    let bridge = HostBridge(link: link, persona: options["persona"]?.first ?? "Generic")
    bridge.onEnd = report
    try bridge.start(credentials)
  } else {
    let bridge = PlayerBridge(link: link, controller: options["controller"]?.first)
    bridge.onRumble = { line in
      if let data = try? JSONSerialization.data(withJSONObject: line),
        let text = String(data: data, encoding: .utf8)
      {
        print(text)
        fflush(stdout)
      }
    }
    bridge.onEnd = report
    try bridge.start(credentials)
  }
  for await _ in ended.stream { break }
  link.close()
}

do { try await run() } catch { fail("\(error)") }
