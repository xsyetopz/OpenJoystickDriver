import Foundation
import OpenJoystickDriverKit

/// The mutable state of an ``AutomaticUserSpaceOutputDispatcher``, behind one lock.
///
/// Each operation is one critical section, so a caller that needs two reads or updates to agree
/// takes them through one operation.
/// - Note: `@unchecked Sendable` because `stateLock` guards every mutable property.
final class AutomaticDispatcherLedger: @unchecked Sendable {
  /// Guards the mutable state below.
  private let stateLock = NSLock()
  /// Whether all virtual output is paused.
  private var suppressedOutput = false
  /// Whether remapping output is paused on the backends.
  private var remappingSuppressedOutput = false
  /// The coordinator's publication state at the last synchronization, for the status.
  private var publication = AutomaticPublicationSnapshot()
  /// The coordinator revision `publication` reflects; nil before the first synchronization.
  private var publicationRevision: UInt64?
  /// Each controller's send times, kept here because every delivered report moves them.
  private var sendTimings: [LogicalControllerID: AutomaticSendTimings] = [:]
  /// The pausing value the coordinator last applied; nil before the first.
  private var appliedSuppression: Bool?
  /// The shortest time between two announcements that only move the send timings, so status
  /// observers see current timings without refreshing for every input report.
  private let timingAnnouncementIntervalNanoseconds: UInt64
  /// When the last change was announced, in uptime nanoseconds; nil before the first.
  private var lastAnnouncementNanoseconds: UInt64?
  /// Per-controller descriptions whose declared controls are fixed for the controller's binding.
  private var descriptionCache: [LogicalControllerID: ApplicationServiceDeviceDescription] = [:]
  /// Bumped by ``forget(_:)`` so a description lookup in flight at that point cannot re-insert a
  /// cache entry for a controller that already stopped.
  private var descriptionCacheGeneration: [LogicalControllerID: UInt64] = [:]
  /// Controllers whose declared controls no profile can represent, surfaced through the status.
  private var unavailableControllers: Set<LogicalControllerID> = []
  /// Each controller's selected profile and how it was selected.
  ///
  /// Selection runs once per physical session, and only a successful retarget changes it, so
  /// delivery never reselects.
  private var selections: [LogicalControllerID: VirtualHIDProfileSelector.Selection] = [:]
  /// The persona identity each controller's backends publish.
  ///
  /// It changes through retargeting, which a change to the persona files triggers, and the next
  /// session reads it again.
  private var identities: [LogicalControllerID: VirtualPersona.Identity] = [:]

  /// Creates an empty ledger that announces a change of the send timings alone at most once per
  /// `timingAnnouncementIntervalNanoseconds`.
  init(timingAnnouncementIntervalNanoseconds: UInt64) {
    self.timingAnnouncementIntervalNanoseconds = timingAnnouncementIntervalNanoseconds
  }

  // MARK: Suppression

  /// Whether all virtual output is paused.
  var suppressOutput: Bool {
    get { stateLock.withLock { suppressedOutput } }
    set { stateLock.withLock { suppressedOutput = newValue } }
  }

  /// Records whether remapping output is paused.
  func setRemappingSuppressed(_ suppressed: Bool) {
    stateLock.withLock { remappingSuppressedOutput = suppressed }
  }

  /// Whether remapping output is paused.
  var remappingSuppressed: Bool { stateLock.withLock { remappingSuppressedOutput } }

  /// Reads the pausing value and records it as the one the coordinator applied.
  func takeSuppressionToApply() -> Bool {
    let value = suppressOutput
    stateLock.withLock { appliedSuppression = value }
    return value
  }

  /// Whether the pausing value differs from the one the coordinator last applied.
  var suppressionNeedsApplying: Bool {
    stateLock.withLock { appliedSuppression != suppressedOutput }
  }

  // MARK: Status

  /// The targets and publication state of the backends, as a status line.
  var status: VirtualOutputBackendStatus {
    stateLock.withLock {
      let targets = Set(publication.targets.values.map(\.rawValue)).sorted()
      let suffix = targets.isEmpty ? "" : ", targets: \(targets.joined(separator: "; "))"
      let lines = publication.diagnosticLines(timings: sendTimings)
      let diagnostics = lines.isEmpty ? "" : ", publication: \(lines.joined(separator: "; "))"
      let unavailable =
        unavailableControllers.isEmpty ? "" : ", unavailable: \(unavailableControllers.count)"
      return .backend("automatic\(suffix)\(diagnostics)\(unavailable)")
    }
  }

  /// The publication state of `identifier`, with its send timings.
  func publicationStatus(
    for identifier: LogicalControllerID
  ) -> ApplicationServicePublicationStatus? {
    stateLock.withLock { publication.statuses[identifier]?.with(sendTimings[identifier]) }
  }

  /// Records that a send to the virtual gamepad of `identifier` was attempted at `now`.
  func recordSendAttempt(for identifier: LogicalControllerID, at now: UInt64) {
    stateLock.withLock {
      sendTimings[identifier, default: AutomaticSendTimings()].lastAttempted = now
    }
  }

  /// Records that a send to the virtual gamepad of `identifier` completed at `now`.
  func recordSendCompletion(for identifier: LogicalControllerID, at now: UInt64) {
    stateLock.withLock {
      sendTimings[identifier, default: AutomaticSendTimings()].lastCompleted = now
    }
  }

