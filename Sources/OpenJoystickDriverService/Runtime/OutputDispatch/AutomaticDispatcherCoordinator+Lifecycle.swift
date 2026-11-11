import Foundation
import OpenJoystickDriverKit

extension AutomaticDispatcherCoordinator {

  /// Applies the current suppression value, retiring every backend when it is on.
  ///
  /// Turning suppression off publishes again for each controller that has a session and a context.
  func synchronizeSuppression(_ currentValue: @Sendable () -> Bool) async {
    guard !closed else { return }
    let wasSuppressed = suppressed
    suppressed = currentValue()
    suppressionRevision &+= 1
    if suppressed {
      let identifiers = Array(entries.keys)
      var slots: [(LogicalControllerID, AutomaticBackendSlot)] = []
      for identifier in identifiers {
        guard let entry = entries[identifier] else { continue }
        entries[identifier]?.publicationGeneration &+= 1
        for pending in entry.tasks.values { pending.task.cancel() }
        entries[identifier]?.pending = nil
        guard let installed = entry.installed else { continue }
        entries[identifier]?.installed = nil
        entries[identifier]?.installedToken = nil
        entries[identifier]?.target = nil
        entries[identifier]?.retiring = installed
        slots.append((identifier, installed))
      }
      await withTaskGroup(of: (LogicalControllerID, Bool).self) { group in
        for (identifier, slot) in slots {
          group.addTask { (identifier, await slot.retireAndWait()) }
        }
        for await (identifier, retired) in group {
          guard let slot = slots.first(where: { $0.0 == identifier })?.1 else { continue }
          if retired {
            await retirementFinished(identifier: identifier, slot: slot)
          } else {
            Task { [weak self] in
              await slot.waitForCloseCompletion()
              await self?.retirementFinished(identifier: identifier, slot: slot)
            }
          }
        }
      }
      return
    }

    guard wasSuppressed else { return }
    let contexts = entries.compactMap {
      identifier,
      entry -> (LogicalControllerID, PublicationContext)? in
      guard entry.physicalSessionActive, entry.installed == nil, entry.retiring == nil,
        entry.pending == nil, let context = entry.context
      else { return nil }
      return (identifier, context)
    }
    for (identifier, context) in contexts {
      do {
        let lease = try await acquire(
          identifier,
          target: context.target,
          isEligible: context.isEligible,
          factory: context.factory
        )
        await lease?.release()
      } catch { continue }
    }
  }

  /// A retirement that timed out still completes its forced close; clear the slot then, so it
  /// cannot linger, and publish again if the controller was left without a backend.
  func clearRetirementOnceClosed(_ slot: AutomaticBackendSlot, controller: LogicalControllerID) {
    Task { [weak self] in
      await slot.waitForCloseCompletion()
      await self?.retirementFinished(identifier: controller, slot: slot)
    }
  }

  /// Clears the retiring slot and publishes again when the controller was left without a backend.
  private func retirementFinished(identifier: LogicalControllerID, slot: AutomaticBackendSlot) async
  {
    guard entries[identifier]?.retiring === slot else { return }
    entries[identifier]?.retiring = nil
    guard !closed, !suppressed, let entry = entries[identifier], entry.physicalSessionActive,
      entry.installed == nil, entry.pending == nil, let context = entry.context
    else { return }
    do {
      let lease = try await acquire(
        identifier,
        target: context.target,
        isEligible: context.isEligible,
        factory: context.factory
      )
      await lease?.release()
    } catch { return }
  }

  /// Returns the profile that each installed backend publishes.
  func installedTargets() -> [LogicalControllerID: VirtualHIDProfileID] {
    entries.reduce(into: [:]) { targets, element in
      guard element.value.installed != nil, let target = element.value.target else { return }
      targets[element.key] = target
    }
  }

  /// Records that a send to the virtual gamepad of `controller` was attempted.
  func recordPublicationAttempt(for controller: LogicalControllerID) {
    entries[controller]?.lastAttemptedSend = DispatchTime.now().uptimeNanoseconds
  }

  /// Records that a send for `controller` completed, which clears its failure and ends recovery.
  func recordPublicationCompletion(for controller: LogicalControllerID) {
    entries[controller]?.lastCompletedSend = DispatchTime.now().uptimeNanoseconds
    entries[controller]?.lastFailure = nil
    entries[controller]?.recoveryState = "idle"
  }

