import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ProtocolDriverRegistryTests {
  private let registry = ProtocolDriverRegistry()

  @Test
  func everyRawUSBRowBindsItsFamilyParserOnBothRawBackends() throws {
    #expect(!registry.rawUSBModels.isEmpty)
    for model in registry.rawUSBModels {
      let record = try #require(registry.record(for: model))
      for backend in [DeviceAccessBackend.rawUSB, .usbExtension] {
        let binding = try bound(identityOnly(model), backend: backend)
        #expect(binding.protocolID == record.physicalProtocolID, "\(model)")
        let driver = try registry.makeDriver(
          for: binding,
          model: model,
          claimed: USBTransportResolution(profile: record.transportProfile)
        ).get()
        #expect(Self.driver(driver, belongsTo: binding.protocolID), "\(model)")
      }
    }
  }

  @Test
  func rawUSBIdentityFactsClassifyLikeFullInterfaceFacts() {
    for model in registry.rawUSBModels {
      let full = PhysicalDevice(
        vendorID: model.vendorID,
        productID: model.productID,
        interfaces: [PhysicalInterfaceSignature(accessBackend: .rawUSB)]
      )
      #expect(
        registry.classify(identityOnly(model), backend: .rawUSB)
          == registry.classify(full, backend: .rawUSB),
        "\(model)"
      )
    }
  }

  @Test
  func everyHIDRowBindsItsFamilyParserOverItsDefaultHost() throws {
    #expect(!registry.hidModels.isEmpty)
    for model in registry.hidModels {
      let record = try #require(registry.record(for: model))
      guard !record.isIdle else { continue }
      let binding = try bound(
        hidDevice(model, gamepadHIDInterface(host: defaultHost(of: record)))
      )
      #expect(binding.protocolID == record.physicalProtocolID, "\(model)")
      let driver = try registry.makeDriver(for: binding, model: model, claimed: nil).get()
      #expect(Self.driver(driver, belongsTo: binding.protocolID), "\(model)")
    }
  }

  @Test(arguments: [(0x054C, 0x09CC), (0x054C, 0x0CE6), (0x057E, 0x2009)])
  func sonyAndNintendoRowsTakeTheirVariantFromTheHostTransport(vendorID: Int, productID: Int) throws
  {
    let model = ControllerModelID(vendorID: UInt16(vendorID), productID: UInt16(productID))
    let usb = try bound(hidDevice(model, gamepadHIDInterface(host: .usb)))
    let bluetooth = try bound(hidDevice(model, gamepadHIDInterface(host: .bluetoothClassic)))
    #expect(usb.variant == .usb)
    #expect(bluetooth.variant == .bluetoothClassic)
  }

  @Test
  func catalogGenericHIDRowsBindOnlyWithAContractDescriptor() throws {
    let rows = [(0x3537, 0x100A), (0x11C1, 0x5600), (0x2E95, 0x434D)].map {
      ControllerModelID(vendorID: UInt16($0.0), productID: UInt16($0.1))
    }
    for model in rows {
      #expect(
        registry.classify(hidDevice(model, hostHIDInterface(.usb)), backend: .hid)
          == rejection(
            .descriptorContractMismatch,
            .hidDescriptor,
            record: recordID(
              model.vendorID,
              model.productID
            )
          ),
        "\(model)"
      )
      let binding = try bound(hidDevice(model, gamepadHIDInterface(host: .usb)))
      #expect(binding.protocolID == .hidDescriptor)
      #expect(
        try registry.makeDriver(for: binding, model: model, claimed: nil).get()
          is HIDDescriptorDriver
      )
    }
  }

  @Test
  func rawUSBRecordOverHIDFallsBackToHIDDescriptor() throws {
    let model = ControllerModelID(vendorID: 0x045E, productID: 0x02EA)
    let binding = try bound(hidDevice(model, gamepadHIDInterface(host: .usb)))
    #expect(binding.rule == .hidDescriptor)
    #expect(binding.inputMapping?.unfitRecordID == "045e-02ea")
  }

  @Test
  func sonyRowOverBluetoothLEIsAnUnsupportedTransportVariant() {
    let model = ControllerModelID(vendorID: 0x054C, productID: 0x09CC)
    #expect(
      registry.classify(
        hidDevice(model, gamepadHIDInterface(host: .bluetoothLE)),
        backend: .hid
      ) == rejection(.unsupportedTransportVariant, .sonyDualShock4, record: "054c-09cc")
    )
  }

  @Test
  func uncataloguedRawUSBHasNoProtocolMatch() {
    let model = ControllerModelID(vendorID: 0x1234, productID: 0x5678)
    #expect(
      registry.classify(identityOnly(model), backend: .rawUSB)
        == .unsupported(.noProtocolMatch)
    )
  }

  @Test
  func uncataloguedHIDBindsOnlyWhenTheDescriptorPassesTheContract() throws {
    let model = ControllerModelID(vendorID: 0x1234, productID: 0x5678)
    #expect(
      registry.classify(hidDevice(model, hostHIDInterface(.usb)), backend: .hid)
        == .unsupported(.descriptorContractMismatch)
    )
    let binding = try bound(hidDevice(model, gamepadHIDInterface(host: .usb)))
    #expect(binding.protocolID == .hidDescriptor)
    #expect(binding.record == nil)
    #expect(
      try registry.makeDriver(for: binding, model: model, claimed: nil).get()
        is HIDDescriptorDriver
    )
  }

  @Test
  func storedAndTransportVariantsConfigureTheirParsers() throws {
    let receiver = try #require(
      try catalogParser(ControllerModelID(vendorID: 0x045E, productID: 0x0719)) as? XUSBDriver
    )
    let wired = try #require(
      try catalogParser(ControllerModelID(vendorID: 0x045E, productID: 0x028E)) as? XUSBDriver
    )
    #expect(receiver.sessionPlan.requiresInputConnectionBeforeOutput)
    #expect(!wired.sessionPlan.requiresInputConnectionBeforeOutput)

    let dongle = try #require(
      try catalogParser(ControllerModelID(vendorID: 0x28DE, productID: 0x1142))
        as? SteamControllerDriver
    )
    let steam = try #require(
      try catalogParser(ControllerModelID(vendorID: 0x28DE, productID: 0x1102))
        as? SteamControllerDriver
    )
    #expect(dongle.isWirelessReceiver)
    #expect(!steam.isWirelessReceiver)

    let ds4 = ControllerModelID(vendorID: 0x054C, productID: 0x09CC)
    let ds4Bluetooth = try #require(
      try catalogParser(ds4, host: .bluetoothClassic) as? DualShock4Driver
    )
    let ds4USB = try #require(try catalogParser(ds4, host: .usb) as? DualShock4Driver)
    #expect(ds4Bluetooth.transport == .bluetooth)
    #expect(ds4USB.transport == .usb)
  }

  /// The DualShock 4 and SHIELD drivers take their model and calibration from the record
  /// parameters.
  @Test
  func recordParametersConfigureTheirDrivers() throws {
    func ds4(_ vendorID: UInt16, _ productID: UInt16) throws -> DualShock4Driver {
      try #require(
        try catalogParser(ControllerModelID(vendorID: vendorID, productID: productID))
          as? DualShock4Driver
      )
    }
    let standard = try ds4(0x054C, 0x09CC)
    #expect(standard.model == .standard)
    #expect(standard.usesFactoryCalibration)
    #expect(try ds4(0x054C, 0x05C5).model == .strikePad)
    let adapter = try ds4(0x054C, 0x0BA0)
    #expect(adapter.model == .wirelessAdapter)
    #expect(adapter.sessionPlan.requiresInputConnectionBeforeOutput)
    #expect(!(try ds4(0x0079, 0x181B).usesFactoryCalibration))

    func shield(_ productID: UInt16) throws -> NVIDIAShieldDriver {
      try #require(
        try catalogParser(ControllerModelID(vendorID: 0x0955, productID: productID))
          as? NVIDIAShieldDriver
      )
    }
    #expect(try shield(0x7210).outputCapabilities == .dualMainRumble)
    #expect(try shield(0x7214).outputCapabilities == .none)
  }

  /// The generic HID driver reads the record's usage map, and the description's standard map when
  /// the record declares none.
  @Test(
    arguments: [
      (0x11C1, 0x5600, true), (0x2E95, 0x434D, true), (0x2DC8, 0x301B, true),
      (0x2DC8, 0x301D, true), (0x0079, 0x0006, true), (0x3537, 0x100A, false),
    ] as [(UInt16, UInt16, Bool)]
  )
  func recordUsageMapsSelectTheHIDUsageMap(
    vendorID: UInt16,
    productID: UInt16,
    declaresMap: Bool
  ) throws {
    let model = ControllerModelID(vendorID: vendorID, productID: productID)
    let driver = try #require(try catalogParser(model) as? HIDDescriptorDriver)
    let standard = try #require(ProtocolDescription.bundled[.hidDescriptor]?.hidUsageMap)
    let recordMap = try #require(ProtocolDriverRegistry().record(for: model)).hidUsageMap
    #expect((recordMap != nil) == declaresMap)
    #expect(driver.usageMap == (recordMap ?? standard))
    #expect((driver.usageMap == standard) == !declaresMap)
  }

  /// A non-Sony DualSense record selects third-party mode, and its parameters give SDL's model
  /// values.
  @Test(
    arguments: [
      (0x0F0D, 0x0184, [], false, false), (0x1532, 0x100B, [.sensors, .touchpad], false, false),
      (0x1532, 0x100C, [.sensors, .touchpad], false, true),
      (0x1532, 0x1012, [.touchpad], false, false), (0x1532, 0x1024, [.touchpad], false, false),
      (0x1532, 0x1026, [.touchpad], false, true),
      (0x3285, 0x0D18, [], true, true), (0x3285, 0x0D19, [], true, false),
    ] as [(UInt16, UInt16, DualSenseFeatures, Bool, Bool)]
  )
  func recordParametersDescribeTheThirdPartyDualSense(
    vendorID: UInt16,
    productID: UInt16,
    unprobedFeatures: DualSenseFeatures,
    forcesVibration: Bool,
    isDongle: Bool
  ) throws {
    let driver = try #require(
      try catalogParser(ControllerModelID(vendorID: vendorID, productID: productID))
        as? DualSenseDriver
    )
    let model = try #require(driver.thirdParty)
    #expect(model.unprobedFeatures == unprobedFeatures)
    #expect(model.usesAlternateReportUnprobed == !unprobedFeatures.isEmpty)
    #expect(model.forcesVibration == forcesVibration)
    #expect(model.isDongle == isDongle)
  }

  @Test
  func sonyDualSenseRecordsRunInSonyMode() throws {
    for productID: UInt16 in [0x0CE6, 0x0DF2, 0x0E5F] {
      let driver = try #require(
        try catalogParser(ControllerModelID(vendorID: 0x054C, productID: productID))
          as? DualSenseDriver
      )
      #expect(driver.thirdParty == nil)
    }
  }

  @Test
  func everyFamilyAndVariantBuildsThroughTheValidatingFactory() throws {
    var built: Set<String> = []
    for model in registry.rawUSBModels {
      let record = try #require(registry.record(for: model))
      let device = PhysicalDevice(
        vendorID: model.vendorID,
        productID: model.productID,
        configurationValue: 1,
        interfaces: [claimedInterface(record)]
      )
      let binding = try bound(device, backend: .rawUSB)
      let driver = try registry.makeDriver(
        for: binding,
        model: model,
        claimed: USBTransportResolution(profile: record.transportProfile, physicalDevice: device)
      ).get()
      #expect(Self.driver(driver, belongsTo: binding.protocolID), "\(model)")
      built.insert(binding.id.rawValue)
    }
    for model in registry.hidModels {
      for host in [PhysicalTransport.usb, .bluetoothClassic, .bluetoothLE] {
        let device = hidDevice(model, gamepadHIDInterface(host: host))
        guard
          case .bound(let binding) = registry.classify(
            device,
            backend: .hid,
            modeID: modeID(of: device)
          )
        else {
          continue
        }
        let driver = try registry.makeDriver(for: binding, model: model, claimed: nil)
          .get()
        #expect(Self.driver(driver, belongsTo: binding.protocolID), "\(model)")
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
    let model = ControllerModelID(vendorID: 0x045E, productID: 0x02EA)
    let binding = try bound(identityOnly(model), backend: .rawUSB)
    #expect(binding.rule == .catalogRecord)
    let result = registry.makeDriver(for: binding, model: model, claimed: nil)
    guard case .failure(let reason) = result else {
      Issue.record("built a driver without claimed facts")
      return
    }
    #expect(reason == .interfaceContractMismatch)
  }

  /// The DriverKit route observes no interface facts, so a catalog row's claim has nothing to check
  /// and builds on the record's profile.
  ///
  /// Only the record vouches for the interface there.
  @Test
  func driverKitClaimWithoutObservedFactsBuildsACatalogRow() throws {
    let model = ControllerModelID(vendorID: 0x045E, productID: 0x02EA)
    let record = try #require(registry.record(for: model))
    let binding = try bound(identityOnly(model), backend: .usbExtension)
    let unobserved = USBTransportResolution(profile: record.transportProfile)
    #expect(
      try registry.makeDriver(for: binding, model: model, claimed: unobserved).get()
        is GIPDriver
    )
    let limited = USBTransportResolution(
      profile: record.transportProfile,
      physicalDevice: PhysicalDevice(interfaces: [
        PhysicalInterfaceSignature(accessBackend: .usbExtension, usbRoute: .usbExtension)
      ])
    )
    #expect(
      try registry.makeDriver(for: binding, model: model, claimed: limited).get()
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

  private func identityOnly(_ model: ControllerModelID) -> PhysicalDevice {
    PhysicalDevice(
      vendorID: model.vendorID,
      productID: model.productID
    )
  }

  private func hidDevice(
    _ model: ControllerModelID,
    _ interface: PhysicalInterfaceSignature
  ) -> PhysicalDevice {
    PhysicalDevice(
      vendorID: model.vendorID,
      productID: model.productID,
      interfaces: [interface]
    )
  }

  private func modeID(of device: PhysicalDevice) -> String? {
    guard let vendorID = device.vendorID, let productID = device.productID else { return nil }
    return registry.record(for: ControllerModelID(vendorID: vendorID, productID: productID))
      .flatMap(classificationModeID(of:))
  }

  private func bound(
    _ device: PhysicalDevice,
    backend: DeviceAccessBackend = .hid
  ) throws -> ProtocolBinding {
    let classification = registry.classify(
      device,
      backend: backend,
      modeID: modeID(of: device)
    )
    guard case .bound(let binding) = classification else {
      Issue.record("\(device.vendorID.map(String.init) ?? "?") did not bind: \(classification)")
      throw CatalogBindingFailure()
    }
    return binding
  }

  /// Whether `driver` is the parser of family `id`.
  ///
  /// A family whose description holds the input layout is decoded by a `ReportLayoutDriver` that
  /// reads that layout and advertises the description's controls.
  static func driver(_ driver: any PhysicalProtocolDriver, belongsTo id: PhysicalProtocolID) -> Bool
  {
    if let layered = driver as? LayeredInputDriver {
      return Self.driver(layered.family, belongsTo: id)
    }
    return switch id {
    case .hidDescriptor: driver is HIDDescriptorDriver
    case .hidReportLayout: driver is ReportLayoutDriver
    case .xboxXID, .nintendoSwitchInputOnly, .vendorFlydigi:
      decodesTheDescribedLayout(driver, of: id)
    case .xboxXUSB: driver is XUSBDriver
    case .xboxGIP: driver is GIPDriver
    case .sonySixaxis: driver is SixaxisDriver
    case .sonyDualShock4: driver is DualShock4Driver
    case .sonyDualSense: driver is DualSenseDriver
    case .nintendoSwitch1: driver is Switch1Driver
    case .nintendoSwitch2: driver is Switch2Driver
    case .valveSteamController: driver is SteamControllerDriver
    case .valveSteamTriton: driver is SteamTritonDriver
    case .valveSteamDeck: driver is SteamDeckDriver
    case .vendorPS3ThirdParty: driver is PS3ThirdPartyDriver
    case .vendorGameSir: driver is GameSirDriver
    case .vendorNVIDIAShield: driver is NVIDIAShieldDriver
    case .nintendoWii: driver is WiiDriver
    default: decodesTheDescribedLayout(driver, of: id)
    }
  }

  private static func decodesTheDescribedLayout(
    _ driver: any PhysicalProtocolDriver,
    of family: PhysicalProtocolID
  ) -> Bool {
    guard let layoutDriver = driver as? ReportLayoutDriver,
      let described = family.protocolDescription.inputLayouts
    else { return false }
    return layoutDriver.layouts == described
      && layoutDriver.capabilities == family.describedControls
  }
}
