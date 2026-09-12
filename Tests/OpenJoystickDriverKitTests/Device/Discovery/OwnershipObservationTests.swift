import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct OwnershipObservationTests {
  @Test
  func ownershipLossStopsOutputAndReacquisitionUsesFreshState() async throws {
    let dispatcher = OwnershipOutputRecorder()
    let manager = DeviceManager(dispatcher: dispatcher)
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678, locationID: 77)
    await manager.handleHIDEvent(
      .connected(
        vendorID: identifier.vendorID,
        productID: identifier.productID,
        serialNumber: nil,
        locationID: 77,
        productName: "Test",
        transport: "USB",
        ownership: .exclusive
      )
    )
    let first = try #require(await manager.pipelines[identifier])
    #expect(await first.isActive)
    await manager.handleHIDEvent(
      .ownershipChanged(locationID: 77, ownership: .ownedByAnotherClient)
    )
    #expect(await first.isActive == false)
    #expect(dispatcher.stops == 1)
    await manager.handleHIDEvent(
      .ownershipChanged(locationID: 77, ownership: .ownedByAnotherClient)
    )
    #expect(dispatcher.stops == 1)
    await manager.handleHIDEvent(.ownershipChanged(locationID: 77, ownership: .exclusive))
    let second = try #require(await manager.pipelines[identifier])
    #expect(first !== second)
    #expect(await second.isActive)
    #expect(await first.isActive == false)
    #expect(
      dispatcher.ownerships == [
        .exclusive, .ownedByAnotherClient, .ownedByAnotherClient, .exclusive,
      ]
    )
    await manager.stop()
  }

  @Test
  func competingOwnerIsVisibleWithoutStartingOrPublishingThePipeline() async throws {
    let dispatcher = OwnershipOutputRecorder()
    let manager = DeviceManager(dispatcher: dispatcher)
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678, locationID: 77)
    await manager.handleHIDEvent(
      .connected(
        vendorID: identifier.vendorID,
        productID: identifier.productID,
        serialNumber: nil,
        locationID: 77,
        productName: "Test",
        transport: "USB",
        ownership: .ownedByAnotherClient
      )
    )
    let pipeline = try #require(await manager.pipelines[identifier])
    #expect(await pipeline.isActive == false)
    #expect(dispatcher.dispatchCount == 0)
    #expect(dispatcher.ownerships == [.ownedByAnotherClient])
    let descriptions = await manager.connectedDeviceDescriptions()
    #expect(descriptions.first?.hidInputOwnership == .ownedByAnotherClient)
    await manager.stop()
  }

  @Test
  func exclusiveHIDOwnershipIsReportedByTheLiveManagerAndPayload() async throws {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678, locationID: 77)
    await manager.handleHIDEvent(
      .connected(
        vendorID: identifier.vendorID,
        productID: identifier.productID,
        serialNumber: nil,
        locationID: 77,
        productName: "Test",
        transport: "USB",
        ownership: .exclusive
      )
    )
    #expect(await manager.ownershipObservation(for: identifier) == .exclusiveHID)
    let descriptions = await manager.connectedDeviceDescriptions()
    let description = try #require(descriptions.first)
    let decoded = try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONEncoder().encode(description)
    )
    #expect(decoded.physicalOwnership == .exclusiveHID)
    #expect(decoded.hidInputOwnership == .exclusive)
    #expect(decoded.duplicateExposureRisk == .none)
    await manager.handleHIDEvent(
      .ownershipChanged(locationID: 77, ownership: .ownedByAnotherClient)
    )
    #expect(await manager.ownershipObservation(for: identifier) == .nativeHIDVisible)
    let lost = await manager.connectedDeviceDescriptions()
    #expect(lost.first?.hidInputOwnership == .ownedByAnotherClient)
    #expect(lost.first?.duplicateExposureRisk == .nativeHIDVisible)
    await manager.handleHIDEvent(
      .disconnected(vendorID: identifier.vendorID, productID: identifier.productID, locationID: 77)
    )
    #expect(await manager.ownershipObservation(for: identifier) == .unknown)
    await manager.stop()
  }

  @Test(arguments: [HIDInputOwnership.shared, .accessDenied, .acquisitionFailed, .unknown])
  func unsuccessfulHIDAcquisitionNeverClaimsExclusiveOwnership(_ ownership: HIDInputOwnership) {
    let info = DeviceManager.DeviceInfo(
      name: "Test",
      connection: "USB",
      serialNumber: nil,
      discoverySource: .hid,
      hidInputOwnership: ownership
    )
    #expect(info.ownershipObservation == .nativeHIDVisible)
  }

  @Test
  func inputMonitoringRequirementFollowsDiscoverySource() {
    #expect(DeviceManager.DiscoverySource.hid.requiresInputMonitoring)
    #expect(!DeviceManager.DiscoverySource.rawUSB(route: .ioUSBHost).requiresInputMonitoring)
    #expect(!DeviceManager.DiscoverySource.rawUSB(route: .usbDriverKit).requiresInputMonitoring)
  }

  @Test(arguments: [
    (DeviceManager.DiscoverySource.hid, ControllerOwnershipObservation.nativeHIDVisible),
    (
      DeviceManager.DiscoverySource.rawUSB(route: .ioUSBHost),
      ControllerOwnershipObservation.exclusiveRawUSB
    ),
    (
      DeviceManager.DiscoverySource.rawUSB(route: .usbDriverKit),
      ControllerOwnershipObservation.driverKitOwnedUSB
    )
  ]) func discoverySourceDerivesOwnership(
    source: DeviceManager.DiscoverySource,
    expected: ControllerOwnershipObservation
  ) {
    let info = DeviceManager.DeviceInfo(
      name: "Test controller",
      connection: "USB",
      serialNumber: nil,
      discoverySource: source
    )

    #expect(info.ownershipObservation == expected)
  }

  @Test func missingDeviceLookupIsUnknown() async {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)

    #expect(await manager.ownershipObservation(for: identifier) == .unknown)
  }

  @Test func deviceDescriptionRoundTripSurfacesOwnershipAndDuplicateRisk() throws {
    let description = ApplicationServiceDeviceDescription(
      name: "Test controller",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "Generic HID",
      connection: "HID",
      discoverySource: .hid,
      physicalOwnership: .nativeHIDVisible,
      duplicateExposureRisk: .nativeHIDVisible,
      serialNumber: nil
    )

    let decoded = try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONEncoder().encode(description)
    )

    #expect(decoded.physicalOwnership == .nativeHIDVisible)
    #expect(decoded.duplicateExposureRisk == .nativeHIDVisible)
  }
}

private final class OwnershipOutputRecorder: OutputDispatcher, ControllerLifecycleListener,
  ControllerInputOwnershipListener, @unchecked Sendable
{
  private let lock = NSLock()
  private var stoppedCount = 0
  private var sentCount = 0
  private var recordedOwnerships: [HIDInputOwnership] = []
  private var suppressed = false

  var stops: Int { lock.withLock { stoppedCount } }
  var dispatchCount: Int { lock.withLock { sentCount } }
  var ownerships: [HIDInputOwnership] { lock.withLock { recordedOwnerships } }
  var suppressOutput: Bool {
    get { lock.withLock { suppressed } }
    set { lock.withLock { suppressed = newValue } }
  }

  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) {
    lock.withLock { sentCount += 1 }
  }

  func controllerDidStop(_ identifier: DeviceIdentifier) { lock.withLock { stoppedCount += 1 } }

  func controllerInputOwnershipChanged(
    _ ownership: HIDInputOwnership,
    for identifier: DeviceIdentifier
  ) { lock.withLock { recordedOwnerships.append(ownership) } }
}
