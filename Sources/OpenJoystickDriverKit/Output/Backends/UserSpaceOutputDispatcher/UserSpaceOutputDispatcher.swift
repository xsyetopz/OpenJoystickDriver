import Darwin
import Foundation
import IOKit
import IOKit.hid
import Security

/// Publishes one virtual gamepad for each connected physical controller.
///
/// A ``VirtualHIDDevicePublisher``, when given and able, publishes each device; otherwise
/// IOKit `IOHIDUserDevice` does. This path does not run in the USB DriverKit extension.
public final class UserSpaceOutputDispatcher: VirtualOutputDispatching,
  VirtualOutputControllerActivating, RemappingGamepadSink, RemappingGamepadOutputControlling,
  @unchecked Sendable
{

  internal let profile: VirtualDeviceProfile
  internal let format: any VirtualGamepadReportFormat
  internal let onOutputCommand: OutputCommandHandler?
  internal let onControllerDidStop: (@Sendable (DeviceIdentifier) async -> Void)?
  internal let lifecycle = LifecycleState()
  internal let testBackendFactory:
    (@Sendable (DeviceIdentifier) async throws -> any VirtualDeviceBackend)?
  /// Tried before `IOHIDUserDevice` (or the test backend) for each new device.
  internal let devicePublisher: (any VirtualHIDDevicePublisher)?
  internal let registryLock = NSLock()
  internal var entries: [DeviceIdentifier: Entry] = [:]
  internal var creationTasks: [DeviceIdentifier: Task<Entry, Error>] = [:]
  internal var creationRetryPolicies: [DeviceIdentifier: UserSpaceDeviceCreationRetryPolicy] = [:]
  internal var lifecycleGenerations: [DeviceIdentifier: UInt64] = [:]
  internal var shutdownTask: Task<Void, Never>?
  internal var _suppressOutput = false
  internal var remappingOutputSuppressed = false
  internal var _status: VirtualOutputBackendStatus = .off
  internal var _lastRumbleStatus: String?

  static let requiredVirtualDeviceEntitlement = "com.apple.developer.hid.virtual.device"
  @preconcurrency
  public init(
    profile: VirtualDeviceProfile,
    format: any VirtualGamepadReportFormat,
    devicePublisher: (any VirtualHIDDevicePublisher)? = nil,
    onOutputCommand: OutputCommandHandler? = nil,
    onControllerDidStop: (@Sendable (DeviceIdentifier) async -> Void)? = nil
  ) throws {
    self.profile = profile
    self.format = format
    self.onOutputCommand = onOutputCommand
    self.onControllerDidStop = onControllerDidStop
    self.testBackendFactory = nil
    self.devicePublisher = devicePublisher

    guard Self.hasRequiredVirtualDeviceEntitlement else {
      throw CreationError.missingEntitlement(Self.requiredVirtualDeviceEntitlement)
    }
  }

  init(
    testBackendFactory:
      @escaping @Sendable (DeviceIdentifier) async throws -> any VirtualDeviceBackend,
    devicePublisher: (any VirtualHIDDevicePublisher)? = nil,
    format: any VirtualGamepadReportFormat = OJDGenericGamepadFormat(),
    onOutputCommand: OutputCommandHandler? = nil,
    onControllerDidStop: (@Sendable (DeviceIdentifier) async -> Void)? = nil
  ) {
    profile = .openJoystickDriverGenericHID
    self.format = format
    self.onOutputCommand = onOutputCommand
    self.onControllerDidStop = onControllerDidStop
    self.testBackendFactory = testBackendFactory
    self.devicePublisher = devicePublisher
  }

  deinit { beginClose() }
}

extension UserSpaceOutputDispatcher: ControllerLifecycleListener {
  public func controllerDidStop(_ identifier: DeviceIdentifier) async {
    let resources = registryLock.withLock { () -> (Entry?, Task<Entry, Error>?) in
      lifecycleGenerations[identifier, default: 0] &+= 1
      let creationTask = creationTasks.removeValue(forKey: identifier)
      creationRetryPolicies.removeValue(forKey: identifier)
      let removed = entries.removeValue(forKey: identifier)
      recomputeStatusLocked()
      return (removed, creationTask)
    }
    await resources.0?.close()
    resources.1?.cancel()
    if let creationTask = resources.1, let entry = try? await creationTask.value {
      await entry.close()
    }
    await onControllerDidStop?(identifier)
  }
}
