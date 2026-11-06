import Foundation
import OpenJoystickDriverKit

/// Where the Xbox USB driver extension is.
enum SystemExtensionSetupState: Sendable, Equatable {
  /// The state is being read.
  case checking
  /// The app bundle holds no extension.
  case missingEmbedded
  /// The extension is not active.
  case needsActivation
  /// The installed extension differs from the embedded one.
  case replacementNeeded
  /// macOS waits for the user to approve the extension.
  case awaitingApproval
  /// The installed extension is active and matches the embedded one.
  case active
  /// Activating or deactivating the extension failed.
  case failed
  /// The extension bundle in the app is invalid.
  case invalid
}

/// Inspects, activates and deactivates the driver extension.
package protocol SystemExtensionSetupClient: Sendable {
  /// Returns the status of the extension.
  func inspect() -> ExtensionStatus
  /// Asks macOS to activate the extension and returns how the request ended.
  func requestActivation() async -> SystemExtensionSetupRequestResult
  /// Asks macOS to deactivate the extension and returns how the request ended.
  func requestDeactivation() async -> SystemExtensionSetupRequestResult
}

/// Keeps the state of the driver extension current and activates it when it needs activation or
/// replacement: automatically once, then only for ``repair()``.
@MainActor
package final class SystemExtensionSetupCoordinator {
  /// Inspects, activates and deactivates the extension.
  private let client: any SystemExtensionSetupClient
  /// Whether the automatic activation ran.
  private var automaticAttempted = false
  /// Whether an activation or deactivation request runs.
  private var requestInFlight = false

  /// Where the extension is.
  private(set) var state: SystemExtensionSetupState = .checking
  /// The status that macOS reports for the extension.
  private(set) var status: ExtensionStatus = .unavailable

  /// Creates the coordinator on a client.
  package init(client: any SystemExtensionSetupClient) { self.client = client }

  /// Reads the state at launch and activates the extension once when it needs it.
  func launch() async { await reconcile(trigger: .launch) }
  /// Reads the state when the app comes to the front.
  func foreground() async { await reconcile(trigger: .foreground) }
  /// Reads the state again.
  func refresh() async { await reconcile(trigger: .refresh) }
  /// Reads the state and activates the extension when it needs activation or replacement.
  func repair() async { await reconcile(trigger: .repair) }

  /// Deactivates the extension.
  ///
  /// The state becomes needs activation, or failed when the request fails.
  func uninstall() async {
    guard !requestInFlight else { return }
    requestInFlight = true
    defer { requestInFlight = false }
    switch await client.requestDeactivation() {
    case .inactive:
      automaticAttempted = true
      state = .needsActivation
    case .active, .awaitingApproval, .failed, .cancelled, .timedOut: state = .failed
    }
  }

  /// What asks for a read of the state.
  private enum Trigger {
    /// The app launched.
    case launch
    /// The app came to the front.
    case foreground
    /// A read of the state was requested.
    case refresh
    /// A repair was requested; it also activates after an awaiting approval or a failure.
    case repair
  }

  /// Reads the status of the extension and requests activation when the extension needs activation
  /// or replacement and the trigger allows it: once automatically, or at every repair.
  ///
  /// An awaiting approval or failed state holds until a repair.
  private func reconcile(trigger: Trigger) async {
    let previousState = state
    status = client.inspect()
    state = Self.state(for: status)
    if (previousState == .awaitingApproval || previousState == .failed)
      && (state == .needsActivation || state == .replacementNeeded) && trigger != .repair
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
    case .inactive: state = .failed
    case .awaitingApproval: state = .awaitingApproval
    case .failed: state = .failed
    case .cancelled: state = .failed
    case .timedOut: state = .failed
    }
  }

  /// Returns the setup state of an extension status.
  private static func state(for status: ExtensionStatus) -> SystemExtensionSetupState {
    guard status.bundle == .present else {
      return status.bundle == .missing ? .missingEmbedded : .invalid
    }
    switch status.registration {
    case .active:
      guard let embedded = status.embedded, let installed = status.installed else { return .failed }
      return embedded == installed ? .active : .replacementNeeded
    case .inactive, .absent: return .needsActivation
    case .unavailable: return .failed
    }
  }
}
