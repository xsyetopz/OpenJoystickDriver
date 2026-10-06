import Darwin
import Foundation
import IOKit
import IOKit.hid
import Security

extension UserSpaceOutputDispatcher {
  public typealias OutputCommandHandler =
    @Sendable (DeviceIdentifier, ControllerOutputCommand) -> Void

  public enum CreationError: Error, CustomStringConvertible, Sendable {
    case createFailed
    case inputMonitoringDenied
    case accessibilityDenied
    case missingEntitlement(String)

    public var description: String {
      switch self {
      case .createFailed: return "Failed to create virtual HID device"
      case .inputMonitoringDenied: return "Input Monitoring denied for IOKit virtual device"
      case .accessibilityDenied: return "Accessibility denied for IOKit virtual device"
      case .missingEntitlement(let entitlement): return "Missing entitlement: \(entitlement)"
      }
    }
  }

  protocol VirtualDeviceBackend: AnyObject, Sendable {
    func send(_ report: [UInt8]) async throws
    func close()
    /// Returns once the native device is gone. Backends without async teardown return at once.
    func waitUntilClosed() async
  }

  internal final class LifecycleState: Sendable {
    private let closed = Locked(false)

    var isOpen: Bool { closed.withLock { !$0 } }

    func close() -> Bool {
      closed.withLock { closed in
        guard !closed else { return false }
        closed = true
        return true
      }
    }
  }

  internal struct IOKitReportError: Error, Sendable { let code: IOReturn }

  internal final class IOHIDBackend: VirtualDeviceBackend, @unchecked Sendable {
    internal var device: IOHIDUserDevice?
    let queue: DispatchQueue
    internal let lock = NSLock()
    internal var isClosed = false
    /// Serial queue for blocking report calls; the sender's single worker already orders them.
    private let sendQueue = DispatchQueue(label: "com.openjoystickdriver.output.report")

    /// Longest wait for the cancel handler before teardown is reported as finished anyway.
    static let cancellationTimeoutNanoseconds: UInt64 = 2_000_000_000
    private let cancellation = Locked(Cancellation())

    private struct Cancellation {
      var completed = false
      var waiters: [CheckedContinuation<Void, Never>] = []
    }

    init(device: IOHIDUserDevice, queue: DispatchQueue) {
      self.device = device
      self.queue = queue
      // The cancel handler must be set before activation. It retains the device, as
      // IOHIDUserDevice.h requires, until the cancel has been fully delivered.
      IOHIDUserDeviceSetCancelHandler(device) { [weak self, device] in
        _ = device
        self?.finishCancellation()
      }
    }

    private func finishCancellation() {
      let waiters = cancellation.withLock { state -> [CheckedContinuation<Void, Never>] in
        state.completed = true
        defer { state.waiters.removeAll() }
        return state.waiters
      }
      waiters.forEach { $0.resume() }
    }

    /// Suspends until the device's cancel handler ran, so the device no longer publishes.
    func waitUntilClosed() async {
      await withTaskGroup(of: Void.self) { group in
        group.addTask { [self] in
          await withCheckedContinuation { continuation in
            let done = cancellation.withLock { state -> Bool in
              if state.completed { return true }
              state.waiters.append(continuation)
              return false
            }
            if done { continuation.resume() }
          }
        }
        group.addTask { [self] in
          // A device that never reports cancellation must not stall teardown forever.
          guard (try? await Task.sleep(nanoseconds: Self.cancellationTimeoutNanoseconds)) != nil
          else { return }
          finishCancellation()
        }
        await group.next()
        group.cancelAll()
      }
    }

    deinit { close() }

    /// Runs the blocking native report call off the cooperative pool.
    func send(_ report: [UInt8]) async throws {
      try await BlockingWork.run(on: sendQueue) { [self] in try sendNow(report) }
    }

    private func sendNow(_ report: [UInt8]) throws {
      guard let device = lock.withLock({ isClosed ? nil : device }) else {
        throw CancellationError()
      }
      // Interrupt IN for IOKit clients (`hid_read`). GetReport is a separate control path.
      let result = report.withUnsafeBytes { pointer -> IOReturn in
        guard let base = pointer.baseAddress else { return kIOReturnBadArgument }
        return IOHIDUserDeviceHandleReportWithTimeStamp(
          device,
          mach_absolute_time(),
          base.assumingMemoryBound(to: UInt8.self),
          pointer.count
        )
      }
      guard result == kIOReturnSuccess else { throw IOKitReportError(code: result) }
    }

    func close() {
      let device = lock.withLock { () -> IOHIDUserDevice? in
        guard !isClosed else { return nil }
        isClosed = true
        defer { self.device = nil }
        return self.device
      }
      if let device { IOHIDUserDeviceCancel(device) }
    }
  }