  /// Returns one sorted status line per controller that has a target.
  func publicationDiagnostics() -> [String] {
    entries.compactMap { identifier, entry in
      guard let target = entry.target ?? entry.context?.target else { return nil }
      let attempted = entry.lastAttemptedSend.map(String.init) ?? "none"
      let completed = entry.lastCompletedSend.map(String.init) ?? "none"
      // The entry outlives a stopped session so a later session gets newer generations.
      let result =
        !entry.physicalSessionActive
        ? "status=ended"
        : entry.lastFailure.map { "failure=\($0)" }
          ?? "status=\(entry.installed?.backend.status.wireValue ?? "none")"
      return "controller=\(identifier), session=\(entry.sessionGeneration), "
        + "publication=\(entry.publicationGeneration), target=\(target.rawValue), "
        + "last-attempted=\(attempted), last-completed=\(completed), "
        + "\(result), recovery=\(entry.recoveryState)"
    }.sorted()
  }

  /// The installed backend of `identifier`; nil when it publishes no virtual gamepad.
  func installedBackend(for identifier: LogicalControllerID) -> (any VirtualOutputDispatching)? {
    entries[identifier]?.installed?.backend
  }

  /// Each controller's publication state, for controllers that have a target profile.
  func publicationStatuses() -> [LogicalControllerID: ApplicationServicePublicationStatus] {
    entries.reduce(into: [:]) { statuses, element in
      let entry = element.value
      guard let target = entry.target ?? entry.context?.target else { return }
      let attempted = entry.lastAttemptedSend
      let completed = entry.lastCompletedSend
      statuses[element.key] =
        if entry.heldByAnotherClient {
          .notPublished(
            .heldByAnotherClient,
            target: target,
            lastAttemptedNanoseconds: attempted,
            lastCompletedNanoseconds: completed
          )
        } else if let failure = entry.lastFailure {
          .failed(
            failure,
            target: target,
            lastAttemptedNanoseconds: attempted,
            lastCompletedNanoseconds: completed
          )
        } else if entry.installed != nil {
          .published(
            target: target,
            lastAttemptedNanoseconds: attempted,
            lastCompletedNanoseconds: completed
          )
        } else {
          .notPublished(
            suppressed ? .suppressed : .noInputYet,
            target: target,
            lastAttemptedNanoseconds: attempted,
            lastCompletedNanoseconds: completed
          )
        }
    }
  }

  /// Applies the current remapping suppression value to every installed backend that supports it.
  func synchronizeRemappingSuppression(_ currentValue: @Sendable () -> Bool) async {
    guard !closed else { return }
    remappingSuppressed = currentValue()
    suppressionRevision &+= 1
    let slots = entries.values.compactMap(\.installed)
    for slot in slots {
      guard let lease = slot.acquire() else { continue }
      if let control = lease.backend as? any RemappingGamepadOutputControlling {
        repeat {
          let revision = suppressionRevision
          await control.setRemappingOutputSuppressed(remappingSuppressed)
          if closed || revision == suppressionRevision { break }
        } while true
      }
      await lease.release()
    }
  }

  /// Records whether another client holds the controller's input.
  ///
  /// Holding retires the live publication, whose virtual device could never move; the physical
  /// session stays, so the next activation or input after the release publishes again.
  func setHeldByAnotherClient(_ held: Bool, for controller: LogicalControllerID) async {
    guard !closed else { return }
    var entry = entries[controller] ?? Entry()
    guard entry.heldByAnotherClient != held else { return }
    entry.heldByAnotherClient = held
    guard held else {
      entries[controller] = entry
      return
    }
    entry.publicationGeneration &+= 1
    for pending in entry.tasks.values { pending.task.cancel() }
    entry.pending = nil
    let installed = entry.installed
    entry.installed = nil
    entry.installedToken = nil
    entry.target = nil
    if let installed { entry.retiring = installed }
    entries[controller] = entry
    guard let installed else { return }
    if await installed.retireAndWait() {
      await retirementFinished(identifier: controller, slot: installed)
    } else {
      Task { [weak self] in
        await installed.waitForCloseCompletion()
        await self?.retirementFinished(identifier: controller, slot: installed)
      }
    }
  }

