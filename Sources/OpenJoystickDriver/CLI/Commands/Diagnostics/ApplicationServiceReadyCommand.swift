import Foundation
import OpenJoystickDriverKit

private enum ApplicationServiceReadyOutcome: Sendable {
  case ready
  case failed(String)
}

private final class ApplicationServiceReadyState: @unchecked Sendable {
  private let lock = NSLock()
  private var storedOutcome: ApplicationServiceReadyOutcome?

  var outcome: ApplicationServiceReadyOutcome? { lock.withLock { storedOutcome } }

  func record(_ outcome: ApplicationServiceReadyOutcome) {
    lock.withLock { storedOutcome = outcome }
  }
}

struct ApplicationServiceReadyCommand {
  func run() {
    let client = ApplicationServiceClient()
    client.connect(timeoutSeconds: applicationServiceCallTimeoutSeconds)
    let semaphore = DispatchSemaphore(value: 0)
    let state = ApplicationServiceReadyState()
    let probe = Task { @Sendable in
      do {
        _ = try await client.getStatus()
        state.record(.ready)
      } catch { state.record(.failed(error.localizedDescription)) }
      semaphore.signal()
    }
    let replied = semaphore.wait(timeout: .now() + applicationServiceCallTimeoutSeconds) == .success
    if !replied { probe.cancel() }
    client.disconnect()
    guard replied, let outcome = state.outcome else {
      CLIOutput.error("The authenticated application service is not ready.")
      exit(1)
    }
    switch outcome {
    case .ready: print("ready")
    case .failed(let message):
      CLIOutput.error(message)
      exit(1)
    }
  }
}
