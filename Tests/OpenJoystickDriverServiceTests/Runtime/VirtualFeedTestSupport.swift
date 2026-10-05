import Foundation
import OpenJoystickDriverKit

@testable import OpenJoystickDriverService

/// A virtual controller that records what the registry does with it.
final class FakeFeedDevice: VirtualFeedDevice, @unchecked Sendable {
  let profile: VirtualHIDProfileID
  let output: UserSpaceOutputDispatcher.OutputCommandHandler
  let failsActivation: Bool
  let hangsActivation: Bool
  var failsSending = false
  private let lock = NSLock()
  /// The hung activation and closes, resumed by `release`.
  private var hung: [CheckedContinuation<Void, Never>] = []
  private var released = false
  private var activatedValue: DeviceIdentifier?
  private var sentValue: [RemappingGamepadState] = []
  /// `ProcessInfo.systemUptime` of each send.
  private var sentTimesValue: [TimeInterval] = []
  private var closeCountValue = 0

  init(
    profile: VirtualHIDProfileID,
    output: @escaping UserSpaceOutputDispatcher.OutputCommandHandler,
    failsActivation: Bool,
    hangsActivation: Bool
  ) {
    self.profile = profile
    self.output = output
    self.failsActivation = failsActivation
    self.hangsActivation = hangsActivation
  }

  var activated: DeviceIdentifier? { lock.withLock { activatedValue } }
  var sent: [RemappingGamepadState] { lock.withLock { sentValue } }
  var sentTimes: [TimeInterval] { lock.withLock { sentTimesValue } }
  var closeCount: Int { lock.withLock { closeCountValue } }

  /// A hanging activation ignores cancellation and returns only after `release`.
  func activate(controller identifier: DeviceIdentifier) async throws {
    if hangsActivation {
      await waitForRelease()
      return
    }
    if failsActivation { throw UserSpaceOutputDispatcher.CreationError.createFailed }
    lock.withLock { activatedValue = identifier }
  }

  func send(_ state: RemappingGamepadState, for identifier: DeviceIdentifier) throws {
    if failsSending { throw UserSpaceOutputDispatcher.CreationError.createFailed }
    lock.withLock {
      sentValue.append(state)
      sentTimesValue.append(ProcessInfo.processInfo.systemUptime)
    }
  }

  /// Like `UserSpaceOutputDispatcher`, closing waits for a hung activation.
  func close() async {
    lock.withLock { closeCountValue += 1 }
    if hangsActivation { await waitForRelease() }
  }

  /// Ends a hung activation and the closes that wait for it, so no task outlives the test.
  func release() {
    let waiting = lock.withLock {
      released = true
      defer { hung = [] }
      return hung
    }
    waiting.forEach { $0.resume() }
  }

  private func waitForRelease() async {
    await withCheckedContinuation { continuation in
      let done = lock.withLock {
        if !released { hung.append(continuation) }
        return released
      }
      if done { continuation.resume() }
    }
  }

  /// The host writes `command` to this device.
  func receive(_ command: ControllerOutputCommand) {
    output(activated ?? DeviceIdentifier(vendorID: 0, productID: 0), command)
  }
}

/// Builds `FakeFeedDevice`s and keeps every one it built.
final class FakeFeedFactory: @unchecked Sendable {
  private let lock = NSLock()
  private var devicesValue: [FakeFeedDevice] = []
  var failsActivation = false
  var hangsActivation = false

  var devices: [FakeFeedDevice] { lock.withLock { devicesValue } }

  /// Releases every hung device.
  func release() { devices.forEach { $0.release() } }

  func registry(
    idleTimeout: TimeInterval = 60,
    activationTimeout: TimeInterval = VirtualFeedRegistry.activationTimeoutSeconds
  ) -> VirtualFeedRegistry {
    VirtualFeedRegistry(
      factory: { profile, output in
        self.lock.withLock {
          let device = FakeFeedDevice(
            profile: profile,
            output: output,
            failsActivation: self.failsActivation,
            hangsActivation: self.hangsActivation
          )
          self.devicesValue.append(device)
          return device
        }
      },
      idleTimeout: idleTimeout,
      activationTimeout: activationTimeout
    )
  }
}
