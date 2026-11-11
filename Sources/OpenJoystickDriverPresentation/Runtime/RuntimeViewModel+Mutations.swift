import Foundation
import OpenJoystickDriverKit

extension RuntimeViewModel {
  /// Returns when no scoped refresh, full refresh or change runs.
  func waitForExclusiveAccess() async {
    await waitForScopedRefreshCompletion()
    await waitForExclusiveOperationCompletion()
  }

  /// Resumes the callers that wait for an exclusive operation and runs the pending scoped
  /// refreshes.
  func resumeDeferredRefreshes() {
    resumeExclusiveOperationWaiters()
    schedulePendingScopedRefresh()
  }

  /// Publishes the snapshot that a profile request returned as the authoritative profile library
  /// and Post Event access.
  func applyRemappingSnapshot(_ snapshot: ApplicationServiceRemappingSnapshotPayload) {
    remappingState = .available(snapshot)
    postEventAccessState = .available(snapshot.postEventAccess)
    postEventAccessGeneration += 1
    authoritativePostEventAccess = snapshot.postEventAccess
    updateStatusRemappingSnapshot(snapshot, postEventAccess: snapshot.postEventAccess)
  }

  /// Sets the permissions of the loaded status; does nothing until the status loads.
  func updateStatusPermissions(_ permissions: RuntimePermissionSummary) {
    guard case .available(let status) = statusState else { return }
    let nextState = RuntimeStatusState.available(status.applyingPermissions(permissions))
    if statusState != nextState { statusState = nextState }
  }

  /// Sets the Post Event access of the loaded status; does nothing until the status loads.
  func updateStatusPostEventAccess(_ state: RemappingPostEventAccessState?) {
    guard case .available(let status) = statusState else { return }
    let nextState = RuntimeStatusState.available(status.applyingPostEventAccess(state))
    if statusState != nextState { statusState = nextState }
  }

  /// Sets the profile library data of the loaded status; does nothing until the status loads.
  func updateStatusRemappingSnapshot(
    _ snapshot: ApplicationServiceRemappingSnapshotPayload,
    postEventAccess: RemappingPostEventAccessState?
  ) {
    guard case .available(let status) = statusState else { return }
    let nextState = RuntimeStatusState.available(
      status.applyingRemappingSnapshot(snapshot, postEventAccess: postEventAccess)
    )
    if statusState != nextState { statusState = nextState }
  }
}
