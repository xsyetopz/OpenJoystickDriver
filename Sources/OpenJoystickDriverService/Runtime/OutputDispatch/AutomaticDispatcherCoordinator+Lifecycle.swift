import Foundation
import OpenJoystickDriverKit

extension AutomaticDispatcherCoordinator {

  func synchronizeSuppression(_ currentValue: @Sendable () -> Bool) async {
    guard !closed else { return }
    let wasSuppressed = suppressed
    suppressed = currentValue()
    suppressionRevision &+= 1
    if suppressed {
      let identifiers = Array(entries.keys)
      var slots: [(DeviceIdentifier, AutomaticBackendSlot)] = []
      for identifier in identifiers {
        guard let entry = entries[identifier] else { continue }
        entries[identifier]?.publicationGeneration &+= 1
        entries[identifier]?.tasks.values.forEach { $0.task.cancel() }
        entries[identifier]?.pending = nil
        guard let installed = entry.installed else { continue }
        entries[identifier]?.installed = nil
        entries[identifier]?.installedToken = nil
        entries[identifier]?.target = nil
        entries[identifier]?.retiring = installed
        slots.append((identifier, installed))
      }
      await withTaskGroup(of: (DeviceIdentifier, Bool).self) { group in
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
      entry -> (DeviceIdentifier, PublicationContext)? in
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
  func clearRetirementOnceClosed(_ slot: AutomaticBackendSlot, controller: DeviceIdentifier) {
    Task { [weak self] in
      await slot.waitForCloseCompletion()
      await self?.retirementFinished(identifier: controller, slot: slot)
    }
  }

  private func retirementFinished(identifier: DeviceIdentifier, slot: AutomaticBackendSlot) async {
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

  func installedTargets() -> [DeviceIdentifier: VirtualHIDProfileID] {
    entries.reduce(into: [:]) { targets, element in
      guard element.value.installed != nil, let target = element.value.target else { return }
      targets[element.key] = target
    }
  }

  func recordPublicationAttempt(for controller: DeviceIdentifier) {
    entries[controller]?.lastAttemptedSend = DispatchTime.now().uptimeNanoseconds
  }

  func recordPublicationCompletion(for controller: DeviceIdentifier) {
    entries[controller]?.lastCompletedSend = DispatchTime.now().uptimeNanoseconds
    entries[controller]?.lastFailure = nil
    entries[controller]?.recoveryState = "idle"
  }

  func publicationDiagnostics() -> [String] {
    entries.compactMap { identifier, entry in
      guard let target = entry.target ?? entry.context?.target else { return nil }
      let attempted = entry.lastAttemptedSend.map(String.init) ?? "none"
      let completed = entry.lastCompletedSend.map(String.init) ?? "none"
      let result =
        entry.lastFailure.map { "failure=\($0)" }
        ?? "status=\(entry.installed?.backend.status.wireValue ?? "none")"
      return "controller=\(identifier), session=\(entry.sessionGeneration), "
        + "publication=\(entry.publicationGeneration), target=\(target.rawValue), "
        + "last-attempted=\(attempted), last-completed=\(completed), "
        + "\(result), recovery=\(entry.recoveryState)"
    }.sorted()
  }

  /// The installed backend of the one controller matching `model` and `runtimeIdentifier`.
  func installedBackend(
    matching model: DeviceIdentifier,
    runtimeIdentifier: String?
  ) -> (controller: DeviceIdentifier, backend: any VirtualOutputDispatching)? {
    guard
      let controller = DeviceManager.connectedIdentifier(
        among: entries.keys,
        matching: model,
        runtimeIdentifier: runtimeIdentifier
      ), let backend = entries[controller]?.installed?.backend
    else { return nil }
    return (controller, backend)
  }

  /// Each controller's publication state, for controllers that have a target profile.
  func publicationStatuses() -> [DeviceIdentifier: ApplicationServicePublicationStatus] {
    entries.reduce(into: [:]) { statuses, element in
      let entry = element.value
      guard let target = entry.target ?? entry.context?.target else { return }
      let state: ApplicationServicePublicationStatus.State
      let reason: String?
      if let failure = entry.lastFailure {
        (state, reason) = (.failed, failure)
      } else if entry.installed != nil {
        (state, reason) = (.published, nil)
      } else {
        (state, reason) = (.notPublished, suppressed ? "suppressed" : "noInputYet")
      }
      statuses[element.key] = ApplicationServicePublicationStatus(
        state: state,
        reason: reason,
        target: target,
        lastAttemptedNanoseconds: entry.lastAttemptedSend,
        lastCompletedNanoseconds: entry.lastCompletedSend
      )
    }
  }

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

  /// A failed publication is retired before an eligible replacement is considered.
  /// The physical session remains valid, so a later report can recover without a mode change.
  func recoverPublication(for controller: DeviceIdentifier, failure: any Error) async {
    guard !closed, !suppressed, var entry = entries[controller], entry.physicalSessionActive,
      entry.recoveryState == "idle", entry.context != nil
    else { return }
    entry.publicationGeneration &+= 1
    entry.lastFailure = String(describing: failure)
    entry.recoveryState = "retiring"
    let old = entry.installed ?? entry.retiring
    entry.installed = nil
    entry.installedToken = nil
    entry.target = nil
    entry.retiring = old
    entry.tasks.values.forEach { $0.task.cancel() }
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

  private func resumeRecovery(
    _ controller: DeviceIdentifier,
    after slot: AutomaticBackendSlot,
    generation: UInt64
  ) {
    guard entries[controller]?.retiring === slot,
      entries[controller]?.recoveryState == "waiting-for-retirement"
    else { return }
    beginRecoveryRetry(controller, generation: generation)
  }

  private func beginRecoveryRetry(_ controller: DeviceIdentifier, generation: UInt64) {
    guard entries[controller]?.publicationGeneration == generation else { return }
    entries[controller]?.retiring = nil
    let token = UUID()
    entries[controller]?.recoveryToken = token
    entries[controller]?.recoveryState = "retry-gated"
    scheduleRecoveryRetry(controller, token: token)
  }

  private func retryPublication(_ controller: DeviceIdentifier, token: UUID) async {
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
      entries[controller]?.lastFailure = String(describing: error)
      entries[controller]?.recoveryState = "retry-gated"
      scheduleRecoveryRetry(controller, token: token)
    }
  }

  private func scheduleRecoveryRetry(_ controller: DeviceIdentifier, token: UUID) {
    Task { [weak self] in
      guard let self else { return }
      try? await Task.sleep(nanoseconds: self.recoveryDelayNanoseconds)
      await self.retryPublication(controller, token: token)
    }
  }

  func stop(_ controller: DeviceIdentifier) async {
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
    tasks.forEach { $0.cancel() }
    let retired = await installed?.retireAndWait() ?? true
    for task in tasks { _ = await task.result }
    if retired, entries[controller]?.sessionGeneration == entry.sessionGeneration {
      entries[controller]?.retiring = nil
    } else if let installed, !retired {
      clearRetirementOnceClosed(installed, controller: controller)
    }
  }

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
    tasks.forEach { $0.cancel() }
    for slot in slots { _ = await slot.retireAndWait() }
    for task in tasks { _ = await task.result }
    entries.removeAll()
    closeFinished = true
    let waiters = closeWaiters
    closeWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }
}
