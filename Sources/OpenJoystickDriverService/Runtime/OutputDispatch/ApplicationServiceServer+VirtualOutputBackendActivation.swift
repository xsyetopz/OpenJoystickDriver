import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  /// Publishes the automatic dispatcher for the connected controllers after every earlier queued
  /// change; true when output is live.
  func activateVirtualOutputBackendForCurrentDevices() async -> Bool {
    await virtualOutputTransitionCoordinator.enqueue { [weak self] in
      await self?.performVirtualOutputBackendActivation() ?? false
    }
  }

  /// Builds, activates, and publishes the automatic dispatcher when no output is live.
  ///
  /// A failure closes the candidate and leaves output unavailable with the failure as its status.
  func performVirtualOutputBackendActivation() async -> Bool {
    guard !isVirtualOutputServerStopped() else { return false }
    let isLive = userSpaceLock.withLock { userSpaceEnabled && userSpaceDispatcher != nil }
    if isLive { return true }

    let candidate: UserSpaceDispatcherBuild
    do {
      candidate = try await withVirtualOutputTimeout(
        virtualOutputTransitionTimeouts.stageNanoseconds,
        clock: virtualOutputTransitionClock,
        error: .stageTimedOut
      ) {
        try self.buildUserSpaceDispatcher()
      } onLateSuccess: { late in
        _ = await self.closeVirtualOutputBackend(late.closeSlot)
      }
    } catch {
      recordVirtualOutputBackendUnavailable(error)
      return false
    }
    guard !isVirtualOutputServerStopped() else {
      _ = await closeVirtualOutputBackend(candidate.closeSlot)
      return false
    }

    do {
      try await activateVirtualOutputDispatcher(
        candidate.dispatcher,
        for: await connectedIdentifiers()
      )
    } catch {
      _ = await closeVirtualOutputBackend(candidate.closeSlot)
      recordVirtualOutputBackendUnavailable(error)
      return false
    }

    let published = withUserSpaceState { () -> Bool in
      guard !virtualOutputServerStopped else { return false }
      userSpaceDispatcher = candidate.dispatcher
      userSpaceCloseSlot = candidate.closeSlot
      dispatcher.setBackend(candidate.dispatcher)
      userSpaceEnabled = true
      userSpaceStatus = candidate.status
      return true
    }
    guard published else {
      _ = await closeVirtualOutputBackend(candidate.closeSlot)
      return false
    }
    print("[ApplicationServiceServer] Virtual gamepad ready")
    return true
  }

  /// Activates `candidate` for `identifiers`, bounding each controller by the per-controller
  /// timeout and the whole set by the total timeout.
  ///
  /// - Throws: `CancellationError` when the server stops before a controller's activation.
  private func activateVirtualOutputDispatcher(
    _ candidate: any VirtualOutputDispatching,
    for identifiers: [LogicalControllerID]
  ) async throws {
    let timeout = virtualOutputTransitionTimeouts.activationNanoseconds(for: identifiers.count)
    guard !identifiers.isEmpty, let scoped = candidate as? any VirtualOutputControllerActivating
    else {
      try await withVirtualOutputTimeout(
        timeout,
        clock: virtualOutputTransitionClock,
        error: .activationTimedOut
      ) { try await candidate.activate(for: identifiers) }
      return
    }
    let started = virtualOutputTransitionClock.now()
    for identifier in identifiers {
      guard !isVirtualOutputServerStopped() else { throw CancellationError() }
      let now = virtualOutputTransitionClock.now()
      let elapsed = now >= started ? now - started : 0
      let remaining = timeout > elapsed ? timeout - elapsed : 0
      try await withVirtualOutputTimeout(
        min(remaining, virtualOutputTransitionTimeouts.perControllerNanoseconds),
        clock: virtualOutputTransitionClock,
        error: .activationTimedOut
      ) { try await scoped.activate(controller: identifier) }
    }
  }

  /// Records that the backend is unavailable with `error` as its status, unless the server stopped.
  private func recordVirtualOutputBackendUnavailable(_ error: any Error) {
    withUserSpaceState {
      guard !virtualOutputServerStopped else { return }
      userSpaceStatus = .error("\(error)")
    }
    print("[ApplicationServiceServer] Virtual gamepad unavailable: \(error)")
  }

  /// Every connected controller once, in provider order.
  func connectedIdentifiers() async -> [LogicalControllerID] {
    var seen = Set<LogicalControllerID>()
    return (await connectedIdentifierProvider()).filter { seen.insert($0).inserted }
  }
}
