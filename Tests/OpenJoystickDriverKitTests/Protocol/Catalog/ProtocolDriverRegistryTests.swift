import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ProtocolDriverRegistryTests {
  private let registry = ProtocolDriverRegistry()

  @Test
  func everyRawUSBRowBindsItsFamilyParserOnBothRawBackends() throws {
    #expect(!registry.rawUSBIdentifiers.isEmpty)
    for identifier in registry.rawUSBIdentifiers {
      let record = try #require(registry.record(for: identifier))
      for backend in [DeviceAccessBackend.ioUSBHost, .usbDriverKit] {
        let binding = try bound(identityOnly(identifier), backend: backend)
        #expect(binding.protocolID == record.physicalProtocolID, "\(identifier)")
        let driver = try registry.makeDriver(
          for: binding,
          identifier: identifier,
          claimed: USBTransportResolution(profile: record.transportProfile)
        ).get()
        #expect(Self.driver(driver, belongsTo: binding.protocolID), "\(identifier)")
      }
    }
  }

  @Test
  func rawUSBIdentityFactsClassifyLikeFullInterfaceFacts() throws {
    for identifier in registry.rawUSBIdentifiers {
      let full = PhysicalDevice(
        vendorID: identifier.controllerIdentity.vendorID,
        productID: identifier.controllerIdentity.productID,
        interfaces: [PhysicalInterfaceSignature(accessBackend: .ioUSBHost)]
      )
      #expect(
        registry.classify(identityOnly(identifier), backend: .ioUSBHost)
          == registry.classify(full, backend: .ioUSBHost),
        "\(identifier)"
      )
    }
  }

  @Test
  func everyHIDRowBindsItsFamilyParserOverUSB() throws {
    #expect(!registry.hidIdentifiers.isEmpty)
    for identifier in registry.hidIdentifiers {
      let record = try #require(registry.record(for: identifier))
      let binding = try bound(hidDevice(identifier, gamepadHIDInterface(host: .usb)))
      #expect(binding.protocolID == record.physicalProtocolID, "\(identifier)")
      let driver = try registry.makeDriver(for: binding, identifier: identifier, claimed: nil).get()
      #expect(Self.driver(driver, belongsTo: binding.protocolID), "\(identifier)")
    }
  }

  @Test(arguments: [(0x054C, 0x09CC), (0x054C, 0x0CE6), (0x057E, 0x2009)])
  func sonyAndNintendoRowsTakeTheirVariantFromTheHostTransport(vendorID: Int, productID: Int) throws
  {
    let identifier = DeviceIdentifier(vendorID: UInt16(vendorID), productID: UInt16(productID))
    let usb = try bound(hidDevice(identifier, gamepadHIDInterface(host: .usb)))
    let bluetooth = try bound(hidDevice(identifier, gamepadHIDInterface(host: .bluetoothClassic)))
    #expect(usb.variant == .usb)
    #expect(bluetooth.variant == .bluetoothClassic)
  }

  @Test
  func catalogGenericHIDRowsBindOnlyWithAContractDescriptor() throws {
    let rows = [(0x3537, 0x100A), (0x11C1, 0x5600), (0x2E95, 0x434D)].map {
      DeviceIdentifier(vendorID: UInt16($0.0), productID: UInt16($0.1))
    }
    for identifier in rows {
      #expect(
        registry.classify(hidDevice(identifier, hostHIDInterface(.usb)), backend: .ioHID)
          == rejection(
            .descriptorContractMismatch,
            .hidDescriptor,
            record: recordID(
              identifier.controllerIdentity.vendorID,
              identifier.controllerIdentity.productID
            )
          ),
        "\(identifier)"
      )
      let binding = try bound(hidDevice(identifier, gamepadHIDInterface(host: .usb)))
      #expect(binding.protocolID == .hidDescriptor)
      #expect(
        try registry.makeDriver(for: binding, identifier: identifier, claimed: nil).get()
          is HIDDescriptorDriver
      )
    }
  }

  @Test
  func rawUSBRowObservedThroughHIDIsAnUnsupportedTransportVariant() {
    let identifier = DeviceIdentifier(vendorID: 0x045E, productID: 0x02EA)
    #expect(
      registry.classify(hidDevice(identifier, gamepadHIDInterface(host: .usb)), backend: .ioHID)
        == rejection(.unsupportedTransportVariant, .xboxGIP, record: "045e-02ea")
    )
  }

  @Test
  func sonyRowOverBluetoothLEIsAnUnsupportedTransportVariant() {
    let identifier = DeviceIdentifier(vendorID: 0x054C, productID: 0x09CC)
    #expect(
      registry.classify(
        hidDevice(identifier, gamepadHIDInterface(host: .bluetoothLE)),
        backend: .ioHID
      ) == rejection(.unsupportedTransportVariant, .sonyDualShock4, record: "054c-09cc")
    )
  }

  @Test
  func uncataloguedRawUSBHasNoProtocolMatch() {
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)
    #expect(
      registry.classify(identityOnly(identifier), backend: .ioUSBHost)
        == .unsupported(.noProtocolMatch)
    )
  }

  @Test
  func uncataloguedHIDBindsOnlyWhenTheDescriptorPassesTheContract() throws {
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)
    #expect(
      registry.classify(hidDevice(identifier, hostHIDInterface(.usb)), backend: .ioHID)
        == .unsupported(.descriptorContractMismatch)
    )
    let binding = try bound(hidDevice(identifier, gamepadHIDInterface(host: .usb)))
    #expect(binding.protocolID == .hidDescriptor)
    #expect(binding.record == nil)
    #expect(
      try registry.makeDriver(for: binding, identifier: identifier, claimed: nil).get()
        is HIDDescriptorDriver
    )
  }

  @Test
  func storedAndTransportVariantsConfigureTheirParsers() throws {
    let receiver = try #require(
      try catalogParser(DeviceIdentifier(vendorID: 0x045E, productID: 0x0719)) as? XUSBDriver
    )
    let wired = try #require(
      try catalogParser(DeviceIdentifier(vendorID: 0x045E, productID: 0x028E)) as? XUSBDriver
    )
    #expect(receiver.sessionPlan.requiresInputConnectionBeforeOutput)
    #expect(!wired.sessionPlan.requiresInputConnectionBeforeOutput)

    let dongle = try #require(
      try catalogParser(DeviceIdentifier(vendorID: 0x28DE, productID: 0x1142))
        as? SteamControllerDriver
    )
    let steam = try #require(
      try catalogParser(DeviceIdentifier(vendorID: 0x28DE, productID: 0x1102))
        as? SteamControllerDriver
    )
    #expect(dongle.isWirelessReceiver)
    #expect(!steam.isWirelessReceiver)

    let ds4 = DeviceIdentifier(vendorID: 0x054C, productID: 0x09CC)
    let ds4Bluetooth = try #require(
      try catalogParser(ds4, host: .bluetoothClassic) as? DualShock4Driver
    )
    let ds4USB = try #require(try catalogParser(ds4, host: .usb) as? DualShock4Driver)
    #expect(ds4Bluetooth.transport == .bluetooth)
    #expect(ds4USB.transport == .usb)
  }

  @Test
  func everyFamilyAndVariantBuildsThroughTheValidatingFactory() throws {
    var built: Set<String> = []
    for identifier in registry.rawUSBIdentifiers {
      let record = try #require(registry.record(for: identifier))
      let device = PhysicalDevice(
        vendorID: identifier.controllerIdentity.vendorID,
        productID: identifier.controllerIdentity.productID,
        configurationValue: 1,
        interfaces: [claimedInterface(record)]
      )
      let binding = try bound(device, backend: .ioUSBHost)
      let driver = try registry.makeDriver(
        for: binding,
        identifier: identifier,
        claimed: USBTransportResolution(profile: record.transportProfile, physicalDevice: device)
      ).get()
      #expect(Self.driver(driver, belongsTo: binding.protocolID), "\(identifier)")
      built.insert(binding.id.rawValue)
    }
    for identifier in registry.hidIdentifiers {
      for host in [PhysicalTransport.usb, .bluetoothClassic] {
        let device = hidDevice(identifier, gamepadHIDInterface(host: host))
        guard case .bound(let binding) = registry.classify(device, backend: .ioHID) else {
          continue
        }
        let driver = try registry.makeDriver(for: binding, identifier: identifier, claimed: nil)
          .get()
        #expect(Self.driver(driver, belongsTo: binding.protocolID), "\(identifier)")
        built.insert(binding.id.rawValue)
      }
    }
    let registered = PhysicalProtocolID.allCases.flatMap { id in
      id.variants.isEmpty
        ? [ProtocolBindingID(id, variant: nil).rawValue]
        : id.variants.map { ProtocolBindingID(id, variant: $0).rawValue }
    }
    #expect(built == Set(registered))
  }

  @Test
  func catalogRawUSBRowWithoutAClaimHasNoDriver() throws {
    let identifier = DeviceIdentifier(vendorID: 0x045E, productID: 0x02EA)
    let binding = try bound(identityOnly(identifier), backend: .ioUSBHost)
    #expect(binding.rule == .catalogRecord)
    let result = registry.makeDriver(for: binding, identifier: identifier, claimed: nil)
    guard case .failure(let reason) = result else {
      Issue.record("built a driver without claimed facts")
      return
    }
    #expect(reason == .interfaceContractMismatch)
  }

  /// The DriverKit route observes no interface facts, so a catalog row's claim has nothing to
  /// check and builds on the record's profile. Only the record vouches for the interface there.
  @Test
  func driverKitClaimWithoutObservedFactsBuildsACatalogRow() throws {
    let identifier = DeviceIdentifier(vendorID: 0x045E, productID: 0x02EA)
    let record = try #require(registry.record(for: identifier))
    let binding = try bound(identityOnly(identifier), backend: .usbDriverKit)
    let unobserved = USBTransportResolution(profile: record.transportProfile)
    #expect(
      try registry.makeDriver(for: binding, identifier: identifier, claimed: unobserved).get()
        is GIPDriver
    )
    let limited = USBTransportResolution(
      profile: record.transportProfile,
      physicalDevice: PhysicalDevice(interfaces: [
        PhysicalInterfaceSignature(accessBackend: .usbDriverKit, usbRoute: .usbDriverKit)
      ])
    )
    #expect(
      try registry.makeDriver(for: binding, identifier: identifier, claimed: limited).get()
        is GIPDriver
    )
  }

  /// The record's claimed interface as its configuration descriptor reports it when the family
  /// contract holds: the family's class triple and exactly the profile's interrupt endpoints.
  private func claimedInterface(_ record: DeviceRuntimeProfile) -> PhysicalInterfaceSignature {
    let profile = record.transportProfile
    let variant = record.physicalProtocolVariant ?? .usb
    let signature = ProtocolClassifier.signatures.first {
      $0.protocolID == record.physicalProtocolID && $0.variant == variant
    }
    return PhysicalInterfaceSignature(
      interfaceNumber: profile.interfaceNumber,
      alternateSetting: profile.alternateSetting,
      interfaceClass: signature?.interfaceClass ?? 0xFF,
      interfaceSubclass: signature?.interfaceSubclass ?? 0x00,
      interfaceProtocol: signature?.interfaceProtocol ?? 0x00,
      endpoints: [
        PhysicalEndpointSignature(
          address: profile.inputEndpoint,
          direction: .in,
          transferType: .interrupt
        ),
        PhysicalEndpointSignature(
          address: profile.outputEndpoint,
          direction: .out,
          transferType: .interrupt
        ),
      ]
    )
  }

  private func identityOnly(_ identifier: DeviceIdentifier) -> PhysicalDevice {
    PhysicalDevice(
      vendorID: identifier.controllerIdentity.vendorID,
      productID: identifier.controllerIdentity.productID
    )
  }

  private func hidDevice(
    _ identifier: DeviceIdentifier,
    _ interface: PhysicalInterfaceSignature
  ) -> PhysicalDevice {
    PhysicalDevice(
      vendorID: identifier.controllerIdentity.vendorID,
      productID: identifier.controllerIdentity.productID,
      interfaces: [interface]
    )
  }

  private func bound(
    _ device: PhysicalDevice,
    backend: DeviceAccessBackend = .ioHID
  ) throws -> ProtocolBinding {
    let classification = registry.classify(device, backend: backend)
    guard case .bound(let binding) = classification else {
      Issue.record("\(device.vendorID.map(String.init) ?? "?") did not bind: \(classification)")
      throw CatalogBindingFailure()
    }
    return binding
  }

  static func driver(_ driver: any PhysicalProtocolDriver, belongsTo id: PhysicalProtocolID) -> Bool
  {
    switch id {
    case .hidDescriptor: driver is HIDDescriptorDriver
    case .xboxXID: driver is XIDDriver
    case .xboxXUSB: driver is XUSBDriver
    case .xboxGIP: driver is GIPDriver
    case .sonySixaxis: driver is SixaxisDriver
    case .sonyDualShock4: driver is DualShock4Driver
    case .sonyDualSense: driver is DualSenseDriver
    case .nintendoSwitch1: driver is Switch1Driver
    case .valveSteamController: driver is SteamControllerDriver
    case .vendorFlydigi: driver is FlydigiDriver
    case .vendorGameSir: driver is GameSirDriver
    case .genericByteLayout: driver is ByteLayoutDriver
    }
  }
}
