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
    case .present:
      print("Embedded DriverKit extension: present")
    case .missing:
      print("Embedded DriverKit extension: missing")
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
    case .absent:
      print("OS registration: absent")
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
    case .completed(let message):
      CLIOutput.diagnostic(message)
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
    let dextPath =
      bundlePath + "/Contents/Library/SystemExtensions/\(ojdSystemExtensionID).dext"
    return FileManager.default.fileExists(atPath: dextPath)
  }

}

private final class SystemExtensionSubmission: NSObject, OSSystemExtensionRequestDelegate {
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
  private var result: Result?

  init(mode: Mode) { self.mode = mode }

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
    while result == nil && Date() < deadline {
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    return result ?? .timedOut
  }

  func request(
    _ request: OSSystemExtensionRequest,
    didFinishWithResult result: OSSystemExtensionRequest.Result
  ) {
    self.result = .completed(
      "System extension request finished with result \(result.rawValue)."
    )
  }

  func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
    let nsError = error as NSError
    result = .failed(
      "System extension request failed: \(nsError.domain) " +
        "code=\(nsError.code) \(nsError.localizedDescription)"
    )
  }

  func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
    result = .requiresApproval
  }

  func request(
    _ request: OSSystemExtensionRequest,
    actionForReplacingExtension existing: OSSystemExtensionProperties,
    withExtension ext: OSSystemExtensionProperties
  ) -> OSSystemExtensionRequest.ReplacementAction {
    CLIOutput.diagnostic(
      "Replacing \(existing.bundleIdentifier) v\(existing.bundleVersion) " +
        "with v\(ext.bundleVersion)."
    )
    return .replace
  }
}
