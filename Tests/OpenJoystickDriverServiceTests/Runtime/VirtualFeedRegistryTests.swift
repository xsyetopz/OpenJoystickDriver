import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

@Suite(.serialized)
struct VirtualFeedRegistryTests {
  @Test
  func productionIdleTimeoutIsTwoSecondsAndIsRegistryDefault() {
    #expect(VirtualFeedExchangeResult.idleTimeoutSeconds == 2)
    let registry = VirtualFeedRegistry { _, _ in throw CancellationError() }
    #expect(registry.idleTimeout == VirtualFeedExchangeResult.idleTimeoutSeconds)
  }

  @Test(.timeLimit(.minutes(1)))
  func feedPublishesItsProfileSendsFramesAndReturnsHostsCommands() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "Generic")
    let device = try #require(factory.devices.first)
    #expect(device.profile == .generic)
    let identifier = try #require(device.activated)
    #expect(identifier.model.vendorID == VirtualHIDProfileID.generic.identity.vendorID)
    #expect(
      identifier.model.productID == VirtualHIDProfileID.generic.identity.productID
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
    await waitUntil("!device.sent.isEmpty") { !device.sent.isEmpty }
    #expect(
      device.sent == [
        RemappingGamepadState(buttons: [.south], axes: [.leftStickY: 0.5, .leftStickX: 0.25])
      ]
    )
    await waitUntil("registry.exchange(token: session.token, frames: []).queued == 0") {
      registry.exchange(token: session.token, frames: []).queued == 0
    }
    let empty = registry.exchange(token: session.token, frames: [])
    #expect(empty == VirtualFeedExchangeResult(feedback: [], closed: false))
    #expect(device.sent.count == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func framesPlayInOrderEachForItsHoldAndAtLeastMinimum() async throws {
    let factory = FakeFeedFactory()
    let time = ManualVirtualFeedClock()
    let registry = factory.registry(clock: time.clock)
    let session = try await registry.open(profile: "Generic")
    let device = try #require(factory.devices.first)
    let frames = [
      VirtualFeedFrame(buttons: [.south], holdMilliseconds: 100), VirtualFeedFrame(),
      VirtualFeedFrame(dpad: [.up]), VirtualFeedFrame(holdMilliseconds: 0),
    ]

    let result = registry.exchange(token: session.token, frames: frames)
    #expect(result.accepted == 4)
    #expect(result.queued == 4)
    let minimum = Double(VirtualFeedExchangeResult.minimumFrameMilliseconds) / 1000
    // The first frame goes out at once; each later one goes out when the previous one's time ends.
    for (index, step) in [0.1, minimum, minimum].enumerated() {
      await waitUntil("device.sent.count == \(index + 1)") { device.sent.count == index + 1 }
      await time.waitForSleeper(due: time.now + step)
      #expect(device.sent.count == index + 1)
      time.advance(by: step)
    }
    await waitUntil("device.sent.count == 4") { device.sent.count == 4 }

    #expect(device.sent == frames.map(\.gamepadState))
    let times = device.sentTimes
    #expect(times.first == 0)
    #expect(times[1] - times[0] >= 0.1 - 1e-9)
    #expect(times[2] - times[1] >= minimum - 1e-9)
    #expect(times[3] - times[2] >= minimum - 1e-9)
  }

  @Test(.timeLimit(.minutes(1)))
  func delayedSendDoesNotShortenNextGapBelowMinimum() async throws {
    let factory = FakeFeedFactory()
    let time = ManualVirtualFeedClock()
    let registry = factory.registry(clock: time.clock)
    let session = try await registry.open(profile: "Generic")
    let device = try #require(factory.devices.first)
    let minimum = Double(VirtualFeedExchangeResult.minimumFrameMilliseconds) / 1000
    let delay = minimum * 4
    // The first send takes four minimums on the clock before it returns.
    device.duringSend = { sent in if sent == 0 { time.advance(by: delay) } }
    let frames = [VirtualFeedFrame(buttons: [.south]), VirtualFeedFrame(buttons: [.east])]

    #expect(registry.exchange(token: session.token, frames: frames).accepted == 2)
    await waitUntil("device.sent.count == 1") { device.sent.count == 1 }
    await time.waitForSleeper(due: delay + minimum)
    #expect(device.sent.count == 1)
    time.advance(by: minimum)
    await waitUntil("device.sent.count == 2") { device.sent.count == 2 }

    let times = device.sentTimes
    #expect(times[1] - times[0] >= minimum - 1e-9)
  }

  @Test(.timeLimit(.minutes(1)))
  func queuedFramesCoalesceOnlyWhenButtonsAndDpadMatchWithoutHold() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "Generic")
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
    await waitUntil("registry.exchange(token: session.token, frames: []).queued == 0") {
      registry.exchange(token: session.token, frames: []).queued == 0
    }

    #expect(
      device.sent
        == [frames[2], frames[4], frames[5], frames[6]].map(\.gamepadState)
    )
  }

  @Test
  func fullQueueAcceptsOnlyFramesThatFit() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "Generic")
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
  func closingStopsFramesThatWait() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "Generic")
    let device = try #require(factory.devices.first)
    _ = registry.exchange(
      token: session.token,
      frames: [VirtualFeedFrame(buttons: [.south], holdMilliseconds: 60_000), VirtualFeedFrame()]
    )
    await waitUntil("!device.sent.isEmpty") { !device.sent.isEmpty }

    #expect(await registry.close(token: session.token))
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(device.sent.count == 1)
    #expect(device.closeCount == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func failedSendClosesFeed() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "Generic")
    let device = try #require(factory.devices.first)
    device.failsSending = true

    _ = registry.exchange(token: session.token, frames: [VirtualFeedFrame()])
    // The registry drops the feed before it awaits the device's close, so the count alone does
    // not say the device is closed.
    await waitUntil("registry.openFeedCount == 0 && device.closeCount > 0") {
      registry.openFeedCount == 0 && device.closeCount > 0
    }

    #expect(device.closeCount == 1)
    #expect(registry.exchange(token: session.token, frames: []).closed)
  }

  @Test
  func closingRemovesDeviceOnceAndLaterExchangesReportClosed() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "Generic")

    #expect(await registry.close(token: session.token))
    #expect(!(await registry.close(token: session.token)))
    #expect(factory.devices.first?.closeCount == 1)
    #expect(registry.openFeedCount == 0)
    let result = registry.exchange(token: session.token, frames: [VirtualFeedFrame()])
    #expect(result == VirtualFeedExchangeResult(feedback: [], closed: true))
  }

  @Test(.timeLimit(.minutes(1)))
  func feedWithoutExchangesClosesAfterIdleTimeout() async throws {
    let factory = FakeFeedFactory()
    let time = ManualVirtualFeedClock()
    let registry = factory.registry(idleTimeout: 0.125, clock: time.clock)
    let session = try await registry.open(profile: "Generic")
    let device = try #require(factory.devices.first)
    await time.waitForSleepers(1)

    time.advance(by: 0.0625)
    await time.waitForSleepers(1)
    #expect(registry.openFeedCount == 1)
    time.advance(by: 0.0625)
    await waitUntil("registry.openFeedCount == 0 && device.closeCount > 0") {
      registry.openFeedCount == 0 && device.closeCount > 0
    }

    #expect(device.closeCount == 1)
    #expect(registry.exchange(token: session.token, frames: []).closed)
  }

  @Test(.timeLimit(.minutes(1)))
  func burstThatPlaysLongerThanIdleTimeoutIsNotClosed() async throws {
    let factory = FakeFeedFactory()
    let time = ManualVirtualFeedClock()
    let registry = factory.registry(idleTimeout: 0.25, clock: time.clock)
    let session = try await registry.open(profile: "Generic")
    let device = try #require(factory.devices.first)
    let frames = (0..<6).map {
      VirtualFeedFrame(buttons: $0.isMultiple(of: 2) ? [.south] : [.east], holdMilliseconds: 125)
    }
    #expect(registry.exchange(token: session.token, frames: frames).accepted == frames.count)

    // Each step plays one frame; the burst takes 0.75 seconds, three times the idle timeout.
    for played in 1...frames.count {
      await waitUntil("device.sent.count == played") { device.sent.count == played }
      // The frame's own wait ends at its start plus its hold; wait for that one by name.
      await time.waitForSleeper(due: 0.125 * Double(played))
      #expect(registry.openFeedCount == 1)
      time.advance(by: 0.125)
    }
    #expect(device.closeCount == 0)
    // The idle time counts from the end of the last frame, which the player records.
    await waitUntil("registry.lastExchangeTimes.contains(time.now)") {
      registry.lastExchangeTimes.contains(time.now)
    }
    time.advance(by: 0.1875)
    await time.waitForSleepers(1)
    #expect(registry.openFeedCount == 1)
    time.advance(by: 0.0625)
    await waitUntil("registry.openFeedCount == 0") { registry.openFeedCount == 0 }
    #expect(device.sent.count == frames.count)
  }

  @Test(.timeLimit(.minutes(1)))
  func frameHeldLongerThanIdleTimeoutIsNotClosedBeforeItsHoldEnds() async throws {
    let factory = FakeFeedFactory()
    let time = ManualVirtualFeedClock()
    let registry = factory.registry(idleTimeout: 0.25, clock: time.clock)
    let session = try await registry.open(profile: "Generic")
    let device = try #require(factory.devices.first)
    _ = registry.exchange(
      token: session.token,
      frames: [VirtualFeedFrame(buttons: [.south], holdMilliseconds: 750)]
    )
    await waitUntil("device.sent.count == 1") { device.sent.count == 1 }
    await time.waitForSleepers(2)

    // Two idle timeouts pass while the frame is still held.
    time.advance(by: 0.5)
    await time.waitForSleepers(2)
    #expect(registry.openFeedCount == 1)
    // The hold ends at 0.75; the idle time counts from there, not from the exchange.
    time.advance(by: 0.25)
    await waitUntil("registry.lastExchangeTimes.contains(0.75)") {
      registry.lastExchangeTimes.contains(0.75)
    }
    await time.waitForSleepers(1)
    time.advance(by: 0.1875)
    await time.waitForSleepers(1)
    #expect(registry.openFeedCount == 1)
    time.advance(by: 0.0625)
    await waitUntil("registry.openFeedCount == 0") { registry.openFeedCount == 0 }
    #expect(factory.devices.first?.closeCount == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func sendThatHangsClosesFeedOnceFrameTimePlusIdleTimeoutPasses() async throws {
    let factory = FakeFeedFactory()
    let time = ManualVirtualFeedClock()
    let registry = factory.registry(idleTimeout: 0.25, clock: time.clock)
    defer { factory.release() }
    let session = try await registry.open(profile: "Generic")
    let device = try #require(factory.devices.first)
    device.hangsSending = true
    _ = registry.exchange(
      token: session.token,
      frames: [VirtualFeedFrame(buttons: [.south], holdMilliseconds: 250)]
    )
    await waitUntil("device.hungCount == 1") { device.hungCount == 1 }
    await time.waitForSleepers(1)

    // The frame time is 0.25 and the idle timeout 0.25, so the feed closes at 0.5.
    time.advance(by: 0.4375)
    await time.waitForSleepers(1)
    #expect(registry.openFeedCount == 1)
    time.advance(by: 0.0625)
    // The registry drops the session before it awaits the close, so wait for the close itself.
    await waitUntil("device.closeCount == 1") { device.closeCount == 1 }
    #expect(registry.openFeedCount == 0)
    #expect(registry.exchange(token: session.token, frames: []).closed)
  }

  @Test
  func fifthFeedIsRefusedBeforeItsDeviceIsBuilt() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    for _ in 0..<VirtualFeedRegistry.maximumFeeds {
      _ = try await registry.open(profile: "Generic")
    }

    await #expect(throws: VirtualFeedError.tooManyFeeds(VirtualFeedRegistry.maximumFeeds)) {
      try await registry.open(profile: "SDLCompatible")
    }
    #expect(factory.devices.count == VirtualFeedRegistry.maximumFeeds)
    #expect(registry.openFeedCount == VirtualFeedRegistry.maximumFeeds)
  }

  @Test
  func endpointFeedsAndRPCFeedsEachHaveTheirOwnLimit() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let limit = VirtualFeedRegistry.maximumFeeds
    for _ in 0..<limit { _ = try await registry.open(profile: "Generic", pool: .endpoint) }

    await #expect(throws: VirtualFeedError.tooManyFeeds(limit)) {
      try await registry.open(profile: "Generic", pool: .endpoint)
    }
    for _ in 0..<limit { _ = try await registry.open(profile: "Generic", pool: .rpc) }
    await #expect(throws: VirtualFeedError.tooManyFeeds(limit)) {
      try await registry.open(profile: "Generic", pool: .rpc)
    }
    #expect(registry.openFeedCount == 2 * limit)
  }

  @Test(.timeLimit(.minutes(1)))
  func activationThatHangsFailsAfterTimeoutAndKeepsNoFeed() async throws {
    let factory = FakeFeedFactory()
    factory.hangsActivation = true
    let registry = factory.registry(activationTimeout: 0.1)
    defer { factory.release() }

    await #expect(throws: VirtualFeedError.self) {
      try await registry.open(profile: "Generic")
    }
    #expect(registry.openFeedCount == 0)
    await waitUntil("factory.devices.first?.closeCount == 1") {
      factory.devices.first?.closeCount == 1
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func cancellingOpenThatHangsClosesItsDevice() async throws {
    let factory = FakeFeedFactory()
    factory.hangsActivation = true
    let registry = factory.registry(activationTimeout: 60)
    defer { factory.release() }
    let opening = Task { try await registry.open(profile: "Generic") }
    await waitUntil("!factory.devices.isEmpty") { !factory.devices.isEmpty }

    opening.cancel()
    await #expect(throws: CancellationError.self) { try await opening.value }
    #expect(registry.openFeedCount == 0)
    await waitUntil("factory.devices.first?.closeCount == 1") {
      factory.devices.first?.closeCount == 1
    }
  }

  @Test
  func unknownProfileIsRefusedWithoutDevice() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()

    await #expect(throws: VirtualFeedError.unknownProfile("hid-unknown")) {
      try await registry.open(profile: "hid-unknown")
    }
    #expect(factory.devices.isEmpty)
  }

  @Test
  func failedActivationClosesDeviceAndKeepsNoFeed() async throws {
    let factory = FakeFeedFactory()
    factory.failsActivation = true
    let registry = factory.registry()

    await #expect(throws: VirtualFeedError.self) {
      try await registry.open(profile: "Generic")
    }
    #expect(registry.openFeedCount == 0)
    await waitUntil("factory.devices.first?.closeCount == 1") {
      factory.devices.first?.closeCount == 1
    }
  }

  @Test
  func cancellationThrownByActivationFailsItInsteadOfCancellingOpen() async throws {
    let factory = FakeFeedFactory()
    factory.cancelsActivation = true
    let registry = factory.registry()

    await #expect(throws: VirtualFeedError.self) {
      try await registry.open(profile: "Generic")
    }
    #expect(registry.openFeedCount == 0)
    await waitUntil("factory.devices.first?.closeCount == 1") {
      factory.devices.first?.closeCount == 1
    }
  }

  @Test
  func stoppingClosesEveryFeedAndRefusesNewOnes() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    _ = try await registry.open(profile: "Generic")
    _ = try await registry.open(profile: "Generic")

    await registry.stop()
    #expect(factory.devices.map(\.closeCount) == [1, 1])
    await #expect(throws: VirtualFeedError.serviceStopped) {
      try await registry.open(profile: "Generic")
    }
    #expect(factory.devices.last?.closeCount == 1)
  }

  @Test
  func uncollectedCommandsKeepOnlyNewest() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "Generic")
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
