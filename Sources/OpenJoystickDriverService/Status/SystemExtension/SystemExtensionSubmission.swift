import Foundation
import OpenJoystickDriverKit
import SystemExtensions

private let localization = Localization()

final class SystemExtensionSubmissionCompletionGate: Sendable {
  private let finished = Locked(false)

  func accept() -> Bool {
    finished.withLock { finished in
      guard !finished else { return false }
      finished = true
      return true
    }
  }
}

protocol SystemExtensionSubmissionControlling: AnyObject, Sendable {
  func start()
  func cancel()
}

final class SystemExtensionRequestState: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  private var submission: (any SystemExtensionSubmissionControlling)?

  func start(_ submission: any SystemExtensionSubmissionControlling) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !cancelled else { return false }
    self.submission = submission
    submission.start()
    return true
  }

  func cancel() {
    lock.lock()
    cancelled = true
    let submission = self.submission
    lock.unlock()
    submission?.cancel()
  }
}

package final class SystemExtensionSubmission: NSObject, OSSystemExtensionRequestDelegate,
  SystemExtensionSubmissionControlling, @unchecked Sendable
{
  package enum Mode {
    case activation
    case deactivation
  }

  package enum Result {
    case completed(String)
    case requiresApproval
    case timedOut
    case failed(String)
  }

  private let mode: Mode
  private let resultLock = NSLock()
  private var result: Result?

  private let completion: ((SystemExtensionSetupRequestResult) -> Void)?
  private let completionGate = SystemExtensionSubmissionCompletionGate()

  package init(mode: Mode, completion: ((SystemExtensionSetupRequestResult) -> Void)? = nil) {
    self.mode = mode
    self.completion = completion
  }

  package func start() {
    let request: OSSystemExtensionRequest
    switch mode {
    case .activation:
      request = OSSystemExtensionRequest.activationRequest(
        forExtensionWithIdentifier: ExtensionProbe.bundleIdentifier,
        queue: .main
      )
    case .deactivation:
      request = OSSystemExtensionRequest.deactivationRequest(
        forExtensionWithIdentifier: ExtensionProbe.bundleIdentifier,
        queue: .main
      )
    }
    request.delegate = self
    OSSystemExtensionManager.shared.submitRequest(request)
  }

  package func wait(timeout seconds: TimeInterval) -> Result {
    let deadline = Date().addingTimeInterval(seconds)
    while currentResult == nil && Date() < deadline {
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    if currentResult == nil { timeout() }
    return currentResult ?? .timedOut
  }

  private var currentResult: Result? {
    resultLock.lock()
    defer { resultLock.unlock() }
    return result
  }

  package func request(
    _ request: OSSystemExtensionRequest,
    didFinishWithResult result: OSSystemExtensionRequest.Result
  ) {
    guard completionGate.accept() else { return }
    setResult(
      .completed(
        localization.formatted(
          "cli.extension.completed",
          arguments: [String(result.rawValue)]
        )
      )
    )
    finish(mode == .activation ? .active : .inactive)
  }

  package func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
    guard completionGate.accept() else { return }
    let nsError = error as NSError
    setResult(
      .failed(
        localization.formatted(
          "cli.extension.failed",
          arguments: [nsError.domain, nsError.code, nsError.localizedDescription]
        )
      )
    )
    finish(.failed)
  }

  package func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
    guard completionGate.accept() else { return }
    setResult(.requiresApproval)
    finish(.awaitingApproval)
  }

  package func request(
    _ request: OSSystemExtensionRequest,
    actionForReplacingExtension existing: OSSystemExtensionProperties,
    withExtension ext: OSSystemExtensionProperties
  ) -> OSSystemExtensionRequest.ReplacementAction {
    let message = localization.formatted(
      "cli.extension.replacing",
      arguments: [existing.bundleIdentifier, existing.bundleVersion, ext.bundleVersion]
    )
    FileHandle.standardError.write(Data((message + "\n").utf8))
    return .replace
  }

  private func finish(_ result: SystemExtensionSetupRequestResult) { completion?(result) }

  private func setResult(_ result: Result) {
    resultLock.lock()
    self.result = result
    resultLock.unlock()
  }

  func timeout() {
    guard completionGate.accept() else { return }
    setResult(.timedOut)
    completion?(.timedOut)
  }

  func cancel() {
    guard completionGate.accept() else { return }
    setResult(
      .failed(
        localization.string(
          "cli.extension.cancelled"
        )
      )
    )
    completion?(.cancelled)
  }

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
