import Foundation
import OpenJoystickDriverKit

/// The publication state of every controller of the automatic dispatcher, read in one call.
///
/// Every delivered report moves the send timings, so ``hasSameMeaning(as:)`` leaves them out:
/// a status change is announced for what an observer acts on, never for each report.
struct AutomaticPublicationSnapshot: Equatable, Sendable {
  /// The profile that each installed backend publishes.
  var targets: [LogicalControllerID: VirtualHIDProfileID] = [:]
  /// The publication diagnostic of each controller that has a target.
  var diagnostics: [AutomaticPublicationDiagnostic] = []
  /// The publication state of each controller that has a target.
  var statuses: [LogicalControllerID: ApplicationServicePublicationStatus] = [:]

  /// Whether `other` differs from this snapshot only in its send timings.
  func hasSameMeaning(as other: Self) -> Bool {
    targets == other.targets
      && diagnostics.map(\.withoutTimings) == other.diagnostics.map(\.withoutTimings)
      && statuses.count == other.statuses.count
      && statuses.allSatisfy { identifier, status in
        other.statuses[identifier].map(status.hasSameMeaning(as:)) ?? false
      }
  }

  /// One sorted status line per controller that has a target.
  var diagnosticLines: [String] { diagnostics.map(\.line).sorted() }
}

/// The publication diagnostic of one controller, formatted only when the status is read.
struct AutomaticPublicationDiagnostic: Equatable, Sendable {
  /// The controller.
  let controller: LogicalControllerID
  /// The physical session generation.
  let sessionGeneration: UInt64
  /// The publication generation.
  let publicationGeneration: UInt64
  /// The profile the controller publishes or tries to publish.
  let target: VirtualHIDProfileID
  /// `status=ended`, `failure=<text>`, or `status=<backend status>`.
  let result: String
  /// Where recovery stands.
  let recoveryState: String
  /// When a send was last attempted, in uptime nanoseconds.
  var lastAttempted: UInt64?
  /// When a send last completed, in uptime nanoseconds.
  var lastCompleted: UInt64?

  /// The diagnostic with no send timings.
  var withoutTimings: Self {
    var copy = self
    copy.lastAttempted = nil
    copy.lastCompleted = nil
    return copy
  }

  /// The status line of the controller.
  var line: String {
    let attempted = lastAttempted.map(String.init) ?? "none"
    let completed = lastCompleted.map(String.init) ?? "none"
    return "controller=\(controller), session=\(sessionGeneration), "
      + "publication=\(publicationGeneration), target=\(target.rawValue), "
      + "last-attempted=\(attempted), last-completed=\(completed), "
      + "\(result), recovery=\(recoveryState)"
  }
}

extension ApplicationServicePublicationStatus {
  /// Whether `other` differs from this status only in its send timings.
  func hasSameMeaning(as other: Self) -> Bool {
    state == other.state && reason == other.reason && failure == other.failure
      && target == other.target
  }
}
