import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

@Suite(.serialized)
struct VirtualFeedRegistryTests {
  /// Waits until `condition` holds.
  private static func wait(until condition: () -> Bool) async throws {
    while !condition() { try await Task.sleep(nanoseconds: 2_000_000) }
  }

  @Test(.timeLimit(.minutes(1)))
  func aFeedPublishesItsProfileSendsFramesWithYDownAndReturnsTheHostsCommands() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "hid-generic")
    let device = try #require(factory.devices.first)
    #expect(device.profile == .generic)
    let identifier = try #require(device.activated)
    #expect(identifier.controllerIdentity.vendorID == VirtualHIDProfileID.generic.identity.vendorID)
    #expect(
      identifier.controllerIdentity.productID == VirtualHIDProfileID.generic.identity.productID
    )

    device.receive(.setRumble(.off, duration: .held))
    device.receive(.stopRumble)
    let frame = VirtualFeedFrame(buttons: [.south], axes: [.leftStickY: 0.5, .leftStickX: 0.25])
    let result = registry.exchange(token: session.token, frames: [frame])

    #expect(
      result
        == VirtualFeedExchangeResult(
          feedback: [.setRumble(.off, duration: .held), .stopRumble],
          closed: false,
          accepted: 1,
          queued: 1
        )
    )
    try await Self.wait { !device.sent.isEmpty }
    #expect(
      device.sent == [
        RemappingGamepadState(buttons: [.south], axes: [.leftStickY: -0.5, .leftStickX: 0.25])
      ]
    )
    try await Self.wait { registry.exchange(token: session.token, frames: []).queued == 0 }
    let empty = registry.exchange(token: session.token, frames: [])
    #expect(empty == VirtualFeedExchangeResult(feedback: [], closed: false))
    #expect(device.sent.count == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func framesPlayInOrderEachForItsHoldAndAtLeastTheMinimum() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "hid-generic")
    let device = try #require(factory.devices.first)
    let frames = [
      VirtualFeedFrame(buttons: [.south], holdMilliseconds: 100), VirtualFeedFrame(),
      VirtualFeedFrame(dpad: [.up]), VirtualFeedFrame(holdMilliseconds: 0),
    ]

    let result = registry.exchange(token: session.token, frames: frames)
    #expect(result.accepted == 4)
    #expect(result.queued == 4)
    try await Self.wait { device.sent.count == 4 }

    #expect(device.sent == frames.map(\.gamepadState))
    let times = device.sentTimes
    #expect(times[1] - times[0] >= 0.1)
    let minimum = Double(VirtualFeedExchangeResult.minimumFrameMilliseconds) / 1000
    #expect(times[2] - times[1] >= minimum)
    #expect(times[3] - times[2] >= minimum)
  }

  @Test(.timeLimit(.minutes(1)))
  func queuedFramesCoalesceOnlyWhenButtonsAndDpadMatchWithoutAHold() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "hid-generic")
    let device = try #require(factory.devices.first)
    let frames = [
      VirtualFeedFrame(buttons: [.south], axes: [.leftStickX: 0.1]),
      VirtualFeedFrame(buttons: [.south], axes: [.leftStickX: 0.2]),
      VirtualFeedFrame(buttons: [.south], axes: [.leftStickX: 0.3]),
      VirtualFeedFrame(), VirtualFeedFrame(axes: [.leftStickX: 1]),
      VirtualFeedFrame(holdMilliseconds: 10), VirtualFeedFrame(),
    ]

    let result = registry.exchange(token: session.token, frames: frames)
    #expect(result.accepted == frames.count)
    #expect(result.queued == 4)
    try await Self.wait { registry.exchange(token: session.token, frames: []).queued == 0 }

    #expect(
      device.sent
        == [frames[2], frames[4], frames[5], frames[6]].map(\.gamepadState)
    )
  }

  @Test
  func aFullQueueAcceptsOnlyTheFramesThatFit() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "hid-generic")
    let limit = VirtualFeedExchangeResult.maximumQueuedFrames
    let frames = (0..<(limit + 10)).map {
      $0.isMultiple(of: 2) ? VirtualFeedFrame(buttons: [.south]) : VirtualFeedFrame()
    }

    let result = registry.exchange(token: session.token, frames: frames)
    #expect(result.accepted == limit)
    #expect(result.queued == limit)
    await registry.close(token: session.token)
  }

  @Test(.timeLimit(.minutes(1)))
  func closingStopsTheFramesThatWait() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "hid-generic")
    let device = try #require(factory.devices.first)
    _ = registry.exchange(
      token: session.token,
      frames: [VirtualFeedFrame(buttons: [.south], holdMilliseconds: 60_000), VirtualFeedFrame()]
    )
    try await Self.wait { !device.sent.isEmpty }

    #expect(await registry.close(token: session.token))
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(device.sent.count == 1)
    #expect(device.closeCount == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func aFailedSendClosesTheFeed() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "hid-generic")
    let device = try #require(factory.devices.first)
    device.failsSending = true

    _ = registry.exchange(token: session.token, frames: [VirtualFeedFrame()])
    try await Self.wait { registry.openFeedCount == 0 }

    #expect(device.closeCount == 1)
    #expect(registry.exchange(token: session.token, frames: []).closed)
  }

  @Test
  func closingRemovesTheDeviceOnceAndLaterExchangesReportClosed() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "hid-generic")

    #expect(await registry.close(token: session.token))
    #expect(!(await registry.close(token: session.token)))
    #expect(factory.devices.first?.closeCount == 1)
    #expect(registry.openFeedCount == 0)
    let result = registry.exchange(token: session.token, frames: [VirtualFeedFrame()])
    #expect(result == VirtualFeedExchangeResult(feedback: [], closed: true))
  }

  @Test(.timeLimit(.minutes(1)))
  func aFeedWithoutExchangesClosesAfterTheIdleTimeout() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry(idleTimeout: 0.1)
    let session = try await registry.open(profile: "hid-generic")
    while registry.openFeedCount > 0 { try await Task.sleep(nanoseconds: 10_000_000) }

    #expect(factory.devices.first?.closeCount == 1)
    #expect(registry.exchange(token: session.token, frames: []).closed)
  }

  @Test
  func theFifthFeedIsRefusedAndItsDeviceClosed() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    for _ in 0..<VirtualFeedRegistry.maximumFeeds {
      _ = try await registry.open(profile: "hid-generic")
    }

    await #expect(throws: VirtualFeedError.tooManyFeeds(VirtualFeedRegistry.maximumFeeds)) {
      try await registry.open(profile: "hid-xbox-one-s-bt")
    }
    #expect(factory.devices.last?.closeCount == 1)
    #expect(factory.devices.last?.activated == nil)
    #expect(registry.openFeedCount == VirtualFeedRegistry.maximumFeeds)
  }

  @Test
  func anUnknownProfileIsRefusedWithoutADevice() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()

    await #expect(throws: VirtualFeedError.unknownProfile("hid-unknown")) {
      try await registry.open(profile: "hid-unknown")
    }
    #expect(factory.devices.isEmpty)
  }

  @Test
  func aFailedActivationClosesTheDeviceAndKeepsNoFeed() async throws {
    let factory = FakeFeedFactory()
    factory.failsActivation = true
    let registry = factory.registry()

    await #expect(throws: VirtualFeedError.self) {
      try await registry.open(profile: "hid-generic")
    }
    #expect(factory.devices.first?.closeCount == 1)
    #expect(registry.openFeedCount == 0)
  }

  @Test
  func stoppingClosesEveryFeedAndRefusesNewOnes() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    _ = try await registry.open(profile: "hid-generic")
    _ = try await registry.open(profile: "hid-generic")

    await registry.stop()
    #expect(factory.devices.map(\.closeCount) == [1, 1])
    await #expect(throws: VirtualFeedError.serviceStopped) {
      try await registry.open(profile: "hid-generic")
    }
    #expect(factory.devices.last?.closeCount == 1)
  }

  @Test
  func uncollectedCommandsKeepOnlyTheNewest() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "hid-generic")
    let device = try #require(factory.devices.first)
    let limit = VirtualFeedRegistry.maximumQueuedFeedback
    for index in 0..<(limit + 2) {
      device.receive(.setRumble(.off, duration: .milliseconds(index)))
    }

    let result = registry.exchange(token: session.token, frames: [])
    #expect(result.feedback.count == limit)
    #expect(result.feedback.first == .setRumble(.off, duration: .milliseconds(2)))
    #expect(result.feedback.last == .setRumble(.off, duration: .milliseconds(limit + 1)))
  }
}
