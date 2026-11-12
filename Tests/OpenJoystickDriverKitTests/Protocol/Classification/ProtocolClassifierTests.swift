import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ProtocolClassifierTests {
  private static let catalog = DeviceCatalog()

  // MARK: - Vocabulary

  @Test
  func bindingReasonsAreTheTypedReasonIDs() {
    #expect(
      ProtocolBindingReason.allCases.map(\.rawValue) == [
        "NoProtocolMatch", "AmbiguousProtocolMatch", "InterfaceContractMismatch",
        "DescriptorContractMismatch", "UnsupportedProtocolVariant", "UnsupportedTransportVariant",
        "VirtualProfileUnavailable", "DeviceInUse", "ConfigurationUnreadable", "BootloaderIdentity",
        "NoModeMatched", "NoControllerLinked",
      ]
    )
  }

  @Test
  func everyCatalogRecordDecodesToAnImplementedFamilyVariant() throws {
    for model in Self.catalog.rawUSBModels + Self.catalog.hidModels {
      let record = try #require(Self.catalog.record(for: model))
      if let variant = record.physicalProtocolVariant {
        #expect(record.physicalProtocolID.variants.contains(variant))
        // GameSir's `usb` names its vendor USB protocol, not the host transport.
        #expect(
          record.physicalProtocolID == .vendorGameSir
            || (variant != .usb && variant != .bluetoothClassic)
        )
      }
    }
  }

  // MARK: - Catalog records

  @Test
  func catalogRecordBindsOnARawUSBBackend() throws {
    for backend in [DeviceAccessBackend.rawUSB, .usbExtension] {
      let result = classify(device(0x045E, 0x028E, interfaces: []), backend: backend)
      let binding = try bound(result)
      #expect(binding.protocolID == .xboxXUSB)
      #expect(binding.variant == .wired)
      #expect(binding.accessBackend == backend)
      #expect(binding.interfaceNumber == 0)
      #expect(binding.rule == .catalogRecord)
      #expect(binding.matchedPredicates == [.catalogIdentity, .catalogAccessPath])
      #expect(binding.record == Self.catalog.record(for: model(0x045E, 0x028E)))
    }
  }

  @Test
  func catalogRecordCarriesStoredVariants() throws {
    let receiver = try bound(classify(device(0x045E, 0x0719, interfaces: []), backend: .rawUSB))
    #expect(receiver.protocolID == .xboxXUSB)
    #expect(receiver.variant == .receiver)

    let gameSir = try bound(classify(device(0x3537, 0x1003, interfaces: []), backend: .rawUSB))
    #expect(gameSir.protocolID == .vendorGameSir)
    #expect(gameSir.variant == .usb)

    let steamDongle = try bound(
      classify(device(0x28DE, 0x1142, interfaces: [hidInterface(host: .usb)]), backend: .hid)
    )
    #expect(steamDongle.protocolID == .valveSteamController)
    #expect(steamDongle.variant == .dongle)
    let steamWired = try bound(
      classify(device(0x28DE, 0x1102, interfaces: [hidInterface(host: .usb)]), backend: .hid)
    )
    #expect(steamWired.variant == .wired)
  }

  @Test
  func rawUSBGIPRecordDerivesTheUSBVariant() throws {
    let binding = try bound(
      classify(device(0x045E, 0x02EA, interfaces: []), backend: .usbExtension)
    )
    #expect(binding.protocolID == .xboxGIP)
    #expect(binding.variant == .usb)
    #expect(binding.matchedPredicates.contains(.catalogIdentity))
  }

  @Test
  func hidRecordDerivesTheTransportVariantFromTheHostTransport() throws {
    let usb = try bound(
      classify(device(0x054C, 0x09CC, interfaces: [hidInterface(host: .usb)]), backend: .hid)
    )
    #expect(usb.protocolID == .sonyDualShock4)
    #expect(usb.variant == .usb)
    #expect(usb.matchedPredicates == [.catalogIdentity, .catalogAccessPath, .hostTransport])

    let bluetooth = try bound(
      classify(
        device(0x054C, 0x09CC, interfaces: [hidInterface(host: .bluetoothClassic)]),
        backend: .hid
      )
    )
    #expect(bluetooth.variant == .bluetoothClassic)
  }

  /// Sixaxis, DS4, DualSense and Switch drivers are built for one transport variant, so no
  /// driver exists for an unknown or unimplemented host transport.
  @Test(
    arguments: [
      (0x054C, 0x0268, .sonySixaxis), (0x054C, 0x09CC, .sonyDualShock4),
      (0x054C, 0x0CE6, .sonyDualSense), (0x057E, 0x2009, .nintendoSwitch1),
    ] as [(UInt16, UInt16, PhysicalProtocolID)]
  )
  func hidRecordWithUnknownOrUnimplementedHostTransportIsUnsupported(
    vendorID: UInt16,
    productID: UInt16,
    family: PhysicalProtocolID
  ) {
    let expected = rejection(
      .unsupportedTransportVariant,
      family,
      record: recordID(vendorID, productID)
    )
    for host in [nil, PhysicalTransport.bluetoothLE, .proprietaryRadioReceiver] {
      #expect(
        classify(
          device(vendorID, productID, interfaces: [hidInterface(host: host)]),
          backend: .hid
        ) == expected
      )
    }
    #expect(classify(device(vendorID, productID, interfaces: []), backend: .hid) == expected)
  }

  /// Bluetooth LE is the Switch 2 GATT link; a Switch 2 controller has no Classic link.
  @Test
  func switch2BindsUSBAndBluetoothLEButNotBluetoothClassic() throws {
    for host in [PhysicalTransport.usb, .bluetoothLE] {
      let binding = try bound(
        classify(device(0x057E, 0x2069, interfaces: [hidInterface(host: host)]), backend: .hid)
      )
      #expect(binding.variant == (host == .usb ? .usb : .bluetoothLE))
    }
    let classic = classify(
      device(0x057E, 0x2069, interfaces: [hidInterface(host: .bluetoothClassic)]),
      backend: .hid
    )
    let expected = rejection(
      .unsupportedTransportVariant,
      .nintendoSwitch2,
      record: recordID(0x057E, 0x2069)
    )
    #expect(classic == expected)
  }

  /// A Bluetooth-only Switch pad (PDP `0e6f:0186`, PowerA `0f0d:00f6`) only charges over USB.
  @Test(arguments: [(0x0E6F, 0x0186), (0x0F0D, 0x00F6)] as [(UInt16, UInt16)])
  func bluetoothOnlySwitchPadBindsBluetoothClassicButNotUSB(identity: (UInt16, UInt16)) throws {
    let (vendorID, productID) = identity
    let classic = try bound(
      classify(
        device(vendorID, productID, interfaces: [hidInterface(host: .bluetoothClassic)]),
        backend: .hid
      )
    )
    #expect(classic.protocolID == .nintendoSwitch1)
    #expect(classic.variant == .bluetoothClassic)
    let usb = classify(
      device(vendorID, productID, interfaces: [hidInterface(host: .usb)]),
      backend: .hid
    )
    let expected = rejection(
      .unsupportedTransportVariant,
      .nintendoSwitch1,
      record: recordID(vendorID, productID)
    )
    #expect(usb == expected)
  }

  @Test(arguments: [(0x3537, 0x100A), (0x11C1, 0x5600), (0x2E95, 0x434D)] as [(UInt16, UInt16)])
  func singleContractHIDRecordsNeedNoTransportVariant(identity: (UInt16, UInt16)) throws {
    let record = try #require(Self.catalog.record(for: model(identity.0, identity.1)))
    #expect(record.physicalProtocolID == .hidDescriptor)
    let generic = try bound(
      classify(
        device(identity.0, identity.1, interfaces: [hidInterface(host: nil, descriptor: gamepad)]),
        backend: .hid
      )
    )
    #expect(generic.protocolID == .hidDescriptor)
    #expect(generic.variant == nil)
    #expect(generic.rule == .catalogRecord)
    #expect(
      generic.matchedPredicates == [.catalogIdentity, .catalogAccessPath, .hidDescriptorContract]
    )
    #expect(generic.record == record)
  }

  @Test(arguments: [(0x3537, 0x100A), (0x11C1, 0x5600), (0x2E95, 0x434D)] as [(UInt16, UInt16)])
  func catalogHIDDescriptorRecordsStillRequireTheDescriptorContract(identity: (UInt16, UInt16)) {
    for interfaces in [
      [hidInterface(host: .usb, descriptor: nil)],
      [hidInterface(host: .usb, descriptor: vendorOnly)], [],
    ] {
      #expect(
        classify(device(identity.0, identity.1, interfaces: interfaces), backend: .hid)
          == rejection(
            .descriptorContractMismatch,
            .hidDescriptor,
            record: recordID(identity.0, identity.1)
          )
      )
    }
  }

  /// #63: the GameSir G7 Pro dongle exposes a HID gamepad interface and a HID interface with a
  /// vendor usage; the bundled record's `HIDDescriptor` mode binds the gamepad one.
  @Test
  func theGameSirDongleBindsItsHIDDescriptorMode() async throws {
    func hid(
      _ number: UInt8,
      _ usage: HIDUsageSignature,
      _ descriptor: Data?
    )
      -> PhysicalInterfaceSignature
    {
      PhysicalInterfaceSignature(
        interfaceNumber: number,
        interfaceClass: 3,
        interfaceSubclass: 0,
        interfaceProtocol: 0,
        hostTransport: .usb,
        accessBackend: .hid,
        hidLayout: HIDLayoutSummary(primaryUsage: usage, reportDescriptor: descriptor)
      )
    }
    let dongle = device(
      0x3537,
      0x1022,
      interfaces: [
        hid(0, HIDUsageSignature(usagePage: 1, usage: 5), gamepad),
        hid(1, HIDUsageSignature(usagePage: 0xFF00, usage: 1), vendorOnly),
      ]
    )
    let selection = await ProtocolDriverRegistry().selectMode(
      of: model(0x3537, 0x1022),
      backend: .hid,
      reader: UnreadableModeProbeReader(),
      device: dongle
    )
    #expect(selection == .matched("hid"))
    let binding = try bound(
      ProtocolDriverRegistry().classify(dongle, backend: .hid, modeID: "hid")
    )
    #expect(binding.protocolID == .hidDescriptor)
    #expect(binding.rule == .catalogRecord)
  }

  @Test
  func transportMismatchWithTheRecordIsUnsupportedAndNeverGenericHID() throws {
    // A raw-USB record observed through IOHID with no usable HID interface.
    #expect(
      classify(
        device(0x045E, 0x028E, interfaces: [hidInterface(host: .usb, descriptor: vendorOnly)]),
        backend: .hid
      ) == rejection(.interfaceContractMismatch, .xboxXUSB, record: "045e-028e")
    )
    // With a gamepad descriptor the HIDDescriptor rule serves it and names the record.
    let fallback = try bound(
      classify(
        device(0x045E, 0x028E, interfaces: [hidInterface(host: .usb, descriptor: gamepad)]),
        backend: .hid
      )
    )
    #expect(fallback.rule == .hidDescriptor)
    #expect(fallback.inputMapping?.unfitRecordID == "045e-028e")
    // A HID record observed through raw USB.
    for backend in [DeviceAccessBackend.rawUSB, .usbExtension] {
      #expect(
        classify(device(0x054C, 0x09CC, interfaces: []), backend: backend)
          == rejection(.unsupportedTransportVariant, .sonyDualShock4, record: "054c-09cc")
      )
    }
  }

  /// One VID:PID can ship XUSB or GIP firmware; the Xbox interface it exposes decides.
  @Test
  func xboxRecordYieldsToTheOtherXboxFamilysObservedSignature() throws {
    let asGIP = try bound(
      classify(device(0x045E, 0x028E, interfaces: [gipInterface()]), backend: .rawUSB)
    )
    #expect(asGIP.protocolID == .xboxGIP)
    #expect(asGIP.rule == .interfaceSignature)
    #expect(asGIP.record == nil)

    let asXUSB = try bound(
      classify(
        device(0x045E, 0x02EA, interfaces: [usbInterface(0, 0xFF, 0x5D, 0x01)]),
        backend: .rawUSB
      )
    )
    #expect(asXUSB.protocolID == .xboxXUSB)
    #expect(asXUSB.variant == .wired)
    #expect(asXUSB.rule == .interfaceSignature)
  }

  @Test
  func xboxRecordKeepsItsFamilyWhenItsOwnSignatureIsPresent() throws {
    let interfaces = [usbInterface(0, 0xFF, 0x5D, 0x01), usbInterface(1, 0xFF, 0x47, 0xD0)]
    let binding = try bound(
      classify(device(0x045E, 0x028E, interfaces: interfaces), backend: .rawUSB)
    )
    #expect(binding.protocolID == .xboxXUSB)
    #expect(binding.rule == .catalogRecord)
  }

  let gamepad = Data(GamepadHIDDescriptor.descriptor)
  let vendorOnly = Data([
    0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x75, 0x08, 0x95, 0x3F, 0x81, 0x02, 0xC0,
  ])

  func classify(_ device: PhysicalDevice, backend: DeviceAccessBackend) -> ProtocolClassification {
    ProtocolClassifier.classify(device, backend: backend, catalog: Self.catalog)
  }

  func bound(_ result: ProtocolClassification) throws -> ProtocolBinding {
    guard case .bound(let binding) = result else {
      Issue.record("expected a binding, got \(result)")
      throw BindingMissing()
    }
    return binding
  }

  private struct BindingMissing: Error {}

  private func model(_ vendorID: UInt16, _ productID: UInt16) -> ControllerModelID {
    ControllerModelID(vendorID: vendorID, productID: productID)
  }

  private func device(
    _ vendorID: UInt16,
    _ productID: UInt16,
    interfaces: [PhysicalInterfaceSignature]
  ) -> PhysicalDevice {
    PhysicalDevice(vendorID: vendorID, productID: productID, interfaces: interfaces)
  }

  func unknownDevice(_ interfaces: [PhysicalInterfaceSignature]) -> PhysicalDevice {
    #expect(Self.catalog.record(for: model(0x1234, 0x5678)) == nil)
    return device(0x1234, 0x5678, interfaces: interfaces)
  }

  func usbInterface(
    _ number: UInt8,
    _ interfaceClass: UInt8,
    _ subclass: UInt8,
    _ interfaceProtocol: UInt8,
    endpoints: [PhysicalEndpointSignature]? = nil
  ) -> PhysicalInterfaceSignature {
    PhysicalInterfaceSignature(
      interfaceNumber: number,
      alternateSetting: 0,
      interfaceClass: interfaceClass,
      interfaceSubclass: subclass,
      interfaceProtocol: interfaceProtocol,
      hostTransport: .usb,
      endpoints: endpoints ?? [endpoint(0x81 + number, .in), endpoint(0x01 + number, .out)]
    )
  }

  func gipInterface() -> PhysicalInterfaceSignature { usbInterface(0, 0xFF, 0x47, 0xD0) }

  func hidInterface(host: PhysicalTransport?, descriptor: Data? = nil) -> PhysicalInterfaceSignature
  {
    PhysicalInterfaceSignature(
      interfaceClass: 0x03,
      hostTransport: host,
      accessBackend: .hid,
      hidLayout: HIDLayoutSummary(reportDescriptor: descriptor)
    )
  }

  func endpoint(
    _ address: UInt8,
    _ direction: USBEndpointDirection,
    _ transferType: USBEndpointTransferType = .interrupt
  ) -> PhysicalEndpointSignature {
    PhysicalEndpointSignature(address: address, direction: direction, transferType: transferType)
  }
}
