import Foundation
import OpenJoystickDriverKit
import SystemExtensions

private let ojdSystemExtensionID = ExtensionProbe.bundleIdentifier

struct SystemExtensionCommand {
  func run(arguments: [String]) {
    let subcommand = arguments.first ?? "status"
    switch subcommand {
    case "status": printStatus()
    case "enable": submitActivation()
    case "disable": submitDeactivation()
    case "--help", "-h", "help": printHelp()
    default:
      CLIOutput.error("Unknown extension command: \(subcommand)")
      printHelp()
      exit(1)
    }
  }

  private func printHelp() {
    print(
      """
      Usage: OpenJoystickDriver --headless extension <status|enable|disable>

      Commands:
        status     Show registered OpenJoystickDriver system extensions
        enable     Submit DriverKit system extension activation request
        disable    Submit DriverKit system extension deactivation request
      """
    )
  }

  private func printStatus() {
    let status = ExtensionProbe.currentStatus()
    switch status.bundle {
    case .present: print("Embedded DriverKit extension: present")
    case .missing: print("Embedded DriverKit extension: missing")
    case .invalid(let actualIdentifier):
      print("Embedded DriverKit extension: invalid (\(actualIdentifier))")
    }

    switch status.registration {
    case .active(let record):
      print("OS registration: active")
      print(record)
    case .inactive(let record):
      print("OS registration: registered but inactive")
      print(record)
    case .absent: print("OS registration: absent")
    case .unavailable(let reason):
      CLIOutput.diagnostic("OS registration: unavailable")
      CLIOutput.error(reason)
      exit(1)
    }
  }

  private func submitActivation() {
    requireApplicationsBundleOrExit()
    requireValidBundleSignatureOrExit(action: "Install system extension")
    guard bundleContainsSystemExtension() else {
      CLIOutput.error("App bundle does not contain \(ojdSystemExtensionID).dext")
      CLIOutput.diagnostic("Fix: run ./scripts/ojd rebuild dev, then retry from /Applications.")
      exit(1)
    }
    submit(.activation)
  }

  private func submitDeactivation() {
    requireApplicationsBundleOrExit()
    requireValidBundleSignatureOrExit(action: "Uninstall system extension")
    submit(.deactivation)
  }

  private func submit(_ mode: SystemExtensionSubmission.Mode) {
    let submission = SystemExtensionSubmission(mode: mode)
    submission.start()
    let result = submission.wait(timeout: 60)
    switch result {
    case .completed(let message): CLIOutput.diagnostic(message)
    case .requiresApproval:
      CLIOutput.diagnostic(
        "System extension request submitted and requires approval in System Settings."
      )
      CLIOutput.diagnostic(
        "Open System Settings > General > Login Items & Extensions > Driver Extensions."
      )
    case .timedOut:
      CLIOutput.error("System extension request did not finish within 60s.")
      CLIOutput.diagnostic(
        "Check System Settings for an approval prompt, then run extension status."
      )
      exit(2)
    case .failed(let error):
      CLIOutput.error(error)
      exit(1)
    }
  }

  private func bundleContainsSystemExtension() -> Bool {
    let bundlePath = Bundle.main.bundlePath
    let dextPath = bundlePath + "/Contents/Library/SystemExtensions/\(ojdSystemExtensionID).dext"
    return FileManager.default.fileExists(atPath: dextPath)
  }

}

final class SystemExtensionSubmissionCompletionGate: @unchecked Sendable {
  private let lock = NSLock()
  private var finished = false

  func accept() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !finished else { return false }
    finished = true
    return true
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

final class SystemExtensionSubmission: NSObject, OSSystemExtensionRequestDelegate,
  SystemExtensionSubmissionControlling, @unchecked Sendable
{
  enum Mode {
    case activation
    case deactivation
  }

  enum Result {
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

  init(mode: Mode, completion: ((SystemExtensionSetupRequestResult) -> Void)? = nil) {
    self.mode = mode
    self.completion = completion
  }

  func start() {
    let request: OSSystemExtensionRequest
    switch mode {
    case .activation:
      request = OSSystemExtensionRequest.activationRequest(
        forExtensionWithIdentifier: ojdSystemExtensionID,
        queue: .main
      )
    case .deactivation:
      request = OSSystemExtensionRequest.deactivationRequest(
        forExtensionWithIdentifier: ojdSystemExtensionID,
        queue: .main
      )
    }
    request.delegate = self
    OSSystemExtensionManager.shared.submitRequest(request)
  }

  func wait(timeout seconds: TimeInterval) -> Result {
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

  func request(
    _ request: OSSystemExtensionRequest,
    didFinishWithResult result: OSSystemExtensionRequest.Result
  ) {
    guard completionGate.accept() else { return }
    setResult(.completed("System extension request finished with result \(result.rawValue)."))
    finish(.active)
  }

  func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
    guard completionGate.accept() else { return }
    let nsError = error as NSError
    setResult(
      .failed(
        "System extension request failed: \(nsError.domain) "
          + "code=\(nsError.code) \(nsError.localizedDescription)"
      )
    )
    finish(.failed)
  }

  func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
    guard completionGate.accept() else { return }
    setResult(.requiresApproval)
    finish(.awaitingApproval)
  }

  func request(
    _ request: OSSystemExtensionRequest,
    actionForReplacingExtension existing: OSSystemExtensionProperties,
    withExtension ext: OSSystemExtensionProperties
  ) -> OSSystemExtensionRequest.ReplacementAction {
    CLIOutput.diagnostic(
      "Replacing \(existing.bundleIdentifier) v\(existing.bundleVersion) "
        + "with v\(ext.bundleVersion)."
    )
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
    setResult(.failed("System extension request cancelled."))
    completion?(.cancelled)
  }

  func completeForTesting(_ outcome: SystemExtensionSetupRequestResult) {
    guard completionGate.accept() else { return }
    switch outcome {
    case .active: setResult(.completed("test"))
    case .awaitingApproval: setResult(.requiresApproval)
    case .failed, .cancelled: setResult(.failed("test"))
    case .timedOut: setResult(.timedOut)
    }
    completion?(outcome)
  }
}
