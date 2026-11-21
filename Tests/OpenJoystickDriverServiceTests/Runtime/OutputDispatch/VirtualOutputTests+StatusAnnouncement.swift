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

  @Test
  func inputKeepsPublicationTimingsCurrentWithoutAnnouncingEveryReport() async throws {
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)
    let probe = AutomaticBackendProbe()
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(
        dispatcher: LoggingOutputDispatcher(),
        installationKey: testPortKeyInstallationKey
      ),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { _ in probe },
      descriptionsProvider: provider([identifier]),
      timingAnnouncementIntervalNanoseconds: .max
    )
    let tally = AnnouncementTally()
    let observer = NotificationCenter.default.addObserver(
      forName: .ojdServiceStatusDidChange,
      object: dispatcher,
      queue: nil
    ) { _ in tally.increment() }
    defer { NotificationCenter.default.removeObserver(observer) }

    try await dispatcher.activate(for: [identifier])
    await dispatcher.dispatch(ControllerEvent([.press(.south)]), from: identifier)
    let settled = tally.count
    let before = try #require(
      dispatcher.publicationStatus(for: identifier)?.lastCompletedNanoseconds
    )

    let delivered = probe.dispatched
    for _ in 0..<1_000 {
      await dispatcher.dispatch(ControllerEvent([.press(.south)]), from: identifier)
    }

    #expect(probe.dispatched == delivered + 1_000)
    #expect(tally.count == settled)
    let status = try #require(dispatcher.publicationStatus(for: identifier))
    #expect(status.state == .published)
    #expect(try #require(status.lastCompletedNanoseconds) > before)
    let completed = try #require(status.lastCompletedNanoseconds)
    #expect(dispatcher.status.wireValue.contains("last-completed=\(completed)"))

    await dispatcher.controllerDidStop(identifier)
    #expect(tally.count > settled)
    await dispatcher.close()
  }

  @Test
  func steadyInputLeavesCoordinatorStateUnchanged() async throws {
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(
        dispatcher: LoggingOutputDispatcher(),
        installationKey: testPortKeyInstallationKey
      ),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { _ in AutomaticBackendProbe() },
      descriptionsProvider: provider([identifier]),
      timingAnnouncementIntervalNanoseconds: .max
    )
    try await dispatcher.activate(for: [identifier])
    await dispatcher.dispatch(ControllerEvent([.press(.south)]), from: identifier)
    let settled = await dispatcher.coordinator.revision

    for _ in 0..<1_000 {
      await dispatcher.dispatch(ControllerEvent([.press(.south)]), from: identifier)
    }

    #expect(await dispatcher.coordinator.revision == settled)
    await dispatcher.close()
  }

  @Test
  func inputAnnouncesTimingChangesOncePerInterval() async throws {
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(
        dispatcher: LoggingOutputDispatcher(),
        installationKey: testPortKeyInstallationKey
      ),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { _ in AutomaticBackendProbe() },
      descriptionsProvider: provider([identifier]),
      timingAnnouncementIntervalNanoseconds: 0
    )
    let tally = AnnouncementTally()
    let observer = NotificationCenter.default.addObserver(
      forName: .ojdServiceStatusDidChange,
      object: dispatcher,
      queue: nil
    ) { _ in tally.increment() }
    defer { NotificationCenter.default.removeObserver(observer) }

    try await dispatcher.activate(for: [identifier])
    let settled = tally.count
    for _ in 0..<3 {
      await dispatcher.dispatch(ControllerEvent([.press(.south)]), from: identifier)
    }

    #expect(tally.count == settled + 3)
    await dispatcher.close()
  }
}
