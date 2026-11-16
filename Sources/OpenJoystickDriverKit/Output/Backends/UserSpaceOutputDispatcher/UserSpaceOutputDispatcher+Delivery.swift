import Foundation

extension UserSpaceOutputDispatcher {

  /// Builds the report of a controller state and submits it to the device of `identifier`.
  ///
  /// A remapped state replaces `input` as the source. The neutral remapped state reaches a device
  /// that exists even when output is suppressed, and it never creates a device. `onPublished` runs
  /// after the report reaches the device.
  ///
  /// - Throws: `CancellationError` when the dispatcher is closed or when output is suppressed for a
  ///   remapped state that is not neutral, or the error of creating the device or sending the
  ///   report; the last two also set the status to an error.
  internal func deliver(
    input: ControllerState?,
    from identifier: LogicalControllerID,
    remappedState: RemappingGamepadState?,
    onPublished: @Sendable () -> Void = {}
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
      withRegistry { if lifecycle.isOpen { _status = .error("\(error)") } }
      throw error
    }
    guard lifecycle.isOpen else { throw CancellationError() }
    if outputSuppressed, !neutralizing { return }
    let stickTransfer =
      remappedState == nil
      ? VirtualGamepadReportMapping.stickTransfer(for: identifier)
      : VirtualGamepadReportMapping.StickTransfer(deadzone: 0, rescalesDeadzone: false)
    let rightPadIsRightStick = VirtualGamepadReportMapping.rightPadIsRightStick(identifier)
    let isActive: @Sendable () -> Bool = { [self] in
      lifecycle.isOpen && (!isOutputSuppressed(remapped: remapped) || neutralizing)
    }
    do {
      try await activeEntry.sender.submit(
        isFrame: true,
        whileActive: isActive,
        requireActive: true
      ) {
        [activeEntry] in
        guard isActive() else { throw CancellationError() }
        let primaryReport = activeEntry.inputReportState.update(remapped: remapped) { state in
          if let remappedState {
            VirtualGamepadReportMapping.apply(remappedState, to: &state)
          } else if let input {
            VirtualGamepadReportMapping.apply(
              input,
              stickTransfer: stickTransfer,
              rightPadIsRightStick: rightPadIsRightStick,
              to: &state
            )
          }
        }
        let primary =
          activeEntry.inputReportState.claimDelivery(of: primaryReport) ? [primaryReport] : []
        return primary + activeEntry.inputReportState.claimChangedAuxiliaryReports()
      }.value()
      onPublished()
      withRegistry { recomputeStatusLocked() }
    } catch UserSpaceReportSender.Failure.superseded {
      // A newer frame in the queue carries the complete state, so the device stays open.
      return
    } catch {
      let removed = withRegistry { () -> Entry? in
        guard entries[identifier] === activeEntry else { return nil }
        _status = .error("\(error)")
        return entries.removeValue(forKey: identifier)
      }
      await removed?.close()
      throw error
    }
  }

  /// The device entry of `identifier`; it creates the device when none exists.
  ///
  /// One creation runs at a time per controller, and a failure delays the next attempt by the retry
  /// policy.
  ///
  /// - Throws: `CancellationError` when the dispatcher closes during creation,
  ///   `CreationError.createFailed` when the retry policy still waits, or the error of creating the
  ///   device.
  internal func entry(for identifier: LogicalControllerID) async throws -> Entry {
    let result: (task: Task<Entry, any Error>, generation: UInt64) = try registryLock.withLock {
      guard lifecycle.isOpen else { throw CancellationError() }
      let generation = lifecycleGenerations[identifier, default: 0]
      if let entry = entries[identifier] { return (Task { entry }, generation) }
      if let task = creationTasks[identifier] { return (task, generation) }

      let now = DispatchTime.now().uptimeNanoseconds
      let retryPolicy = creationRetryPolicies[identifier] ?? UserSpaceDeviceCreationRetryPolicy()
      guard retryPolicy.permitsAttempt(at: now) else { throw CreationError.createFailed }

      let identity = identityRegistry.reserve(identifier)
      let task = Task { try await self.createEntry(for: identifier, identity: identity) }
      creationTasks[identifier] = task
      return (task, generation)
    }
    let (task, generation) = result

    do {
      let entry = try await task.value
      let installed = withRegistry { () -> Bool in
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

  /// Runs `body` under `registryLock` and announces a status change it made after the lock is
  /// released, so observers never run while the registry is locked.
  internal func withRegistry<Result>(_ body: () throws -> Result) rethrows -> Result {
    let (result, announce) = try registryLock.withLock { () -> (Result, Bool) in
      let result = try body()
      defer { statusChangePending = false }
      return (result, statusChangePending)
    }
    if announce { NotificationCenter.postServiceStatusChanged(from: self) }
    return result
  }

  /// Sets the status from the entries: `off` without a device, otherwise `on` with the device
  /// count.
  ///
  /// The caller holds `registryLock`.
  internal func recomputeStatusLocked() {
    _status = entries.isEmpty ? .off : .backend("on (devices=\(entries.count))")
  }
}
