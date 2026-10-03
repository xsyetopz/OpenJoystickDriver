import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct VirtualFeedCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "feed",
    abstract: CLILocalized.text(
      "cli.virtual.feed.abstract",
      "Publish a virtual gamepad that standard input drives."
    ),
    discussion: CLILocalized.text(
      "cli.virtual.feed.discussion",
      "Reads one JSON object per line: 'buttons' and 'dpad' list the pressed controls, such as "
        + "south and up, and 'axes' maps axis names, such as left_stick_x, to values. Missing "
        + "controls are neutral. Sticks run from -1 to 1 with Y up; triggers run from 0 to 1. "
        + "Prints each output command that games send to the gamepad, such as rumble, as one JSON "
        + "object per line. Stops when the input ends."
    )
  )

  /// How often an idle feed tells the service that it is still open.
  static let heartbeatSeconds = 0.5

  /// Standard input split into lines; tests replace it.
  @TaskLocal
  static var standardInputLines: @Sendable () -> AsyncStream<String> = {
    AsyncStream { continuation in
      Thread.detachNewThread {
        while let line = readLine() { continuation.yield(line) }
        continuation.finish()
      }
    }
  }

  @OptionGroup
  var global: GlobalOptions

  @Option(
    name: .customLong("as"),
    help: ArgumentHelp(
      CLILocalized.text("cli.virtual.feed.profile", "The virtual gamepad profile to publish."),
      valueName: "profile"
    )
  )
  var profile: VirtualHIDProfileID

  func run() async throws {
    try await global.run {
      let client = try await ServiceConnection.open()
      defer { client.disconnect() }
      let timeout = CLIContext.current.requestTimeout
      let name = profile.rawValue
      let token = try await ServiceConnection.withDeadline(seconds: timeout) {
        try await client.openVirtualFeed(profile: name).token
      }
      let close: @Sendable () async -> Void = {
        _ = await withTimeout(seconds: timeout) { try await client.closeVirtualFeed(token: token) }
      }
      try await withCLIShutdownCleanup(close) {
        if CLIContext.current.format == .human {
          CLIOutput.success(
            CLILocalized.format(
              "cli.virtual.feed.started",
              "Publishing a %@ virtual gamepad. Write frames on standard input; end the input or "
                + "press Control-C to stop.",
              name
            )
          )
        }
        do { try await Self.feed(client, token: token, timeout: timeout) } catch {
          await close()
          throw error
        }
        await close()
      }
    }
  }

  /// Sends the latest frame at most every 16 ms, and a heartbeat when no frame arrives, until
  /// the input ends.
  private static func feed(
    _ client: ApplicationServiceClient,
    token: UUID,
    timeout: Double
  ) async throws {
    let input = Locked(Input())
    let lines = standardInputLines()
    let reader = Task {
      var number = 0
      for await line in lines {
        number += 1
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { continue }
        guard let frame = try? JSONDecoder().decode(VirtualFeedFrame.self, from: Data(text.utf8))
        else {
          input.withLock { $0.invalidLine = number }
          return
        }
        input.withLock { $0.frame = frame }
      }
      input.withLock { $0.finished = true }
    }
    defer { reader.cancel() }
    var lastExchange = 0.0
    while true {
      let next = input.withLock { state -> Input in
        defer { state.frame = nil }
        return state
      }
      if let line = next.invalidLine {
        throw CLIFailure.usage(
          CLILocalized.format(
            "cli.virtual.feed.error.frame",
            "Line %@ is not a valid frame. 'ojd virtual feed --help' shows the format.",
            String(line)
          )
        )
      }
      let now = ProcessInfo.processInfo.systemUptime
      if next.frame != nil || now - lastExchange >= heartbeatSeconds {
        lastExchange = now
        let frame = next.frame
        let result = try await ServiceConnection.withDeadline(seconds: timeout) {
          try await client.exchangeVirtualFeed(token: token, frame: frame)
        }
        for command in result.feedback { try CLIOutput.jsonLine(command) }
        if result.closed {
          throw CLIFailure(
            .failure,
            CLILocalized.text(
              "cli.virtual.feed.error.closed",
              "The service closed the virtual gamepad. Check it with 'ojd status'."
            )
          )
        }
      }
      if next.finished { return }
      try await Task.sleep(nanoseconds: 16_000_000)
    }
  }

  /// What the input reader has seen since the last exchange.
  private struct Input: Sendable {
    var frame: VirtualFeedFrame?
    var finished = false
    /// The 1-based number of the first line that is not a frame.
    var invalidLine: Int?
  }
}
