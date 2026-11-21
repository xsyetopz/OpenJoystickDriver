import Foundation
import OpenJoystickDriverKit

/// The publication state of every controller of the automatic dispatcher, read in one call.
///
/// It carries no send timings: every delivered report moves them, so the dispatcher keeps them in
/// ``AutomaticSendTimings`` and adds them when the status is read. Two snapshots differ only in
/// what an observer acts on.
struct AutomaticPublicationSnapshot: Equatable, Sendable {
  /// The profile that each installed backend publishes.
  var targets: [LogicalControllerID: VirtualHIDProfileID] = [:]
  /// The publication diagnostic of each controller that has a target.
  var diagnostics: [AutomaticPublicationDiagnostic] = []
  /// The publication state of each controller that has a target.
  var statuses: [LogicalControllerID: ApplicationServicePublicationStatus] = [:]

  /// One sorted status line per controller that has a target, with each controller's timings.
  func diagnosticLines(
    timings: [LogicalControllerID: AutomaticSendTimings]
  ) -> [String] {
    diagnostics.map { $0.line(timings: timings[$0.controller]) }.sorted()
  }
}

/// When the virtual gamepad of one controller last received a send, in uptime nanoseconds.
struct AutomaticSendTimings: Equatable, Sendable {
  /// When a send was last attempted.
  var lastAttempted: UInt64?
  /// When a send last completed.
  var lastCompleted: UInt64?
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

  /// The status line of the controller with its send `timings`.
  func line(timings: AutomaticSendTimings?) -> String {
    let attempted = timings?.lastAttempted.map(String.init) ?? "none"
    let completed = timings?.lastCompleted.map(String.init) ?? "none"
    return "controller=\(controller), session=\(sessionGeneration), "
      + "publication=\(publicationGeneration), target=\(target.rawValue), "
      + "last-attempted=\(attempted), last-completed=\(completed), "
      + "\(result), recovery=\(recoveryState)"
  }

  /// The status line of the controller without send timings.
  var line: String { line(timings: nil) }
}

extension ApplicationServicePublicationStatus {
  /// The status with the send times of `timings`.
  func with(_ timings: AutomaticSendTimings?) -> Self {
    guard let timings else { return self }
    let attempted = timings.lastAttempted
    let completed = timings.lastCompleted
    // The factories keep `reason` and `failure` matched to `state`, so each case finds its value.
    if let failure {
      return .failed(
        failure,
        target: target,
        lastAttemptedNanoseconds: attempted,
        lastCompletedNanoseconds: completed
      )
    }
    if let reason {
      return .notPublished(
        reason,
        target: target,
        lastAttemptedNanoseconds: attempted,
        lastCompletedNanoseconds: completed
      )
    }
    return .published(
      target: target,
      lastAttemptedNanoseconds: attempted,
      lastCompletedNanoseconds: completed
    )
  }
}
