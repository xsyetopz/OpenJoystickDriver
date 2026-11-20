import Testing

@testable import OpenJoystickDriverKit

/// An access system that grants everything and counts its Input Monitoring reads.
private final class CountingAccessControlSystem: AccessControlSystem, @unchecked Sendable {
  private let reads = Locked(0)

  var inputReadReads: Int { reads.withLock { $0 } }

  func inputReadAccessState() -> PermissionManager.AccessState {
    reads.withLock { $0 += 1 }
    return .granted
  }

  func inputInjectAccessState() -> PermissionManager.AccessState { .granted }
  func postEventAccessState() -> RemappingPostEventAccessState { .granted }

  @MainActor
  func requestInputReadAccess() {}

  @MainActor
  func requestInputInjectAccess() {}
}

struct InputReadStateReuseTests {
  @Test
  func stateIsReadFromTheSystemWhileNotPolling() async {
    let system = CountingAccessControlSystem()
    let manager = PermissionManager(system: system)

    let state = await manager.currentInputReadState()
    _ = await manager.currentInputReadState()

    #expect(state == .granted)
    #expect(system.inputReadReads == 2)
  }

  @Test
  func polledStateIsReusedWithoutReadingTheSystem() async {
    let system = CountingAccessControlSystem()
    let manager = PermissionManager(system: system)
    await manager.startPolling()
    await manager.refreshAccessState()
    let readsAfterPoll = system.inputReadReads

    let state = await manager.currentInputReadState()
    await manager.stopPolling()

    #expect(state == .granted)
    #expect(system.inputReadReads == readsAfterPoll)
  }

  @Test
  func pollingWithoutAnAnswerReadsTheSystem() async {
    let system = CountingAccessControlSystem()
    let manager = PermissionManager(system: system)
    await manager.startPolling()

    let state = await manager.currentInputReadState()
    await manager.stopPolling()

    #expect(state == .granted)
    #expect(system.inputReadReads == 1)
  }
}
