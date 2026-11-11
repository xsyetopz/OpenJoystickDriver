import Foundation
import OpenJoystickDriverKit

/// Submits system-extension requests for the app's setup flow.
///
/// The composition root adapts it to the presentation layer's setup-client contract.
package final class DefaultSystemExtensionSetupClient: Sendable {
  /// Creates the client.
  package init() {}

  /// Returns the current state of the transport extension.
  package func inspect() -> ExtensionStatus { ExtensionProbe.currentStatus() }

  /// Submits an activation request and returns its outcome.
  package func requestActivation() async -> SystemExtensionSetupRequestResult {
    await request(.activation)
  }

  /// Submits a deactivation request and returns its outcome.
  package func requestDeactivation() async -> SystemExtensionSetupRequestResult {
    await request(.deactivation)
  }

  /// Submits a request of `mode` and returns its outcome.
  ///
  /// The request ends as timed out after 30 seconds, and as cancelled when the task is cancelled.
  private func request(
    _ mode: SystemExtensionSubmission.Mode
  ) async -> SystemExtensionSetupRequestResult {
    let requestState = SystemExtensionRequestState()
    return await withTaskCancellationHandler(
      operation: {
        await withCheckedContinuation { continuation in
          guard !Task.isCancelled else {
            continuation.resume(returning: SystemExtensionSetupRequestResult.cancelled)
            return
          }
          let submission = SystemExtensionSubmission(mode: mode) {
            continuation.resume(returning: $0)
          }
          guard requestState.start(submission) else {
            continuation.resume(returning: SystemExtensionSetupRequestResult.cancelled)
            return
          }
          let timeout = DispatchWorkItem { [weak submission] in submission?.timeout() }
          DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
        }
      },
      onCancel: { requestState.cancel() }
    )
  }
}