  /// A failed publication is retired before an eligible replacement is considered.
  ///
  /// The physical session remains valid, so a later report can recover without a mode change.
  func recoverPublication(for controller: LogicalControllerID, failure: any Error) async {
    guard !closed, !suppressed, var entry = entries[controller], entry.physicalSessionActive,
      entry.recoveryState == "idle", entry.context != nil
    else { return }
    entry.publicationGeneration &+= 1
    entry.lastFailure = PublicationFailureText.text(for: failure)
    entry.recoveryState = "retiring"
    let old = entry.installed ?? entry.retiring
    entry.installed = nil
    entry.installedToken = nil
    entry.target = nil
    entry.retiring = old
    for pending in entry.tasks.values { pending.task.cancel() }
    entry.pending = nil
    entries[controller] = entry
    if let old, !(await old.retireAndWait()) {
      entries[controller]?.recoveryState = "waiting-for-retirement"
      // The forced close still completes; resume recovery then, so retirement is never abandoned.
      Task { [weak self] in
        await old.waitForCloseCompletion()
        await self?.resumeRecovery(controller, after: old, generation: entry.publicationGeneration)
      }
      return
    }
    beginRecoveryRetry(controller, generation: entry.publicationGeneration)
  }

  /// Starts the retry of `controller` once the retirement of `slot` has finished.
  private func resumeRecovery(
    _ controller: LogicalControllerID,
    after slot: AutomaticBackendSlot,
    generation: UInt64
  ) {
    guard entries[controller]?.retiring === slot,
      entries[controller]?.recoveryState == "waiting-for-retirement"
    else { return }
    beginRecoveryRetry(controller, generation: generation)
  }

  /// Gates the retry of `controller` for the recovery delay, unless `generation` is stale.
  private func beginRecoveryRetry(_ controller: LogicalControllerID, generation: UInt64) {
    guard entries[controller]?.publicationGeneration == generation else { return }
    entries[controller]?.retiring = nil
    let token = UUID()
    entries[controller]?.recoveryToken = token
    entries[controller]?.recoveryState = "retry-gated"
    scheduleRecoveryRetry(controller, token: token)
  }

  /// Tries to publish `controller` again; a failure records its text and schedules another retry.
  private func retryPublication(_ controller: LogicalControllerID, token: UUID) async {
    guard !closed, !suppressed, let entry = entries[controller], entry.physicalSessionActive,
      entry.recoveryToken == token, let context = entry.context
    else { return }
    entries[controller]?.recoveryState = "recovering"
    do {
      let lease = try await acquire(
        controller,
        target: context.target,
        isEligible: context.isEligible,
        factory: context.factory
      )
      await lease?.release()
      entries[controller]?.recoveryState = "idle"
      entries[controller]?.recoveryToken = nil
    } catch {
      entries[controller]?.lastFailure = PublicationFailureText.text(for: error)
      entries[controller]?.recoveryState = "retry-gated"
      scheduleRecoveryRetry(controller, token: token)
    }
  }

  /// Retries the publication of `token` after the recovery delay.
  private func scheduleRecoveryRetry(_ controller: LogicalControllerID, token: UUID) {
    Task { [weak self] in
      guard let self else { return }
      try? await Task.sleep(nanoseconds: self.recoveryDelayNanoseconds)
      await self.retryPublication(controller, token: token)
    }
  }

  /// Ends the physical session of `controller`, cancelling its work and retiring its backend.
  func stop(_ controller: LogicalControllerID) async {
    var entry = entries[controller] ?? Entry()
    entry.sessionGeneration &+= 1
    entry.publicationGeneration &+= 1
    entry.physicalSessionActive = false
    let installed = entry.installed ?? entry.retiring
    let tasks = entry.tasks.values.map(\.task)
    entry.installed = nil
    entry.target = nil
    entry.pending = nil
    entry.retiring = installed
    entries[controller] = entry
    for task in tasks { task.cancel() }
    let retired = await installed?.retireAndWait() ?? true
    for task in tasks { _ = await task.result }
    if retired, entries[controller]?.sessionGeneration == entry.sessionGeneration {
      entries[controller]?.retiring = nil
    } else if let installed, !retired {
      clearRetirementOnceClosed(installed, controller: controller)
    }
  }

  /// Closes the coordinator, retiring every installed backend; later callers wait for the first.
  func close() async {
    if closed {
      if !closeFinished { await withCheckedContinuation { closeWaiters.append($0) } }
      return
    }
    closed = true
    let slots = entries.values.compactMap(\.installed)
    let tasks = entries.values.flatMap { $0.tasks.values.map(\.task) }
    for identifier in entries.keys {
      entries[identifier]?.physicalSessionActive = false
      entries[identifier]?.publicationGeneration &+= 1
      entries[identifier]?.installed = nil
      entries[identifier]?.pending = nil
    }
    for task in tasks { task.cancel() }
    for slot in slots { _ = await slot.retireAndWait() }
    for task in tasks { _ = await task.result }
    entries.removeAll()
    closeFinished = true
    let waiters = closeWaiters
    closeWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
  }
}
