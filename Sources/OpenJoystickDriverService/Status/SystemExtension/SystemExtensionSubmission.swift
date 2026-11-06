import Foundation
import OpenJoystickDriverKit
import SystemExtensions

/// The localized texts of the submission results.
private let localization = Localization()

/// A gate that lets exactly one outcome complete a submission.
final class SystemExtensionSubmissionCompletionGate: Sendable {
  /// Whether an outcome was accepted.
  private let finished = Locked(false)

  /// Returns true for the first call and false for every later one.
  func accept() -> Bool {
    finished.withLock { finished in
      guard !finished else { return false }
      finished = true
      return true
    }
  }
}

/// A submission that can be started and cancelled.
protocol SystemExtensionSubmissionControlling: AnyObject, Sendable {
  /// Submits the request.
  func start()
  /// Cancels the request.
  func cancel()
}

/// The state of a request that a task cancellation can reach.
final class SystemExtensionRequestState: @unchecked Sendable {
  /// The lock that guards the state.
  private let lock = NSLock()
  /// Whether the request was cancelled.
  private var cancelled = false
  /// The started submission.
  private var submission: (any SystemExtensionSubmissionControlling)?

  /// Starts `submission` and returns true, or returns false when the request was cancelled.
  func start(_ submission: any SystemExtensionSubmissionControlling) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !cancelled else { return false }
    self.submission = submission
    submission.start()
    return true
  }

  /// Marks the request as cancelled and cancels the started submission.
  func cancel() {
    lock.lock()
    cancelled = true
    let submission = self.submission
    lock.unlock()
    submission?.cancel()
  }
}

/// One activation or deactivation request of the transport extension, with its outcome.
package final class SystemExtensionSubmission: NSObject, OSSystemExtensionRequestDelegate,
  SystemExtensionSubmissionControlling, @unchecked Sendable
{
  /// The kind of request.
  package enum Mode {
    /// Activates the extension.
    case activation
    /// Deactivates the extension.
    case deactivation
  }

  /// The outcome of a request.
  package enum Result {
    /// The request finished, with the text that describes it.
    case completed(String)
    /// The request needs the user to approve it.
    case requiresApproval
    /// The request did not finish in time.
    case timedOut
    /// The request failed, with the text that describes the failure.
    case failed(String)
  }

  /// The kind of request.
  private let mode: Mode
  /// The lock that guards `result`.
  private let resultLock = NSLock()
  /// The outcome, once the request finished.
  private var result: Result?

  /// Receives the outcome of the request.
  private let completion: ((SystemExtensionSetupRequestResult) -> Void)?
  /// The gate that accepts only the first outcome.
  private let completionGate = SystemExtensionSubmissionCompletionGate()

  /// Creates a submission of `mode` that reports its outcome to `completion`.
  package init(mode: Mode, completion: ((SystemExtensionSetupRequestResult) -> Void)? = nil) {
    self.mode = mode
    self.completion = completion
  }

  /// Submits the request for the transport extension to the system.
  package func start() {
    let request: OSSystemExtensionRequest
    switch mode {
    case .activation:
      request = OSSystemExtensionRequest.activationRequest(
        forExtensionWithIdentifier: ExtensionProbe.extensionID,
        queue: .main
      )
    case .deactivation:
      request = OSSystemExtensionRequest.deactivationRequest(
        forExtensionWithIdentifier: ExtensionProbe.extensionID,
        queue: .main
      )
    }
    request.delegate = self
    OSSystemExtensionManager.shared.submitRequest(request)
  }

  /// Runs the run loop until the request has an outcome or `seconds` pass, and returns the outcome.
  ///
  /// A request that is still pending after `seconds` times out.
  package func wait(timeout seconds: TimeInterval) -> Result {
    let deadline = Date().addingTimeInterval(seconds)
    while currentResult == nil && Date() < deadline {
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    if currentResult == nil { timeout() }
    return currentResult ?? .timedOut
  }

  /// The outcome, or nil while the request is pending.
  private var currentResult: Result? {
    resultLock.lock()
    defer { resultLock.unlock() }
    return result
  }

  /// Records that the request finished, with the result code.
  package func request(
    _ request: OSSystemExtensionRequest,
    didFinishWithResult result: OSSystemExtensionRequest.Result
  ) {
    guard completionGate.accept() else { return }
    setResult(
      .completed(
        localization.formatted(
          "cli.transportExtension.group.completed",
          arguments: [String(result.rawValue)]
        )
      )
    )
    finish(mode == .activation ? .active : .inactive)
  }

  /// Records the failure of the request.
  package func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
    guard completionGate.accept() else { return }
    let nsError = error as NSError
    setResult(
      .failed(
        localization.formatted(
          "cli.transportExtension.group.failed",
          arguments: [nsError.domain, nsError.code, nsError.localizedDescription]
        )
      )
    )
    finish(.failed)
  }

  /// Records that the request needs the user's approval.
  package func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
    guard completionGate.accept() else { return }
    setResult(.requiresApproval)
    finish(.awaitingApproval)
  }

  /// Tells the system to replace the installed extension with the one this request submits.
  ///
  /// The replacement is reported on the standard error stream.
  package func request(
    _ request: OSSystemExtensionRequest,
    actionForReplacingExtension existing: OSSystemExtensionProperties,
    withExtension ext: OSSystemExtensionProperties
  ) -> OSSystemExtensionRequest.ReplacementAction {
    let message = localization.formatted(
      "cli.transportExtension.group.replacing",
      arguments: [existing.bundleIdentifier, existing.bundleVersion, ext.bundleVersion]
    )
    FileHandle.standardError.write(Data((message + "\n").utf8))
    return .replace
  }

  /// Reports `result` to the completion.
  private func finish(_ result: SystemExtensionSetupRequestResult) { completion?(result) }

  /// Stores `result` as the outcome.
  private func setResult(_ result: Result) {
    resultLock.lock()
    self.result = result
    resultLock.unlock()
  }

  /// Ends the request as timed out, unless it already has an outcome.
  func timeout() {
    guard completionGate.accept() else { return }
    setResult(.timedOut)
    completion?(.timedOut)
  }

  /// Ends the request as cancelled, unless it already has an outcome.
  func cancel() {
    guard completionGate.accept() else { return }
    setResult(
      .failed(
        localization.string(
          "cli.transportExtension.group.cancelled"
        )
      )
    )
    completion?(.cancelled)
  }

  /// Ends the request with `outcome`, for a test.
  func completeForTesting(_ outcome: SystemExtensionSetupRequestResult) {
    guard completionGate.accept() else { return }
    switch outcome {
    case .active, .inactive: setResult(.completed("test"))
    case .awaitingApproval: setResult(.requiresApproval)
    case .failed, .cancelled: setResult(.failed("test"))
    case .timedOut: setResult(.timedOut)
    }
    completion?(outcome)
  }
}
