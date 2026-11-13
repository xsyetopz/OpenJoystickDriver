import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

private final class AnnouncementTally: @unchecked Sendable {
  private let lock = NSLock()
  private var posts = 0
  var count: Int { lock.withLock { posts } }
  func increment() { lock.withLock { posts += 1 } }
}

extension VirtualOutputTests {
  @Test
  func activationAnnouncesSelectionAndPublicationItChangedAndNothingElse() async throws {
    let identifiers = [LogicalControllerID(vendorID: 1, productID: 2)]
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(
        dispatcher: LoggingOutputDispatcher(),
        installationKey: testPortKeyInstallationKey
      ),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { _ in AutomaticBackendProbe() },
      descriptionsProvider: provider(identifiers)
    )
    let tally = AnnouncementTally()
    let observer = NotificationCenter.default.addObserver(
      forName: .ojdServiceStatusDidChange,
      object: dispatcher,
      queue: nil
    ) { _ in tally.increment() }
    defer { NotificationCenter.default.removeObserver(observer) }

    try await dispatcher.activate(for: identifiers)
    #expect(tally.count >= 1)

    let settled = tally.count
    await dispatcher.setOutputSuppressed(false)
    #expect(tally.count == settled)
    await dispatcher.close()
  }
}
