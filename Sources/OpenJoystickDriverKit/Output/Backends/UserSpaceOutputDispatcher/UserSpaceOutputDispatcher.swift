import Foundation

/// Publishes one virtual gamepad for each connected physical controller.
///
/// The host supplies a ``VirtualHIDDevicePublisher`` that creates the native virtual HID device;
/// this class owns the per-controller report queues, the input state each device carries, and the
/// backend status. This path does not run in the USB DriverKit extension.
public final class UserSpaceOutputDispatcher: VirtualOutputDispatching,
  VirtualOutputControllerActivating, RemappingGamepadSink, RemappingGamepadOutputControlling,
  @unchecked Sendable
{

  /// The report format of every device.
  internal let format: any VirtualGamepadReportFormat
  /// The handler that receives the output commands that the host sends to a device.
  internal let onOutputCommand: OutputCommandHandler?
  /// Called after a controller's device is closed.
  internal let onControllerDidStop: (@Sendable (LogicalControllerID) async -> Void)?
  /// Whether the dispatcher is open.
  internal let lifecycle = LifecycleState()
  /// Creates the backend of one controller's device.
  internal let backendFactory:
    @Sendable (LogicalControllerID, VirtualDeviceIdentity) async throws -> any VirtualDeviceBackend
  /// Guards the registry state below.
  internal let registryLock = NSLock()
  /// The created devices by controller.
  internal var entries: [LogicalControllerID: Entry] = [:]
  /// The device creations in progress by controller.
  internal var creationTasks: [LogicalControllerID: Task<Entry, Error>] = [:]
  /// The serial numbers and LocationIDs of the controllers that have a device or a creation.
  internal var identityRegistry = VirtualIdentityRegistry()
  /// The pause between failed creation attempts by controller.
  internal var creationRetryPolicies: [LogicalControllerID: UserSpaceDeviceCreationRetryPolicy] =
    [:]
  /// A count by controller that rises when the controller stops or the dispatcher closes; a
  /// creation of an older count is discarded.
  internal var lifecycleGenerations: [LogicalControllerID: UInt64] = [:]
  /// The shutdown that `close()` started; later closes share it.
  internal var shutdownTask: Task<Void, Never>?
  /// Whether output is suppressed.
  internal var _suppressOutput = false
  /// Whether output from remapping is suppressed.
  internal var remappingOutputSuppressed = false
  /// Written only under `registryLock`; a change sets `statusChangePending`, and
  /// ``withRegistry(_:)`` announces it after the lock is released.
  internal var _status: VirtualOutputBackendStatus = .off {
    didSet { if oldValue != _status { statusChangePending = true } }
  }
  /// Whether ``_status`` changed since the last announcement.
  internal var statusChangePending = false
  /// The text of the latest rumble request from the host.
  internal var _lastRumbleStatus: String?

  /// Publishes each controller's device through `publisher` with the identity `profile` and the
  /// reports `format` describes.
  @preconcurrency
  package init(
    publisher: any VirtualHIDDevicePublisher,
    profile: VirtualDeviceProfile,
    format: any VirtualGamepadReportFormat,
    onOutputCommand: OutputCommandHandler? = nil,
    onControllerDidStop: (@Sendable (LogicalControllerID) async -> Void)? = nil
  ) {
    self.format = format
    self.onOutputCommand = onOutputCommand
    self.onControllerDidStop = onControllerDidStop
    self.backendFactory = { identifier, identity in
      try publisher.createDevice(
        for: identifier,
        identity: identity,
        profile: profile,
        format: format
      )
    }
  }

  /// Creates a dispatcher whose devices come from `testBackendFactory`.
  init(
    testBackendFactory:
      @escaping @Sendable (LogicalControllerID) async throws -> any VirtualDeviceBackend,
    format: any VirtualGamepadReportFormat = OJDGenericGamepadFormat(),
    onControllerDidStop: (@Sendable (LogicalControllerID) async -> Void)? = nil
  ) {
    self.format = format
    onOutputCommand = nil
    self.onControllerDidStop = onControllerDidStop
    self.backendFactory = { identifier, _ in try await testBackendFactory(identifier) }
  }

  deinit { beginClose() }
}

extension UserSpaceOutputDispatcher: ControllerLifecycleListener {
  /// Closes the device of `identifier` and cancels its creation, then calls the stop handler.
  public func controllerDidStop(_ identifier: LogicalControllerID) async {
    let resources = withRegistry { () -> (Entry?, Task<Entry, Error>?) in
      lifecycleGenerations[identifier, default: 0] &+= 1
      let creationTask = creationTasks.removeValue(forKey: identifier)
      creationRetryPolicies.removeValue(forKey: identifier)
      identityRegistry.release(identifier)
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
