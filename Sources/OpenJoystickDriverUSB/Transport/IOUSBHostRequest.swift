import Foundation
import IOKit
import IOUSBHost
import OpenJoystickDriverKit

/// Awaits one IOUSBHost request that reports its end through a completion handler.
///
/// An IOUSBHost enqueue method calls its handler only when it returns `YES`; when the enqueue
/// fails, it returns `NO` with an error and the handler never runs. Swift's `async` form of these
/// methods then leaves its continuation unresumed, the runtime reports
/// `_createCheckedThrowingContinuation(_:) leaked its continuation`, and the awaiting task stays
/// suspended forever. This helper resumes once with whichever comes first: the handler's outcome
/// or the enqueue error.
enum IOUSBHostRequest {
  /// The completion handler of an enqueue: the request's status and its transferred byte count.
  typealias Completion = @Sendable (IOReturn, Int) -> Void

  /// Calls `enqueue` with a completion handler and returns the status and byte count it reports.
  ///
  /// - Parameter enqueue: Starts the request and passes the handler to IOUSBHost.
  /// - Returns: The status and the byte count of the completed request.
  /// - Throws: The error `enqueue` throws when the request does not start.
  static func run(
    _ enqueue: (@escaping Completion) throws -> Void
  ) async throws -> (IOReturn, Int) {
    try await withCheckedThrowingContinuation { continuation in
      let waiter = Locked<CheckedContinuation<(IOReturn, Int), any Error>?>(continuation)
      let finish: @Sendable (Result<(IOReturn, Int), any Error>) -> Void = { result in
        let taken = waiter.withLock { waiter in
          defer { waiter = nil }
          return waiter
        }
        taken?.resume(with: result)
      }
      do {
        try enqueue { status, count in finish(.success((status, count))) }
      } catch {
        finish(.failure(error))
      }
    }
  }
}

extension IOUSBHostObject {
  /// Sends `request` on the default control endpoint and returns its status and byte count.
  ///
  /// - Throws: The error of an enqueue that does not start.
  func completedDeviceRequest(
    _ request: IOUSBDeviceRequest,
    data: NSMutableData?,
    completionTimeout: TimeInterval
  ) async throws -> (IOReturn, Int) {
    try await IOUSBHostRequest.run { completion in
      try __enqueue(
        request,
        data: data,
        completionTimeout: completionTimeout,
        completionHandler: completion
      )
    }
  }
}

extension IOUSBHostPipe {
  /// Runs one transfer of `data` on the pipe and returns its status and byte count.
  ///
  /// - Throws: The error of an enqueue that does not start.
  func completedIORequest(
    with data: NSMutableData?,
    completionTimeout: TimeInterval
  ) async throws -> (IOReturn, Int) {
    try await IOUSBHostRequest.run { completion in
      try enqueueIORequest(
        with: data,
        completionTimeout: completionTimeout,
        completionHandler: completion
      )
    }
  }
}
