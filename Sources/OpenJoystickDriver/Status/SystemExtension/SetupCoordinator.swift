import Foundation
import SystemExtensions

enum SystemExtensionSetupState: Sendable, Equatable {
  case checking
  case missingEmbedded
  case needsActivation
  case replacementNeeded
  case awaitingApproval
  case active
  case failed
  case invalid
}

enum SystemExtensionSetupRequestResult: Sendable, Equatable {
  case active
  case awaitingApproval
  case failed
  case cancelled
  case timedOut
}

protocol SystemExtensionSetupClient: Sendable {
  func inspect() -> ExtensionStatus
  func requestActivation() async -> SystemExtensionSetupRequestResult
}

final class DefaultSystemExtensionSetupClient: Sendable, SystemExtensionSetupClient {
  func inspect() -> ExtensionStatus { ExtensionProbe.currentStatus() }

  func requestActivation() async -> SystemExtensionSetupRequestResult {
    let requestState = SystemExtensionRequestState()
    return await withTaskCancellationHandler(operation: {
      await withCheckedContinuation { continuation in
        guard !Task.isCancelled else {
          continuation.resume(returning: SystemExtensionSetupRequestResult.cancelled)
          return
        }
        let submission = SystemExtensionSubmission(mode: .activation) {
          continuation.resume(returning: $0)
        }
        guard requestState.start(submission) else {
          continuation.resume(returning: SystemExtensionSetupRequestResult.cancelled)
          return
        }
        let timeout = DispatchWorkItem { [weak submission] in submission?.timeout() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
      }
    }, onCancel: {
      requestState.cancel()
    })
  }
}

@MainActor final class SystemExtensionSetupCoordinator {
  private let client: any SystemExtensionSetupClient
  private var automaticAttempted = false
  private var requestInFlight = false

  private(set) var state: SystemExtensionSetupState = .checking
  private(set) var status: ExtensionStatus = .unavailable

  init(client: any SystemExtensionSetupClient = DefaultSystemExtensionSetupClient()) {
    self.client = client
  }

  func launch() async { await reconcile(trigger: .launch) }
  func foreground() async { await reconcile(trigger: .foreground) }
  func refresh() async { await reconcile(trigger: .refresh) }
  func repair() async { await reconcile(trigger: .repair) }

  private enum Trigger { case launch, foreground, refresh, repair }

  private func reconcile(trigger: Trigger) async {
    let previousState = state
    status = client.inspect()
    state = Self.state(for: status)
    if (previousState == .awaitingApproval || previousState == .failed)
      && (state == .needsActivation || state == .replacementNeeded)
      && trigger != .repair
    {
      state = previousState == .awaitingApproval ? .awaitingApproval : .failed
    }
    guard state == .needsActivation || state == .replacementNeeded else { return }
    guard trigger == .repair || !automaticAttempted else { return }
    guard !requestInFlight else { return }
    automaticAttempted = true
    requestInFlight = true
    defer { requestInFlight = false }
    switch await client.requestActivation() {
    case .active: state = .active
    case .awaitingApproval: state = .awaitingApproval
    case .failed: state = .failed
    case .cancelled: state = .failed
    case .timedOut: state = .failed
    }
  }

  private static func state(for status: ExtensionStatus) -> SystemExtensionSetupState {
    guard status.bundle == .present else {
      return status.bundle == .missing ? .missingEmbedded : .invalid
    }
    switch status.registration {
    case .active:
      guard let embedded = status.embedded, let installed = status.installed else {
        return .failed
      }
      return embedded == installed ? .active : .replacementNeeded
    case .inactive, .absent: return .needsActivation
    case .unavailable: return .failed
    }
  }
}
