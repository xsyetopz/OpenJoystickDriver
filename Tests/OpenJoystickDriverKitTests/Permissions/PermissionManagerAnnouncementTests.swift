import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct PermissionManagerAnnouncementTests {
  private final class Posts: @unchecked Sendable {
    private let lock = NSLock()
    private var posts = 0
    var count: Int { lock.withLock { posts } }
    func increment() { lock.withLock { posts += 1 } }
  }

  @Test
  func eachChangeOfPermissionsAnnouncesOncePerObservation() async {
    let manager = PermissionManager.grantingAll()
    let posts = Posts()
    let observer = NotificationCenter.default.addObserver(
      forName: .ojdServiceStatusDidChange,
      object: manager,
      queue: nil
    ) { _ in posts.increment() }
    defer { NotificationCenter.default.removeObserver(observer) }
    let current = await manager.postEventState
    let other: RemappingPostEventAccessState = current == .granted ? .notAuthorized : .granted
    let granted = PermissionManager.Snapshot(inputRead: .granted, inputInject: .granted)
    let denied = PermissionManager.Snapshot(inputRead: .denied, inputInject: .denied)

    await manager.record(granted, postEvent: current)
    let afterFirst = posts.count
    await manager.record(granted, postEvent: current)
    #expect(posts.count == afterFirst)

    await manager.record(denied, postEvent: other)
    #expect(posts.count == afterFirst + 1)
  }
}