  /// Whether the stored snapshot is current for `knownRevision`, and whether a full interval has
  /// passed since the last announcement as of `now`.
  func diagnosticsGate(
    knownRevision: UInt64?,
    now: UInt64
  ) -> (current: Bool, intervalElapsed: Bool) {
    stateLock.withLock {
      let elapsed =
        lastAnnouncementNanoseconds.map { now &- $0 >= timingAnnouncementIntervalNanoseconds }
        ?? true
      return (knownRevision != nil && knownRevision == publicationRevision, elapsed)
    }
  }

  /// Stores `snapshot` read at `revision` and returns whether it differs from the stored one.
  func replacePublication(_ snapshot: AutomaticPublicationSnapshot, revision: UInt64) -> Bool {
    stateLock.withLock {
      defer {
        publication = snapshot
        publicationRevision = revision
      }
      return publication != snapshot
    }
  }

  /// Returns `shouldAnnounce` and, when it is true, records `now` as the announcement time.
  func claimAnnouncement(shouldAnnounce: Bool, now: UInt64) -> Bool {
    stateLock.withLock { () -> Bool in
      guard shouldAnnounce else { return false }
      lastAnnouncementNanoseconds = now
      return true
    }
  }

  // MARK: Descriptions

  /// The cached description of `identifier`.
  func cachedDescription(
    for identifier: LogicalControllerID
  ) -> ApplicationServiceDeviceDescription? {
    stateLock.withLock { descriptionCache[identifier] }
  }

  /// The generation of the description cache of `identifier`.
  func cacheGeneration(for identifier: LogicalControllerID) -> UInt64 {
    stateLock.withLock { descriptionCacheGeneration[identifier, default: 0] }
  }

  /// The cache generation of each of `identifiers`.
  func cacheGenerations(for identifiers: [LogicalControllerID]) -> [LogicalControllerID: UInt64] {
    stateLock.withLock {
      identifiers.reduce(into: [LogicalControllerID: UInt64]()) { generations, identifier in
        generations[identifier] = descriptionCacheGeneration[identifier, default: 0]
      }
    }
  }

  /// Caches `description` unless `identifier` stopped since `generation` was read.
  func storeDescription(
    _ description: ApplicationServiceDeviceDescription,
    for identifier: LogicalControllerID,
    generation: UInt64
  ) {
    stateLock.withLock {
      if descriptionCacheGeneration[identifier, default: 0] == generation {
        descriptionCache[identifier] = description
      }
    }
  }

  /// Clears the description cache.
  func removeAllDescriptions() {
    stateLock.withLock { descriptionCache.removeAll() }
  }

  // MARK: Selections

  /// The current selection of `identifier`.
  func selection(for identifier: LogicalControllerID) -> VirtualHIDProfileSelector.Selection? {
    stateLock.withLock { selections[identifier] }
  }

  /// How the current profile of a controller was selected.
  func selectionSource(
    for identifier: LogicalControllerID
  ) -> VirtualHIDProfileSelector.Selection.Source? {
    stateLock.withLock { selections[identifier]?.source }
  }

  /// The current selection of `identifier`, and whether no profile can represent it.
  func profileState(
    for identifier: LogicalControllerID
  ) -> (selection: VirtualHIDProfileSelector.Selection?, unavailable: Bool) {
    stateLock.withLock {
      (selections[identifier], unavailableControllers.contains(identifier))
    }
  }

  /// The persona identity `identifier` publishes.
  func identity(for identifier: LogicalControllerID) -> VirtualPersona.Identity? {
    stateLock.withLock { identities[identifier] }
  }

  /// The current selection and persona identity of `identifier`.
  func selectionAndIdentity(
    for identifier: LogicalControllerID
  ) -> (VirtualHIDProfileSelector.Selection?, VirtualPersona.Identity?) {
    stateLock.withLock { (selections[identifier], identities[identifier]) }
  }

  /// Sets the persona identity `identifier` publishes.
  func setIdentity(_ identity: VirtualPersona.Identity?, for identifier: LogicalControllerID) {
    stateLock.withLock { identities[identifier] = identity }
  }

  /// Records the selection of `identifier`, or records it as unavailable when `selection` is nil.
  ///
  /// A controller that stopped since `generation` was read keeps no entry.
  /// - Returns: Whether the profile, its source, or its availability changed.
  func commit(
    _ selection: VirtualHIDProfileSelector.Selection?,
    identity: VirtualPersona.Identity?,
    for identifier: LogicalControllerID,
    generation: UInt64
  ) -> Bool {
    stateLock.withLock { () -> Bool in
      guard descriptionCacheGeneration[identifier, default: 0] == generation else { return false }
      let previous = selections[identifier]
      let wasUnavailable = unavailableControllers.contains(identifier)
      identities[identifier] = identity
      if let selection {
        selections[identifier] = selection
        _ = unavailableControllers.remove(identifier)
      } else {
        _ = selections.removeValue(forKey: identifier)
        _ = unavailableControllers.insert(identifier)
      }
      return previous?.profileID != selection?.profileID || previous?.source != selection?.source
        || wasUnavailable != (selection == nil)
    }
  }

  /// Forgets the description, selection and identity of `identifier` and invalidates lookups in
  /// flight.
  func forget(_ identifier: LogicalControllerID) {
    stateLock.withLock {
      _ = descriptionCache.removeValue(forKey: identifier)
      descriptionCacheGeneration[identifier, default: 0] &+= 1
      _ = unavailableControllers.remove(identifier)
      _ = selections.removeValue(forKey: identifier)
      _ = identities.removeValue(forKey: identifier)
    }
  }
}
