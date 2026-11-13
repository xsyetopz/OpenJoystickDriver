import Foundation
import OpenJoystickDriverTestSupport
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
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey
    )
    let physicalDevice = PhysicalDevice(
      vendorID: missingVendorID ? nil : 0x1234,
      productID: missingVendorID ? 0x5678 : nil,
      physicalLocationIdentifier: nil
    )

    await manager.handleHIDEvent(
      .connected(
        connection: HIDDeviceConnection(
          physicalDevice: physicalDevice,
          routingAddress: .ioKit(locationID: 91, interfaceNumber: nil)
        ),
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
    let manager = DeviceManager(dispatcher: dispatcher, installationKey: testPortKeyInstallationKey)
    let identifier = LogicalControllerID(vendorID: 0x1234, productID: 0x5678, locationID: 77)
    let physicalDevice = PhysicalDevice(
      vendorID: identifier.model.vendorID,
      productID: identifier.model.productID,
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
    let connection = HIDDeviceConnection(
      physicalDevice: physicalDevice,
      routingAddress: .ioKit(locationID: 77, interfaceNumber: nil)
    )
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
      .ownershipChanged(
        address: .ioKit(locationID: 77, interfaceNumber: nil),
        ownership: .ownedByAnotherClient
      )
    )
    #expect(await first.isActive == false)
    #expect(dispatcher.stops == 1)
    await manager.handleHIDEvent(
      .ownershipChanged(
        address: .ioKit(locationID: 77, interfaceNumber: nil),
        ownership: .ownedByAnotherClient
      )
    )
    #expect(dispatcher.stops == 1)
    await manager.handleHIDEvent(
      .ownershipChanged(
        address: .ioKit(locationID: 77, interfaceNumber: nil),
        ownership: .exclusive
      )
    )
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
  func competingOwnerIsVisibleWithoutStartingOrPublishingPipeline() async throws {
    let dispatcher = OwnershipOutputRecorder()
    let manager = DeviceManager(dispatcher: dispatcher, installationKey: testPortKeyInstallationKey)
    let identifier = LogicalControllerID(vendorID: 0x1234, productID: 0x5678, locationID: 77)
    await manager.handleHIDEvent(
      .connected(
        connection: HIDDeviceConnection(
          physicalDevice: PhysicalDevice(
            vendorID: identifier.model.vendorID,
            productID: identifier.model.productID,
            productName: "Test",
            transportProperty: "USB",
            physicalLocationIdentifier: 77,
            interfaces: [gamepadHIDInterface(host: .usb)]
          ),
          routingAddress: .ioKit(locationID: 77, interfaceNumber: nil),
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

  /// A pad OJD seizes while GameController also lists it reaches the summary as a duplicate.
  @Test(arguments: [true, false])
  func servedPadThatSystemAlsoListsIsDuplicate(_ systemListsGameController: Bool) async throws {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey
    )
    await manager.handleHIDEvent(
      .connected(
        connection: HIDDeviceConnection(
          physicalDevice: PhysicalDevice(
            vendorID: 0x1234,
            productID: 0x5678,
            productName: "Test",
            transportProperty: "USB",
            physicalLocationIdentifier: 77,
            interfaces: [gamepadHIDInterface(host: .usb)],
            systemListsGameController: systemListsGameController
          ),
          routingAddress: .ioKit(locationID: 77, interfaceNumber: nil)
        ),
        ownership: .exclusive
      )
    )
    let description = try #require(await manager.connectedDeviceDescriptions().first)
    #expect(description.physicalOwnership == .exclusiveHID)
    let risk: DuplicateExposureRisk = systemListsGameController ? .systemGameController : .none
    #expect(description.duplicateExposureRisk == risk)
    #expect(
      ControllerSummary(ApplicationServiceDeviceDescription(snapshot: description))
        .alsoListedBySystem == systemListsGameController
    )
    await manager.stop()
  }

  @Test(arguments: [HIDInputOwnership.ownedByAnotherClient, .acquisitionFailed])
  func unseizedConnectionIsRetriedAndRestartsWhenSeizeSucceeds(
    _ initial: HIDInputOwnership
  ) async throws {
    let backend = ClaimRecordingHIDAccessBackend()
    let dispatcher = OwnershipOutputRecorder()
    let manager = DeviceManager(
      dispatcher: dispatcher,
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    let identifier = LogicalControllerID(vendorID: 0x1234, productID: 0x5678, locationID: 77)
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: identifier.model.vendorID,
        productID: identifier.model.productID,
        productName: "Test",
        transportProperty: "USB",
        physicalLocationIdentifier: 77,
        interfaces: [gamepadHIDInterface(host: .usb)]
      ),
      routingAddress: .ioKit(locationID: 77, interfaceNumber: nil)
    )
    await manager.handleHIDEvent(.connected(connection: connection, ownership: initial))
    let first = try #require(await manager.pipelines[identifier])

    await manager.retryHIDInputClaims()
    #expect(await backend.retriedLocations() == [77])

    await manager.handleHIDEvent(
      .ownershipChanged(
        address: .ioKit(locationID: 77, interfaceNumber: nil),
        ownership: .exclusive
      )
    )
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
  func exclusiveHIDOwnershipIsReportedByLiveManagerAndPayload() async throws {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey
    )
    let identifier = LogicalControllerID(vendorID: 0x1234, productID: 0x5678, locationID: 77)
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: identifier.model.vendorID,
        productID: identifier.model.productID,
        productName: "Test",
        transportProperty: "USB",
        physicalLocationIdentifier: 77,
        interfaces: [gamepadHIDInterface(host: .usb)]
      ),
      routingAddress: .ioKit(locationID: 77, interfaceNumber: nil)
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
      .ownershipChanged(
        address: .ioKit(locationID: 77, interfaceNumber: nil),
        ownership: .ownedByAnotherClient
      )
    )
    #expect(await manager.ownershipObservation(for: identifier) == .systemHIDVisible)
    let lost = await manager.connectedDeviceDescriptions()
    #expect(lost.first?.hidInputOwnership == .ownedByAnotherClient)
    #expect(lost.first?.duplicateExposureRisk == .systemHIDVisible)
    await manager.handleHIDEvent(.disconnected(connection: connection))
    #expect(await manager.ownershipObservation(for: identifier) == .unknown)
    await manager.stop()
  }

  private let descriptorBinding = ProtocolBinding(
    protocolID: .hidDescriptor,
    variant: nil,
    accessBackend: .hid,
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
    #expect(info.ownershipObservation == .systemHIDVisible)
  }

  @Test
  func inputReadRequirementFollowsDiscoverySource() {
    #expect(DeviceManager.DiscoverySource.hid.requiresInputRead)
    #expect(!DeviceManager.DiscoverySource.rawUSB(route: .rawUSB).requiresInputRead)
    #expect(!DeviceManager.DiscoverySource.rawUSB(route: .usbExtension).requiresInputRead)
  }

  @Test(arguments: [
    (DeviceManager.DiscoverySource.hid, ControllerOwnershipObservation.systemHIDVisible),
    (
      DeviceManager.DiscoverySource.rawUSB(route: .rawUSB),
      ControllerOwnershipObservation.exclusiveRawUSB
    ),
    (
      DeviceManager.DiscoverySource.rawUSB(route: .usbExtension),
      ControllerOwnershipObservation.extensionOwnedUSB
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
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey
    )
    let identifier = LogicalControllerID(vendorID: 0x1234, productID: 0x5678)

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
      physicalOwnership: .systemHIDVisible,
      duplicateExposureRisk: .systemHIDVisible,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system
    )

    let decoded = try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONEncoder().encode(description)
    )

    #expect(decoded.physicalOwnership == .systemHIDVisible)
    #expect(decoded.duplicateExposureRisk == .systemHIDVisible)
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

  func dispatch(_: ControllerEvent, from _: LogicalControllerID) {
    lock.withLock { sentCount += 1 }
  }

  func activateOutput(for _: LogicalControllerID) { lock.withLock { sentCount += 1 } }

  func controllerDidStop(_: LogicalControllerID) { lock.withLock { stoppedCount += 1 } }

  func controllerInputOwnershipChanged(
    _ ownership: HIDInputOwnership,
    for _: LogicalControllerID
  ) { lock.withLock { recordedOwnerships.append(ownership) } }
}
