import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct OwnershipObservationTests {
  @Test
  func physicalDevicePreservesObservedManufacturerAndLeavesUnknownNil() {
    let observed = PhysicalDevice(vendorID: 0x054C, manufacturer: "Sony Interactive Entertainment")
    let unknown = PhysicalDevice(vendorID: 0x054C)

    #expect(observed.manufacturer == "Sony Interactive Entertainment")
    #expect(unknown.manufacturer == nil)
  }

  @Test(arguments: [true, false])
  func missingHIDIdentifiersAreSkippedWithoutInventingZero(_ missingVendorID: Bool) async {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let physicalDevice = PhysicalDevice(
      vendorID: missingVendorID ? nil : 0x1234,
      productID: missingVendorID ? 0x5678 : nil,
      physicalLocationIdentifier: nil
    )

    await manager.handleHIDEvent(
      .connected(
        connection: HIDDeviceConnection(physicalDevice: physicalDevice, routingLocationID: 91),
        ownership: .exclusive
      )
    )

    #expect(await manager.connectedDeviceDescriptions().isEmpty)
    #expect(await manager.deviceInfos.isEmpty)
    #expect(await manager.pipelines.isEmpty)
    await manager.stop()
  }

  @Test
  func ownershipLossStopsOutputAndReacquisitionUsesFreshState() async throws {
    let dispatcher = OwnershipOutputRecorder()
    let manager = DeviceManager(dispatcher: dispatcher)
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678, locationID: 77)
    let physicalDevice = PhysicalDevice(
      vendorID: identifier.controllerIdentity.vendorID,
      productID: identifier.controllerIdentity.productID,
      manufacturer: "Observed manufacturer",
      productName: "Test",
      transportProperty: "USB",
      physicalLocationIdentifier: nil,
      interfaces: [
        PhysicalInterfaceSignature(
          hostTransport: .usb,
          hidLayout: HIDLayoutSummary(
            hasGamePadOrJoystickCollection: true,
            hasUsableElements: true,
            primaryUsage: HIDUsageSignature(usagePage: 1, usage: 5),
            reportDescriptor: Data(GamepadHIDDescriptor.descriptor),
            reports: [PhysicalHIDReportSignature(kind: .input, reportIDs: [1])]
          )
        )
      ]
    )
    let connection = HIDDeviceConnection(physicalDevice: physicalDevice, routingLocationID: 77)
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    #expect(await manager.deviceInfos[identifier]?.physicalDevice == physicalDevice)
    #expect(
      await manager.deviceInfos[identifier]?.physicalDevice?.manufacturer == "Observed manufacturer"
    )
    #expect(physicalDevice.physicalLocationIdentifier == nil)
    let hidInterface = try #require(physicalDevice.interfaces?.first)
    #expect(hidInterface.accessBackend == nil)
    #expect(
      hidInterface.hidLayout?.descriptorFingerprint
        == "0f776a810f493f1f40fafdf98f2ce3a57a132ba1007e685d45167a97df075af3"
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
    #expect(await manager.deviceInfos[identifier]?.physicalDevice == physicalDevice)
    #expect(
      await manager.deviceInfos[identifier]?.physicalDevice?.manufacturer == "Observed manufacturer"
    )
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
        connection: HIDDeviceConnection(
          physicalDevice: PhysicalDevice(
            vendorID: identifier.controllerIdentity.vendorID,
            productID: identifier.controllerIdentity.productID,
            productName: "Test",
            transportProperty: "USB",
            physicalLocationIdentifier: 77,
            interfaces: [gamepadHIDInterface(host: .usb)]
          ),
          routingLocationID: 77,
        ),
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

  @Test(arguments: [HIDInputOwnership.ownedByAnotherClient, .acquisitionFailed])
  func unseizedConnectionIsRetriedAndRestartsWhenTheSeizeSucceeds(
    _ initial: HIDInputOwnership
  ) async throws {
    let backend = ClaimRecordingHIDAccessBackend()
    let dispatcher = OwnershipOutputRecorder()
    let manager = DeviceManager(dispatcher: dispatcher, hidManager: HIDManager(backend: backend))
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678, locationID: 77)
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: identifier.controllerIdentity.vendorID,
        productID: identifier.controllerIdentity.productID,
        productName: "Test",
        transportProperty: "USB",
        physicalLocationIdentifier: 77,
        interfaces: [gamepadHIDInterface(host: .usb)]
      ),
      routingLocationID: 77
    )
    await manager.handleHIDEvent(.connected(connection: connection, ownership: initial))
    let first = try #require(await manager.pipelines[identifier])

    await manager.retryHIDInputClaims()
    #expect(await backend.retriedLocations() == [77])

    await manager.handleHIDEvent(.ownershipChanged(locationID: 77, ownership: .exclusive))
    let second = try #require(await manager.pipelines[identifier])
    #expect(first !== second)
    #expect(await first.isActive == false)
    #expect(await second.isActive)
    #expect(await manager.deviceInfos[identifier]?.hidInputOwnership == .exclusive)

    await manager.retryHIDInputClaims()
    #expect(await backend.retriedLocations() == [77])
    await manager.stop()
  }

  @Test
  func exclusiveHIDOwnershipIsReportedByTheLiveManagerAndPayload() async throws {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678, locationID: 77)
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: identifier.controllerIdentity.vendorID,
        productID: identifier.controllerIdentity.productID,
        productName: "Test",
        transportProperty: "USB",
        physicalLocationIdentifier: 77,
        interfaces: [gamepadHIDInterface(host: .usb)]
      ),
      routingLocationID: 77
    )
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    #expect(await manager.ownershipObservation(for: identifier) == .exclusiveHID)
    let descriptions = await manager.connectedDeviceDescriptions()
    let description = try #require(descriptions.first)
    let decoded = try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONEncoder().encode(ApplicationServiceDeviceDescription(snapshot: description))
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
    await manager.handleHIDEvent(.disconnected(connection: connection))
    #expect(await manager.ownershipObservation(for: identifier) == .unknown)
    await manager.stop()
  }

  private let descriptorBinding = ProtocolBinding(
    protocolID: .hidDescriptor,
    variant: nil,
    accessBackend: .ioHID,
    interfaceNumber: nil,
    rule: .hidDescriptor,
    matchedPredicates: [.hidDescriptorContract],
    record: nil
  )

  @Test(arguments: [HIDInputOwnership.shared, .accessDenied, .acquisitionFailed, .unknown])
  func unsuccessfulHIDAcquisitionNeverClaimsExclusiveOwnership(_ ownership: HIDInputOwnership) {
    let info = DeviceManager.DeviceInfo(
      name: "Test",
      connection: "USB",
      serialNumber: nil,
      discoverySource: .hid,
      binding: descriptorBinding,
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
    ),
  ])
  func discoverySourceDerivesOwnership(
    source: DeviceManager.DiscoverySource,
    expected: ControllerOwnershipObservation
  ) {
    let info = DeviceManager.DeviceInfo(
      name: "Test controller",
      connection: "USB",
      serialNumber: nil,
      discoverySource: source,
      binding: descriptorBinding
    )

    #expect(info.ownershipObservation == expected)
  }

  @Test
  func missingDeviceLookupIsUnknown() async {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)

    #expect(await manager.ownershipObservation(for: identifier) == .unknown)
  }

  @Test
  func deviceDescriptionRoundTripSurfacesOwnershipAndDuplicateRisk() throws {
    let description = ApplicationServiceDeviceDescription(
      name: "Test controller",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "HID",
      discoverySource: .hid,
      physicalOwnership: .nativeHIDVisible,
      duplicateExposureRisk: .nativeHIDVisible,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture
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

  func dispatch(_: ControllerEvent, labels _: ControllerButtonLabels, from _: DeviceIdentifier) {
    lock.withLock { sentCount += 1 }
  }

  func activateOutput(for _: DeviceIdentifier) { lock.withLock { sentCount += 1 } }

  func controllerDidStop(_ identifier: DeviceIdentifier) { lock.withLock { stoppedCount += 1 } }

  func controllerInputOwnershipChanged(
    _ ownership: HIDInputOwnership,
    for identifier: DeviceIdentifier
  ) { lock.withLock { recordedOwnerships.append(ownership) } }
}
