import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct PermissionPollingTests {
  @Test("restarting polling cancels the earlier poller")
  func restartingPollingCancelsEarlierPoller() async throws {
    let manager = PermissionManager.grantingAll()
    await manager.startPolling()
    let firstPoller = try #require(await manager.pollingTask)

    await manager.startPolling()
    let secondPoller = try #require(await manager.pollingTask)
    await manager.stopPolling()

    #expect(firstPoller.isCancelled)
    #expect(secondPoller.isCancelled)
  }
}
