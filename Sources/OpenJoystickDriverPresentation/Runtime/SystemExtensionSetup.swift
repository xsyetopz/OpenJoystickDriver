import Foundation
package import OpenJoystickDriverKit

/// Where the Xbox USB driver extension is.
enum SystemExtensionSetupState: Sendable, Equatable {
  /// The state is being read.
  case checking
  /// The app bundle holds no extension.
  case missingEmbedded
  /// The extension bundle in the app is invalid.
  case invalid
  /// macOS did not report the registration; the value is the reason.
  case unavailable(String)
  /// The extension is not active.
  case needsActivation
  /// The installed extension differs from the embedded one, or its version is unknown.
  case replacementNeeded
  /// A request is with macOS.
  case running
  /// macOS waits for the user to approve the extension.
  case needsApproval
  /// The request was cancelled.
  case cancelled
  /// macOS did not answer the request in time.
  case timedOut
  /// The request failed with this `NSError`.
  case failed(SystemExtensionRequestFailure)
  /// The installed extension is active and matches the embedded one.
  case active
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

/// Works out the state of the driver extension and requests its activation and deactivation.
///
/// Only ``repair()`` and ``uninstall()`` send a request to macOS; a read never does.
@MainActor
package final class SystemExtensionSetupCoordinator {
  /// Inspects, activates and deactivates the extension.
  private let client: any SystemExtensionSetupClient

  /// Where the extension is.
  private(set) var state: SystemExtensionSetupState = .checking
  /// The status that macOS reports for the extension.
  private(set) var status: ExtensionStatus = .unavailable

  /// Creates the coordinator on a client.
  package init(client: any SystemExtensionSetupClient) { self.client = client }

  /// Reads the state at launch.
  func launch() { inspect() }
  /// Reads the state when the app comes to the front.
  func foreground() { inspect() }
  /// Reads the state again.
  func refresh() { inspect() }

  /// Asks macOS to activate or replace the extension, for the user's click.
  ///
  /// A click while a request runs, or in a state that cannot send a request, changes nothing: the
  /// banner shows no enabled button there.
  func repair() async {
    inspect()
    guard state.canRequest || state.holdsRequestOutcome else { return }
    state = .running
    switch await client.requestActivation() {
    case .active: state = .active
    case .inactive: state = .needsActivation
    case .awaitingApproval: state = .needsApproval
    case .failed(let failure): state = .failed(failure)
    case .cancelled: state = .cancelled
    case .timedOut: state = .timedOut
    }
  }

  /// Deactivates the extension.
  ///
  /// The state becomes needs activation, or the outcome of a request that did not deactivate.
  func uninstall() async {
    guard state != .running else { return }
    state = .running
    switch await client.requestDeactivation() {
    case .inactive: state = .needsActivation
    case .active: state = .active
    case .awaitingApproval: state = .needsApproval
    case .failed(let failure): state = .failed(failure)
    case .cancelled: state = .cancelled
    case .timedOut: state = .timedOut
    }
  }

  // A request outcome that is still true holds over a computed state that asks for a request, so
  // the banner keeps saying what happened.
  private func inspect() {
    status = client.inspect()
    guard state != .running else { return }
    let inspected = Self.state(for: status)
    state = state.holdsRequestOutcome && inspected.canRequest ? state : inspected
  }

  /// Returns the setup state of an extension status.
  private static func state(for status: ExtensionStatus) -> SystemExtensionSetupState {
    guard status.bundle == .present else {
      return status.bundle == .missing ? .missingEmbedded : .invalid
    }
    switch status.registration {
    case .active:
      guard let embedded = status.embedded, let installed = status.installed else {
        return .replacementNeeded
      }
      return embedded == installed ? .active : .replacementNeeded
    case .inactive, .absent: return .needsActivation
    case .unavailable(let reason): return .unavailable(reason)
    }
  }
}

extension SystemExtensionSetupState {
  /// Whether a click can send an activation request from this inspected state.
  fileprivate var canRequest: Bool { self == .needsActivation || self == .replacementNeeded }

  /// Whether this is the outcome of a request that ended without activating.
  fileprivate var holdsRequestOutcome: Bool {
    switch self {
    case .needsApproval, .cancelled, .timedOut, .failed: true
    default: false
    }
  }
}
