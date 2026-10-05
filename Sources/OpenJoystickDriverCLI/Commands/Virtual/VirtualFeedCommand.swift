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
        + "Frames play in order, each for at least 8 ms; 'holdMilliseconds' keeps a frame longer, "
        + "up to 60000. Prints each output command that games send to the gamepad, such as "
        + "rumble, as one JSON object per line. Stops when every frame has played after the input "
        + "ends."
    )
  )

  /// How often an idle feed tells the service that it is still open.
  static let heartbeatSeconds = 0.5

  /// Standard input split into lines, read only when the feed asks for the next one; tests
  /// replace it.
  @TaskLocal
  static var standardInputLines: @Sendable () -> AsyncStream<String> = {
    let reader = DispatchQueue(label: "com.openjoystickdriver.ojd.virtual-feed.input")
    return AsyncStream {
      await withCheckedContinuation { continuation in
        reader.async { continuation.resume(returning: readLine()) }
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

  /// Sends each frame as soon as it is read, in order, and a heartbeat when no frame arrives,
  /// until the input ends and the feed has played every frame. Stops reading input while
  /// ``VirtualFeedExchangeResult/maximumQueuedFrames`` frames wait to be sent.
  private static func feed(
    _ client: ApplicationServiceClient,
    token: UUID,
    timeout: Double
  ) async throws {
    let input = Locked(Input())
    let lines = standardInputLines()
    var wake: AsyncStream<Void>.Continuation?
    let wakes = AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { wake = $0 }
    let signal = wake
    let reader = Task {
      defer { signal?.yield() }
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
        while input.withLock({ $0.pending.count >= VirtualFeedExchangeResult.maximumQueuedFrames })
        {
          try? await Task.sleep(nanoseconds: 4_000_000)
          if Task.isCancelled { return }
        }
        input.withLock { $0.pending.append(frame) }
        signal?.yield()
      }
      input.withLock { $0.finished = true }
    }
    let ticker = Task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 16_000_000)
        signal?.yield()
      }
    }
    defer {
      reader.cancel()
      ticker.cancel()
      signal?.finish()
    }
    var woken = wakes.makeAsyncIterator()
    var lastExchange = 0.0
    var queued = 0
    while true {
      let next = input.withLock { $0 }
      if let line = next.invalidLine {
        throw CLIFailure.usage(
          CLILocalized.format(
            "cli.virtual.feed.error.frame",
            "Line %@ is not a valid frame. 'ojd virtual feed --help' shows the format.",
            String(line)
          )
        )
      }
      let draining = next.finished && queued > 0
      let now = ProcessInfo.processInfo.systemUptime
      if !next.pending.isEmpty || draining || now - lastExchange >= heartbeatSeconds {
        lastExchange = now
        let frames = next.pending
        let result = try await ServiceConnection.withDeadline(seconds: timeout) {
          try await client.exchangeVirtualFeed(token: token, frames: frames)
        }
        input.withLock { $0.pending.removeFirst(min(result.accepted, frames.count)) }
        queued = result.queued
        for command in result.feedback { try CLIOutput.jsonLine(command) }
        if result.closed {
          throw CLIFailure(
            .serviceRequestFailed,
            CLILocalized.text(
              "cli.virtual.feed.error.closed",
              "The service closed the virtual gamepad. Check it with 'ojd status'."
            )
          )
        }
      }
      if next.finished, queued == 0, input.withLock({ $0.pending.isEmpty }) { return }
      guard await woken.next() != nil else { throw CancellationError() }
    }
  }

  /// What the input reader has seen and the feed has not accepted yet.
  private struct Input: Sendable {
    /// Frames to send, oldest first.
    var pending: [VirtualFeedFrame] = []
    var finished = false
    /// The 1-based number of the first line that is not a frame.
    var invalidLine: Int?
  }
}
