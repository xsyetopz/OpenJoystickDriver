import Foundation
import OpenJoystickDriverKit

@testable import OpenJoystickDriverService

/// A virtual controller that records what the registry does with it.
final class FakeFeedDevice: VirtualFeedDevice, @unchecked Sendable {
  let profile: VirtualHIDProfileID
  let output: UserSpaceOutputDispatcher.OutputCommandHandler
  let failsActivation: Bool
  let hangsActivation: Bool
  /// Activation throws a `CancellationError` although the calling task is not cancelled.
  let cancelsActivation: Bool
  /// Reads the registry clock, which stamps each send.
  let now: @Sendable () -> TimeInterval
  /// Runs inside every send with the number of sends before it, standing in for a slow device.
  var duringSend: (@Sendable (Int) -> Void)?
  var failsSending = false
  /// A hanging send returns only after `release`.
  var hangsSending = false
  private let lock = NSLock()
  /// The hung activation, sends, and closes, resumed by `release`.
  private var hung: [CheckedContinuation<Void, Never>] = []
  private var released = false
  private var activatedValue: LogicalControllerID?
  private var sentValue: [RemappingGamepadState] = []
  /// The registry clock's time at the end of each send.
  private var sentTimesValue: [TimeInterval] = []
  private var closeCountValue = 0

  /// How many calls are hung until `release`.
  var hungCount: Int { lock.withLock { hung.count } }

  init(
    profile: VirtualHIDProfileID,
    output: @escaping UserSpaceOutputDispatcher.OutputCommandHandler,
    failsActivation: Bool,
    hangsActivation: Bool,
    cancelsActivation: Bool,
    now: @escaping @Sendable () -> TimeInterval
  ) {
    self.now = now
    self.profile = profile
    self.output = output
    self.failsActivation = failsActivation
    self.hangsActivation = hangsActivation
    self.cancelsActivation = cancelsActivation
  }

  var activated: LogicalControllerID? { lock.withLock { activatedValue } }
  var sent: [RemappingGamepadState] { lock.withLock { sentValue } }
  var sentTimes: [TimeInterval] { lock.withLock { sentTimesValue } }
  var closeCount: Int { lock.withLock { closeCountValue } }

  /// A hanging activation ignores cancellation and returns only after `release`.
  func activate(controller identifier: LogicalControllerID) async throws {
    if hangsActivation {
      await waitForRelease()
      return
    }
    if cancelsActivation { throw CancellationError() }
    if failsActivation { throw UserSpaceOutputDispatcher.CreationError.createFailed }
    lock.withLock { activatedValue = identifier }
  }

  func send(_ state: RemappingGamepadState, for _: LogicalControllerID) async throws {
    if hangsSending { await waitForRelease() }
    if failsSending { throw UserSpaceOutputDispatcher.CreationError.createFailed }
    duringSend?(sent.count)
    let time = now()
    lock.withLock {
      sentValue.append(state)
      sentTimesValue.append(time)
    }
  }

  /// Like `UserSpaceOutputDispatcher`, closing waits for a hung activation.
  func close() async {
    lock.withLock { closeCountValue += 1 }
    if hangsActivation { await waitForRelease() }
  }

  /// Ends a hung activation or send and the closes that wait for it, so no task outlives the test.
  func release() {
    let waiting = lock.withLock {
      released = true
      defer { hung = [] }
      return hung
    }
    for waiter in waiting { waiter.resume() }
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
    output(activated ?? LogicalControllerID(vendorID: 0, productID: 0), command)
  }
}

/// Builds `FakeFeedDevice`s and keeps every one it built.
final class FakeFeedFactory: @unchecked Sendable {
  private let lock = NSLock()
  private var devicesValue: [FakeFeedDevice] = []
  var failsActivation = false
  var hangsActivation = false
  var cancelsActivation = false

  var devices: [FakeFeedDevice] { lock.withLock { devicesValue } }

  /// Releases every hung device.
  func release() { for device in devices { device.release() } }

  func registry(
    idleTimeout: TimeInterval = 60,
    activationTimeout: TimeInterval = VirtualFeedRegistry.activationTimeoutSeconds,
    clock: VirtualFeedClock = .system
  ) -> VirtualFeedRegistry {
    VirtualFeedRegistry(
      factory: { profile, output in
        self.lock.withLock {
          let device = FakeFeedDevice(
            profile: profile,
            output: output,
            failsActivation: self.failsActivation,
            hangsActivation: self.hangsActivation,
            cancelsActivation: self.cancelsActivation,
            now: clock.now
          )
          self.devicesValue.append(device)
          return device
        }
      },
      idleTimeout: idleTimeout,
      activationTimeout: activationTimeout,
      clock: clock
    )
  }
}
