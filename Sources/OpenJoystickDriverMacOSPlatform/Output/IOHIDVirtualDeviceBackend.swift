import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

/// The failure of a native report call, with the IOKit return code.
struct IOKitReportError: Error, Sendable {
  /// The IOKit return code.
  let code: IOReturn
}

/// One `IOHIDUserDevice`: created unpublished, then published by ``activate(hostReports:)``.
final class IOHIDVirtualDeviceBackend: VirtualDeviceBackend, @unchecked Sendable {
  /// The user device, until it closes.
  private var device: IOHIDUserDevice?
  /// The queue that delivers the device's events.
  private let queue: DispatchQueue
  /// The lock that guards `device` and `isClosed`.
  private let lock = NSLock()
  /// Whether the device is closed.
  private var isClosed = false
  /// Serial queue for blocking report calls; the sender's single worker already orders them.
  private let sendQueue = DispatchQueue(label: "com.openjoystickdriver.output.report")

  /// Longest wait for the cancel handler before teardown is reported as finished anyway.
  static let cancellationTimeoutNanoseconds: UInt64 = 2_000_000_000
  /// The state of the cancel handler.
  private let cancellation = Locked(Cancellation())

  /// Whether the cancel handler ran, and who waits for it.
  private struct Cancellation {
    /// Whether the cancel handler ran.
    var completed = false
    /// The tasks that wait for the cancel handler.
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  /// Wraps `device` and sets the cancel handler, which has to be set before activation.
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

  deinit { close() }

  /// Registers the get-report and set-report handlers, then activates the device.
  func activate(hostReports: UserSpaceHostReportHandler) {
    guard let device = lock.withLock({ isClosed ? nil : device }) else { return }
    IOHIDUserDeviceRegisterGetReportBlock(device) { type, reportID, report, reportLength in
      do {
        guard let identifier = UInt32(exactly: reportID) else {
          throw VirtualHostReportError.malformed
        }
        let bytes = try hostReports.getReport(
          type: try Self.reportType(type),
          reportID: identifier,
          maxSize: Int(reportLength.pointee)
        )
        for (index, byte) in bytes.enumerated() { report[index] = byte }
        reportLength.pointee = bytes.count
        return kIOReturnSuccess
      } catch {
        reportLength.pointee = 0
        return Self.ioKitError(error)
      }
    }
    IOHIDUserDeviceRegisterSetReportBlock(device) { type, reportID, report, reportLength in
      do {
        guard reportLength >= 0 else { throw VirtualHostReportError.malformed }
        let bytes = Array(UnsafeBufferPointer(start: report, count: Int(reportLength)))
        try hostReports.acknowledgeSetReport(
          type: try Self.reportType(type),
          reportID: reportID,
          bytes: bytes
        )
        return kIOReturnSuccess
      } catch { return Self.ioKitError(error) }
    }
    IOHIDUserDeviceSetDispatchQueue(device, queue)
    IOHIDUserDeviceActivate(device)
  }

  /// Resumes the tasks that wait for the cancel handler.
  private func finishCancellation() {
    let waiters = cancellation.withLock { state -> [CheckedContinuation<Void, Never>] in
      state.completed = true
      defer { state.waiters.removeAll() }
      return state.waiters
    }
    for waiter in waiters { waiter.resume() }
  }

  /// Suspends until the device's cancel handler ran, so the device has stopped publishing.
  func waitUntilClosed() async {
    // A device that never reports cancellation must not stall teardown forever. The limit runs
    // on a timer thread, so a starved cooperative pool cannot extend it.
    let cancelTimeout = DeadlineTimer.dispatch.schedule(Self.cancellationTimeoutNanoseconds) {
      [weak self] in self?.finishCancellation()
    }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let done = cancellation.withLock { state -> Bool in
        if state.completed { return true }
        state.waiters.append(continuation)
        return false
      }
      if done { continuation.resume() }
    }
    cancelTimeout()
  }

  /// Runs the blocking native report call off the cooperative pool.
  func send(_ report: [UInt8]) async throws {
    try await BlockingWork.run(on: sendQueue) { [self] in try sendNow(report) }
  }

  /// Sends `report` as an input report; blocks until IOKit accepts it.
  ///
  /// - Throws: ``CancellationError`` when the device is closed, and ``IOKitReportError`` when IOKit
  ///   refuses the report.
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

  /// Cancels the device; later sends fail.
  func close() {
    let device = lock.withLock { () -> IOHIDUserDevice? in
      guard !isClosed else { return nil }
      isClosed = true
      defer { self.device = nil }
      return self.device
    }
    if let device { IOHIDUserDeviceCancel(device) }
  }

  /// Returns the report type that `type` names.
  ///
  /// - Throws: ``VirtualHostReportError/unsupported`` for any other type.
  static func reportType(_ type: IOHIDReportType) throws -> VirtualHostReportType {
    switch type {
    case kIOHIDReportTypeInput: .input
    case kIOHIDReportTypeOutput: .output
    case kIOHIDReportTypeFeature: .feature
    default: throw VirtualHostReportError.unsupported
    }
  }

  /// Returns the IOKit return code for `error`.
  static func ioKitError(_ error: any Error) -> IOReturn {
    switch error {
    case VirtualHostReportError.unsupported: kIOReturnUnsupported
    case VirtualHostReportError.malformed: kIOReturnBadArgument
    case VirtualHostReportError.tooLarge: kIOReturnMessageTooLarge
    case VirtualHostReportError.closed: kIOReturnNotOpen
    case is CancellationError: kIOReturnAborted
    default: kIOReturnError
    }
  }
}
