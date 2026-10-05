import Foundation
import OpenJoystickDriverKit

@testable import OpenJoystickDriverService

/// A virtual controller that records what the registry does with it.
final class FakeFeedDevice: VirtualFeedDevice, @unchecked Sendable {
  let profile: VirtualHIDProfileID
  let output: UserSpaceOutputDispatcher.OutputCommandHandler
  let failsActivation: Bool
  var failsSending = false
  private let lock = NSLock()
  private var activatedValue: DeviceIdentifier?
  private var sentValue: [RemappingGamepadState] = []
  /// `ProcessInfo.systemUptime` of each send.
  private var sentTimesValue: [TimeInterval] = []
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
  var sentTimes: [TimeInterval] { lock.withLock { sentTimesValue } }
  var closeCount: Int { lock.withLock { closeCountValue } }

  func activate(controller identifier: DeviceIdentifier) throws {
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

  func close() { lock.withLock { closeCountValue += 1 } }

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

  var devices: [FakeFeedDevice] { lock.withLock { devicesValue } }

  func registry(idleTimeout: TimeInterval = 60) -> VirtualFeedRegistry {
    VirtualFeedRegistry(
      factory: { profile, output in
        self.lock.withLock {
          let device = FakeFeedDevice(
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
