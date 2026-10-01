import Darwin
import Foundation
import IOKit
import IOKit.hid
import Security

extension UserSpaceOutputDispatcher {

  internal func deliver(
    input: ControllerState?,
    labels: ControllerButtonLabels,
    from identifier: DeviceIdentifier,
    remappedState: RemappingGamepadState?
  ) async throws {
    let neutralizing = remappedState == .neutral
    let remapped = remappedState != nil
    let outputSuppressed = isOutputSuppressed(remapped: remapped)
    guard lifecycle.isOpen, !outputSuppressed || neutralizing || !remapped else {
      throw CancellationError()
    }
    let activeEntry: Entry
    do {
      if neutralizing {
        guard let existing = registryLock.withLock({ entries[identifier] }) else { return }
        activeEntry = existing
      } else {
        activeEntry = try await entry(for: identifier)
      }
    } catch {
      registryLock.withLock { if lifecycle.isOpen { _status = .error("\(error)") } }
      throw error
    }
    guard lifecycle.isOpen else { throw CancellationError() }
    if outputSuppressed && !neutralizing { return }
    let stickTransfer =
      remappedState == nil
      ? Self.stickTransfer(for: identifier) : StickTransfer(deadzone: 0, rescalesDeadzone: false)
    let isActive: @Sendable () -> Bool = { [self] in
      lifecycle.isOpen && (!isOutputSuppressed(remapped: remapped) || neutralizing)
    }
    do {
      try await activeEntry.sender.submit(whileActive: isActive, requireActive: true) {
        [self, activeEntry] in
        guard isActive() else { throw CancellationError() }
        let primaryReport = activeEntry.inputReportState.update(remapped: remapped) { state in
          if let remappedState {
            apply(remappedState, to: &state)
          } else if let input {
            Self.apply(input, labels: labels, stickTransfer: stickTransfer, to: &state)
          }
        }
        let primary =
          activeEntry.inputReportState.claimDelivery(of: primaryReport) ? [primaryReport] : []
        return primary + activeEntry.inputReportState.claimChangedAuxiliaryReports()
      }.value()
      registryLock.withLock { recomputeStatusLocked() }
    } catch {
      let removed = registryLock.withLock { () -> Entry? in
        guard entries[identifier] === activeEntry else { return nil }
        _status = .error("\(error)")
        return entries.removeValue(forKey: identifier)
      }
      await removed?.close()
      throw error
    }
  }

  internal func entry(
    for identifier: DeviceIdentifier,
    seed: UserSpaceInputReportState.Snapshot? = nil
  ) async throws -> Entry {
    let result: (task: Task<Entry, Error>, generation: UInt64) = try registryLock.withLock {
      guard lifecycle.isOpen else { throw CancellationError() }
      let generation = lifecycleGenerations[identifier, default: 0]
      if let entry = entries[identifier] { return (Task { entry }, generation) }
      if let task = creationTasks[identifier] { return (task, generation) }

      let now = DispatchTime.now().uptimeNanoseconds
      let retryPolicy = creationRetryPolicies[identifier] ?? UserSpaceDeviceCreationRetryPolicy()
      guard retryPolicy.permitsAttempt(at: now) else { throw CreationError.createFailed }

      let task = Task { try await self.createEntry(for: identifier, seed: seed) }
      creationTasks[identifier] = task
      return (task, generation)
    }
    let (task, generation) = result

    do {
      let entry = try await task.value
      let installed = registryLock.withLock { () -> Bool in
        guard lifecycle.isOpen, lifecycleGenerations[identifier, default: 0] == generation else {
          return false
        }
        creationTasks.removeValue(forKey: identifier)
        creationRetryPolicies.removeValue(forKey: identifier)
        entries[identifier] = entry
        recomputeStatusLocked()
        return true
      }
      guard installed else {
        await entry.close()
        throw CancellationError()
      }
      return entry
    } catch {
      registryLock.withLock {
        guard lifecycleGenerations[identifier, default: 0] == generation else { return }
        creationTasks.removeValue(forKey: identifier)
        var policy = creationRetryPolicies[identifier] ?? UserSpaceDeviceCreationRetryPolicy()
        policy.recordFailure(at: DispatchTime.now().uptimeNanoseconds)
        creationRetryPolicies[identifier] = policy
      }
      throw error
    }
  }

  /// Replaces a published device its publisher lost with a new one that starts from the lost
  /// device's state, so the virtual gamepad comes back without waiting for new input.
  internal func replaceLostEntry(for identifier: DeviceIdentifier, lost: Entry) async {
    let removed = registryLock.withLock { () -> Bool in
      guard lifecycle.isOpen, entries[identifier] === lost else { return false }
      entries.removeValue(forKey: identifier)
      recomputeStatusLocked()
      return true
    }
    guard removed else { return }
    let seed = lost.inputReportState.snapshot()
    await lost.close()
    guard let entry = try? await entry(for: identifier, seed: seed) else { return }
    _ = try? await entry.sender.submit { [entry] in [entry.inputReportState.currentReport()] }
      .value()
  }

  internal func recomputeStatusLocked() {
    _status = entries.isEmpty ? .off : .backend("on (devices=\(entries.count))")
  }
}
