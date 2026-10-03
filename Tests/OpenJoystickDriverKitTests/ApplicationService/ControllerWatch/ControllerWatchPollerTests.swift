import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct ControllerWatchPollerTests {
  @Test
  func reportsConnectionsAndOnlyChangedInput() async throws {
    let source = FakeWatchSource()
    source.set(devices: ["pad-1", "pad-2"], state: ControllerState(pressed: [.faceSouth]))
    var poller = ControllerWatchPoller(source: source)

    let first = try await poller.poll(now: 0, includeOutput: false)
    let second = try await poller.poll(now: 16_000_000, includeOutput: false)
    source.set(devices: ["pad-1"], state: ControllerState(pressed: [.faceEast]))
    let third = try await poller.poll(now: 32_000_000, includeOutput: false)
    let fourth = try await poller.poll(
      now: ControllerWatchPoller.deviceListInterval,
      includeOutput: false
    )

    #expect(
      first.map(\.summary) == ["connected pad-1", "connected pad-2", "input pad-1", "input pad-2"]
    )
    #expect(second.isEmpty)
    // The list is read again only after the interval, so pad-2 is still read until then.
    #expect(third.map(\.summary) == ["input pad-1", "input pad-2"])
    #expect(fourth.map(\.summary) == ["disconnected pad-2"])
    #expect(first[0].event.controller?.id == "pad-1")
    #expect(first[2].event.input == ControllerState(pressed: [.faceSouth]))
  }

  @Test
  func readsOutputOnlyWhenAsked() async throws {
    let source = FakeWatchSource()
    source.set(devices: ["pad-1"], state: ControllerState())
    var poller = ControllerWatchPoller(source: source)

    let without = try await poller.poll(now: 0, includeOutput: false)
    let with = try await poller.poll(now: 16_000_000, includeOutput: true)

    #expect(source.outputReads == 1)
    #expect(without.last?.event.output == nil)
    #expect(with.map(\.summary) == ["input pad-1"])
    #expect(with.last?.event.output == source.output)
  }
}

extension ControllerWatchPoller.Update {
  var summary: String { "\(event.type.rawValue) \(event.id)" }
}