  public var suppressOutput: Bool {
    get { registryLock.withLock { _suppressOutput } }
    set { registryLock.withLock { _suppressOutput = newValue } }
  }

  public var status: VirtualOutputBackendStatus { registryLock.withLock { _status } }
  public func setOutputSuppressed(_ suppressed: Bool) async {
    let suppression: (entries: [Entry], shouldNeutralize: Bool) = registryLock.withLock {
      let changed = !_suppressOutput && suppressed
      _suppressOutput = suppressed
      return (Array(entries.values), changed)
    }
    for entry in suppression.entries {
      _ = try? await entry.sender.submit {
        suppression.shouldNeutralize && !entry.inputReportState.isRemapped
          ? [entry.inputReportState.reset()] + entry.inputReportState.claimChangedAuxiliaryReports()
          : []
      }.value()
    }
  }
  public func setRemappingOutputSuppressed(_ suppressed: Bool) async {
    let senders = registryLock.withLock {
      remappingOutputSuppressed = suppressed
      return entries.values.map(\.sender)
    }
    for sender in senders { _ = try? await sender.submit { [] }.value() }
  }

  public var lastRumbleStatus: String? { registryLock.withLock { _lastRumbleStatus } }
  static var hasRequiredVirtualDeviceEntitlement: Bool {
    hasEntitlement(requiredVirtualDeviceEntitlement)
  }

  public func close() async { await beginClose().value }

  /// Creates and neutrally activates one virtual device for each supplied controller.
  public func activate(for identifiers: [DeviceIdentifier]) async throws {
    guard lifecycle.isOpen else { throw CancellationError() }
    var seen = Set<DeviceIdentifier>()
    let identifiers = identifiers.filter { seen.insert($0).inserted }
    do {

      for identifier in identifiers {
        let entry = try await entry(for: identifier)
        guard lifecycle.isOpen else { throw CancellationError() }
        try await entry.sender.submit { [entry] in [entry.inputReportState.currentReport()] }
          .value()

      }
      registryLock.withLock { recomputeStatusLocked() }
    } catch {
      await close()
      throw error
    }
  }

  public func activate(controller identifier: DeviceIdentifier) async throws {
    guard lifecycle.isOpen else { throw CancellationError() }
    do {
      let entry = try await entry(for: identifier)
      guard lifecycle.isOpen else { throw CancellationError() }
      try await entry.sender.submit { [entry] in [entry.inputReportState.currentReport()] }.value()
      registryLock.withLock { recomputeStatusLocked() }
    } catch {
      await close()
      throw error
    }
  }

  @discardableResult
  func beginClose() -> Task<Void, Never> {
    registryLock.withLock {
      if let shutdownTask { return shutdownTask }
      _ = lifecycle.close()
      let resources = Array(entries.values)
      let identifiers = Set(entries.keys).union(creationTasks.keys)
      let tasks = Array(creationTasks.values)
      entries.removeAll()
      for identifier in identifiers { lifecycleGenerations[identifier, default: 0] &+= 1 }
      creationTasks.removeAll()
      creationRetryPolicies.removeAll()
      _status = .off
      tasks.forEach { $0.cancel() }
      let drains = resources.map { $0.beginClose() }
      let shutdown = Task {
        for drain in drains { await drain.value }
        for task in tasks { if let entry = try? await task.value { await entry.close() } }
      }
      shutdownTask = shutdown
      return shutdown
    }
  }

  public func dispatch(
    _ event: ControllerEvent,
    labels: ControllerButtonLabels,
    from identifier: DeviceIdentifier
  ) async {
    try? await deliver(input: event.state, labels: labels, from: identifier, remappedState: nil)
  }

  public func activateOutput(for identifier: DeviceIdentifier) async {
    try? await deliver(input: nil, labels: .standard, from: identifier, remappedState: nil)
  }

  public func activateOutputReportingFailure(for identifier: DeviceIdentifier) async throws {
    try await deliver(input: nil, labels: .standard, from: identifier, remappedState: nil)
  }

  public func dispatchReportingFailure(
    _ event: ControllerEvent,
    labels: ControllerButtonLabels,
    from identifier: DeviceIdentifier
  ) async throws {
    try await deliver(input: event.state, labels: labels, from: identifier, remappedState: nil)
  }

  public func send(_ state: RemappingGamepadState, for identifier: DeviceIdentifier) async throws {
    if state == .neutral, !lifecycle.isOpen {
      await close()
      return
    }
    try await deliver(input: nil, labels: .standard, from: identifier, remappedState: state)
  }

  internal func isOutputSuppressed(remapped: Bool) -> Bool {
    registryLock.withLock { remapped ? remappingOutputSuppressed : _suppressOutput }
  }
}

extension UserSpaceOutputDispatcher.VirtualDeviceBackend {
  func waitUntilClosed() async { await Task.yield() }
}
