import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct VirtualFeedCommandTests {
  private static let token = UUID()

  /// A service with one open feed whose first exchange returns the commands in `result`; every
  /// exchange returns its `closed`, accepts at most `limit` frames, and reports the next count of
  /// `queued`, then 0.
  private static func service(
    result: VirtualFeedExchangeResult = VirtualFeedExchangeResult(feedback: [], closed: false),
    accepting limit: Int = .max,
    queued: [Int] = []
  ) throws -> FakeService {
    let exchanged = NSLock()
    nonisolated(unsafe) var first = true
    nonisolated(unsafe) var counts = queued
    return try FakeService(devices: []) { method, arguments in
      switch method {
      case .openVirtualFeed: return encoded(VirtualFeedSession(token: token))
      case .exchangeVirtualFeed:
        let sent =
          (try? JSONDecoder().decode(
            LocalServiceRPCVirtualFeedExchangeArguments.self,
            from: arguments
          ))?.frames.count ?? 0
        let (isFirst, count) = exchanged.withLock {
          defer { first = false }
          return (first, counts.isEmpty ? 0 : counts.removeFirst())
        }
        return encoded(
          VirtualFeedExchangeResult(
            feedback: isFirst ? result.feedback : [],
            closed: result.closed,
            accepted: min(limit, sent),
            queued: count
          )
        )
      case .closeVirtualFeed: return encoded(true)
      default: return nil
      }
    }
  }

  private static func run(
    _ service: FakeService,
    input lines: [String],
    _ arguments: [String] = []
  ) async -> CLIRun {
    let input: @Sendable () -> AsyncStream<String> = {
      AsyncStream { continuation in
        for line in lines { continuation.yield(line) }
        continuation.finish()
      }
    }
    return await VirtualFeedCommand.$standardInputLines.withValue(input) {
      await service.run(["virtual", "feed", "--as", "hid-generic"] + arguments)
    }
  }

  /// The arguments of each exchange the service received, oldest first.
  private static func exchanges(
    _ service: FakeService
  ) throws
    -> [LocalServiceRPCVirtualFeedExchangeArguments]
  {
    try service.arguments(of: .exchangeVirtualFeed).map {
      try JSONDecoder().decode(LocalServiceRPCVirtualFeedExchangeArguments.self, from: $0)
    }
  }

  @Test
  func everyFrameReachesTheFeedInOrderAndTheFeedClosesWhenTheInputEnds() async throws {
    let service = try Self.service()
    let result = await Self.run(
      service,
      input: [
        #"{"buttons":["south"],"holdMilliseconds":50}"#, "{}", "",
        #"{"buttons":["east"],"dpad":["up"],"axes":{"left_stick_y":0.5}}"#, "{}",
      ]
    )

    #expect(result.code == 0, "\(result.standardError)")
    #expect(result.standardOutput.isEmpty)
    let opened = try #require(service.arguments(of: .openVirtualFeed).first)
    let open = try JSONDecoder().decode(LocalServiceRPCVirtualFeedOpenArguments.self, from: opened)
    #expect(open.profile == "hid-generic")
    let exchanges = try Self.exchanges(service)
    #expect(exchanges.allSatisfy { $0.token == Self.token })
    #expect(
      exchanges.flatMap(\.frames) == [
        VirtualFeedFrame(buttons: [.south], holdMilliseconds: 50), VirtualFeedFrame(),
        VirtualFeedFrame(buttons: [.east], dpad: [.up], axes: [.leftStickY: 0.5]),
        VirtualFeedFrame(),
      ]
    )
    #expect(service.arguments(of: .closeVirtualFeed).count == 1)
  }

  @Test
  func framesTheFeedDidNotAcceptAreSentAgainInOrder() async throws {
    let service = try Self.service(accepting: 1)
    let input = [#"{"buttons":["south"]}"#, "{}", #"{"dpad":["up"]}"#, "{}"]
    let result = await Self.run(service, input: input)

    #expect(result.code == 0, "\(result.standardError)")
    let accepted = try Self.exchanges(service).compactMap(\.frames.first)
    #expect(
      accepted == [
        VirtualFeedFrame(buttons: [.south]), VirtualFeedFrame(), VirtualFeedFrame(dpad: [.up]),
        VirtualFeedFrame(),
      ]
    )
  }

  @Test
  func theFeedClosesOnlyAfterItPlayedEveryFrame() async throws {
    let service = try Self.service(queued: [3, 2, 1])
    let result = await Self.run(service, input: ["{}"])

    #expect(result.code == 0, "\(result.standardError)")
    #expect(try Self.exchanges(service).count >= 4)
    #expect(service.arguments(of: .closeVirtualFeed).count == 1)
  }

  @Test
  func eachOutputCommandIsPrintedAsOneJSONLine() async throws {
    let service = try Self.service(
      result: VirtualFeedExchangeResult(
        feedback: [.setRumble(.off, duration: .milliseconds(200)), .stopRumble],
        closed: false
      )
    )
    let result = await Self.run(service, input: ["{}"], ["--json"])

    #expect(result.code == 0, "\(result.standardError)")
    let lines = result.standardOutput.split(separator: "\n").map(String.init)
    #expect(lines.count == 2)
    #expect(lines.last == #"{"type":"stop-rumble"}"#)
    let first = try JSONDecoder().decode(
      ControllerOutputCommand.self,
      from: Data((lines.first ?? "").utf8)
    )
    #expect(first == .setRumble(.off, duration: .milliseconds(200)))
  }

  @Test(arguments: [
    #"{"buttons":["jump"]}"#, "not json", #"{"axes":{"x":1}}"#, #"{"holdMilliseconds":60001}"#,
    #"{"holdMilliseconds":-1}"#, #"{"buttons":["south","south"]}"#, #"{"dpad":["up","up"]}"#,
    #"{"button":["south"]}"#,
  ])
  func aLineThatIsNotAFrameExitsSixtyFourAndClosesTheFeed(line: String) async throws {
    let service = try Self.service()
    let result = await Self.run(service, input: ["{}", "", line])

    #expect(result.code == 64)
    #expect(result.standardError.contains("3"), "\(result.standardError)")
    #expect(service.arguments(of: .closeVirtualFeed).count == 1)
  }

  @Test
  func aFeedTheServiceClosedExitsOne() async throws {
    let service = try Self.service(
      result: VirtualFeedExchangeResult(feedback: [], closed: true)
    )
    let result = await Self.run(service, input: ["{}"])

    #expect(result.code == 1)
    #expect(result.standardError.contains("ojd status"))
  }

  @Test
  func anUnknownProfileIsAUsageError() async throws {
    let service = try Self.service()
    let result = await service.run(["virtual", "feed", "--as", "hid-unknown"])

    #expect(result.code == 64)
    #expect(service.arguments(of: .openVirtualFeed).isEmpty)
  }

  @Test
  func plainIsAUsageError() async throws {
    let service = try Self.service()
    let result = await Self.run(service, input: ["{}"], ["--plain"])

    #expect(result.code == 64)
    #expect(result.standardError.contains("--plain"))
    #expect(service.arguments(of: .openVirtualFeed).isEmpty)
  }
}
