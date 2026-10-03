import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct VirtualFeedCommandTests {
  private static let token = UUID()

  /// A service with one open feed whose first exchange returns `result`; later exchanges return
  /// no commands with the same `closed`.
  private static func service(
    result: VirtualFeedExchangeResult = VirtualFeedExchangeResult(feedback: [], closed: false)
  ) throws -> FakeService {
    let later = VirtualFeedExchangeResult(feedback: [], closed: result.closed)
    let exchanged = NSLock()
    nonisolated(unsafe) var first = true
    return try FakeService(devices: []) { method, _ in
      switch method {
      case .openVirtualFeed: return encoded(VirtualFeedSession(token: token))
      case .exchangeVirtualFeed:
        let isFirst = exchanged.withLock {
          defer { first = false }
          return first
        }
        return encoded(isFirst ? result : later)
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

  @Test
  func theLatestFrameReachesTheFeedAndTheFeedClosesWhenTheInputEnds() async throws {
    let service = try Self.service()
    let result = await Self.run(
      service,
      input: [
        #"{"buttons":["east"]}"#, "",
        #"{"buttons":["south"],"dpad":["up"],"axes":{"left_stick_y":0.5}}"#,
      ]
    )

    #expect(result.code == 0, "\(result.standardError)")
    #expect(result.standardOutput.isEmpty)
    let opened = try #require(service.arguments(of: .openVirtualFeed).first)
    let open = try JSONDecoder().decode(LocalServiceRPCVirtualFeedOpenArguments.self, from: opened)
    #expect(open.profile == "hid-generic")
    let exchanged = try #require(service.arguments(of: .exchangeVirtualFeed).last)
    let exchange = try JSONDecoder().decode(
      LocalServiceRPCVirtualFeedExchangeArguments.self,
      from: exchanged
    )
    #expect(exchange.token == Self.token)
    #expect(
      exchange.frame
        == VirtualFeedFrame(buttons: [.south], dpad: [.up], axes: [.leftStickY: 0.5])
    )
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

  @Test(arguments: [#"{"buttons":["jump"]}"#, "not json", #"{"axes":{"x":1}}"#])
  func aLineThatIsNotAFrameExitsSixtyFourAndClosesTheFeed(line: String) async throws {
    let service = try Self.service()
    let result = await Self.run(service, input: ["{}", "", line])

    #expect(result.code == 64)
    #expect(result.standardError.contains("Line 3"), "\(result.standardError)")
    #expect(service.arguments(of: .closeVirtualFeed).count == 1)
  }

  @Test
  func aFeedTheServiceClosedExitsOne() async throws {
    let service = try Self.service(
      result: VirtualFeedExchangeResult(feedback: [], closed: true)
    )
    let result = await Self.run(service, input: ["{}"])

    #expect(result.code == 1)
    #expect(result.standardError.contains("closed the virtual gamepad"))
  }

  @Test
  func anUnknownProfileIsAUsageError() async throws {
    let service = try Self.service()
    let result = await service.run(["virtual", "feed", "--as", "hid-unknown"])

    #expect(result.code == 64)
    #expect(service.arguments(of: .openVirtualFeed).isEmpty)
  }
}
