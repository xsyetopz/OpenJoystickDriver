import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

@Suite(.serialized)
struct VirtualFeedRegistryTests {
  /// A virtual controller that records what the registry does with it.
  private final class FakeDevice: VirtualFeedDevice, @unchecked Sendable {
    let profile: VirtualHIDProfileID
    let output: UserSpaceOutputDispatcher.OutputCommandHandler
    let failsActivation: Bool
    private let lock = NSLock()
    private var activatedValue: DeviceIdentifier?
    private var sentValue: [RemappingGamepadState] = []
    private var closeCountValue = 0

    init(
      profile: VirtualHIDProfileID,
      output: @escaping UserSpaceOutputDispatcher.OutputCommandHandler,
      failsActivation: Bool
    ) {
      self.profile = profile
      self.output = output
      self.failsActivation = failsActivation
    }

    var activated: DeviceIdentifier? { lock.withLock { activatedValue } }
    var sent: [RemappingGamepadState] { lock.withLock { sentValue } }
    var closeCount: Int { lock.withLock { closeCountValue } }

    func activate(controller identifier: DeviceIdentifier) throws {
      if failsActivation { throw UserSpaceOutputDispatcher.CreationError.createFailed }
      lock.withLock { activatedValue = identifier }
    }

    func send(_ state: RemappingGamepadState, for identifier: DeviceIdentifier) throws {
      lock.withLock { sentValue.append(state) }
    }

    func close() { lock.withLock { closeCountValue += 1 } }

    /// The host writes `command` to this device.
    func receive(_ command: ControllerOutputCommand) {
      output(activated ?? DeviceIdentifier(vendorID: 0, productID: 0), command)
    }
  }

  /// Builds `FakeDevice`s and keeps every one it built.
  private final class Factory: @unchecked Sendable {
    private let lock = NSLock()
    private var devicesValue: [FakeDevice] = []
    var failsActivation = false

    var devices: [FakeDevice] { lock.withLock { devicesValue } }

    func registry(idleTimeout: TimeInterval = 60) -> VirtualFeedRegistry {
      VirtualFeedRegistry(
        factory: { profile, output in
          self.lock.withLock {
            let device = FakeDevice(
              profile: profile,
              output: output,
              failsActivation: self.failsActivation
            )
            self.devicesValue.append(device)
            return device
          }
        },
        idleTimeout: idleTimeout
      )
    }
  }

  @Test
  func aFeedPublishesItsProfileSendsFramesWithYDownAndReturnsTheHostsCommands() async throws {
    let factory = Factory()
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
    let result = try await registry.exchange(token: session.token, frame: frame)

    #expect(
      result
        == VirtualFeedExchangeResult(
          feedback: [.setRumble(.off, duration: .held), .stopRumble],
          closed: false
        )
    )
    #expect(
      device.sent == [
        RemappingGamepadState(buttons: [.south], axes: [.leftStickY: -0.5, .leftStickX: 0.25])
      ]
    )
    let empty = try await registry.exchange(token: session.token, frame: nil)
    #expect(empty == VirtualFeedExchangeResult(feedback: [], closed: false))
    #expect(device.sent.count == 1)
  }

  @Test
  func closingRemovesTheDeviceOnceAndLaterExchangesReportClosed() async throws {
    let factory = Factory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "hid-generic")

    #expect(await registry.close(token: session.token))
    #expect(!(await registry.close(token: session.token)))
    #expect(factory.devices.first?.closeCount == 1)
    #expect(registry.openFeedCount == 0)
    let result = try await registry.exchange(token: session.token, frame: VirtualFeedFrame())
    #expect(result == VirtualFeedExchangeResult(feedback: [], closed: true))
  }

  @Test(.timeLimit(.minutes(1)))
  func aFeedWithoutExchangesClosesAfterTheIdleTimeout() async throws {
    let factory = Factory()
    let registry = factory.registry(idleTimeout: 0.1)
    let session = try await registry.open(profile: "hid-generic")
    while registry.openFeedCount > 0 { try await Task.sleep(nanoseconds: 10_000_000) }

    #expect(factory.devices.first?.closeCount == 1)
    let result = try await registry.exchange(token: session.token, frame: nil)
    #expect(result.closed)
  }

  @Test
  func theFifthFeedIsRefusedAndItsDeviceClosed() async throws {
    let factory = Factory()
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
    let factory = Factory()
    let registry = factory.registry()

    await #expect(throws: VirtualFeedError.unknownProfile("hid-unknown")) {
      try await registry.open(profile: "hid-unknown")
    }
    #expect(factory.devices.isEmpty)
  }

  @Test
  func aFailedActivationClosesTheDeviceAndKeepsNoFeed() async throws {
    let factory = Factory()
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
    let factory = Factory()
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
    let factory = Factory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "hid-generic")
    let device = try #require(factory.devices.first)
    let limit = VirtualFeedRegistry.maximumQueuedFeedback
    for index in 0..<(limit + 2) {
      device.receive(.setRumble(.off, duration: .milliseconds(index)))
    }

    let result = try await registry.exchange(token: session.token, frame: nil)
    #expect(result.feedback.count == limit)
    #expect(result.feedback.first == .setRumble(.off, duration: .milliseconds(2)))
    #expect(result.feedback.last == .setRumble(.off, duration: .milliseconds(limit + 1)))
  }
}
