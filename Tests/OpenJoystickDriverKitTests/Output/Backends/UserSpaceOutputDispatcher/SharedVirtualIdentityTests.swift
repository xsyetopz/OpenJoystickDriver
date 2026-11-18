import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A virtual device that accepts every report and answers no host request.
private final class SilentBackend: VirtualDeviceBackend {
  func activate(hostReports _: UserSpaceHostReportHandler) {}
  func send(_: [UInt8]) {}
  func close() {}
}

/// Records the identity of every device it creates.
private final class IdentityRecordingPublisher: VirtualHIDDevicePublisher, @unchecked Sendable {
  private let lock = NSLock()
  private var created: [LogicalControllerID: VirtualDeviceIdentity] = [:]

  func createDevice(
    for identifier: LogicalControllerID,
    identity: VirtualDeviceIdentity,
    profile _: VirtualDeviceProfile,
    format _: any VirtualGamepadReportFormat
  ) -> any VirtualDeviceBackend {
    lock.withLock { created[identifier] = identity }
    return SilentBackend()
  }

  func identity(of identifier: LogicalControllerID) -> VirtualDeviceIdentity? {
    lock.withLock { created[identifier] }
  }
}

struct SharedVirtualIdentityTests {
  private static func sharedSerialPad(locationID: UInt32) -> LogicalControllerID {
    LogicalControllerID(
      vendorID: 0x057E,
      productID: 0x2009,
      serialNumber: "000000000001",
      locationID: locationID
    )
  }

  private static func dispatcher(
    _ publisher: IdentityRecordingPublisher,
    _ identities: SharedVirtualIdentityRegistry
  ) -> UserSpaceOutputDispatcher {
    UserSpaceOutputDispatcher(
      publisher: publisher,
      profile: .generic,
      format: OJDGenericGamepadFormat(),
      identities: identities
    )
  }

  /// The automatic dispatcher builds one backend per controller; two pads with one serial must
  /// still publish distinct virtual identities.
  @Test
  func backendsOfSameSerialPadsPublishDistinctIdentities() async throws {
    let identities = SharedVirtualIdentityRegistry()
    let publisher = IdentityRecordingPublisher()
    let first = Self.sharedSerialPad(locationID: 0x1400_0000)
    let second = Self.sharedSerialPad(locationID: 0x1500_0000)
    let firstBackend = Self.dispatcher(publisher, identities)
    let secondBackend = Self.dispatcher(publisher, identities)

    try await firstBackend.activate(controller: first)
    try await secondBackend.activate(controller: second)

    let firstIdentity = try #require(publisher.identity(of: first))
    let secondIdentity = try #require(publisher.identity(of: second))
    #expect(firstIdentity.serialNumber != secondIdentity.serialNumber)
    #expect(firstIdentity.locationID != secondIdentity.locationID)
    await firstBackend.close()
    await secondBackend.close()
  }

  /// A replacement backend reserves before the old one closes, and keeps the controller's
  /// identity after it does.
  @Test
  func replacementBackendKeepsIdentityAfterOldBackendCloses() async throws {
    let identities = SharedVirtualIdentityRegistry()
    let publisher = IdentityRecordingPublisher()
    let first = Self.sharedSerialPad(locationID: 0x1400_0000)
    let second = Self.sharedSerialPad(locationID: 0x1500_0000)
    let old = Self.dispatcher(publisher, identities)
    try await old.activate(controller: first)
    let plain = try #require(publisher.identity(of: first))

    let replacement = Self.dispatcher(publisher, identities)
    try await replacement.activate(controller: first)
    await old.close()
    let other = Self.dispatcher(publisher, identities)
    try await other.activate(controller: second)

    #expect(publisher.identity(of: first) == plain)
    #expect(publisher.identity(of: second)?.serialNumber != plain.serialNumber)
    await replacement.close()
    await other.close()
  }

  @Test
  func closedBackendFreesItsIdentities() async throws {
    let identities = SharedVirtualIdentityRegistry()
    let publisher = IdentityRecordingPublisher()
    let first = Self.sharedSerialPad(locationID: 0x1400_0000)
    let second = Self.sharedSerialPad(locationID: 0x1500_0000)
    let backend = Self.dispatcher(publisher, identities)
    try await backend.activate(controller: first)
    let plain = try #require(publisher.identity(of: first))
    await backend.close()

    let next = Self.dispatcher(publisher, identities)
    try await next.activate(controller: second)

    #expect(publisher.identity(of: second) == plain)
    await next.close()
  }
}
