import Foundation

/// Binds observed devices to protocol drivers and constructs them.
///
/// Classification goes through ``ProtocolClassifier``; driver construction keys only
/// on the bound ``PhysicalProtocolID`` and ``PhysicalProtocolVariantID``, after the claimed
/// interface contract holds. A device that does not bind has no driver.
public final class ProtocolDriverRegistry: Sendable {
  private let catalog = DeviceCatalog()

  public init() {}

  /// Exact catalog models whose records declare raw USB access.
  public var rawUSBIdentifiers: [DeviceIdentifier] { catalog.rawUSBProfileIdentifiers }

  /// Exact catalog models whose records declare HID access; they may not advertise
  /// GamePad usage.
  public var hidIdentifiers: [DeviceIdentifier] { catalog.hidProfileIdentifiers }

  /// The exact catalog record for this identity, or nil for an uncatalogued model.
  public func record(for identifier: DeviceIdentifier) -> DeviceRuntimeProfile? {
    catalog.record(for: identifier)
  }

  /// Profile-editor capabilities for an exact catalog identity.
  ///
  /// No device is observed, so a family whose variant follows the host transport is
  /// described by its USB variant; the transport variant does not change capabilities.
  public func profileCapabilities(
    for identifier: DeviceIdentifier
  ) -> ControllerProfileCapabilities? {
    guard let record = catalog.record(for: identifier) else { return nil }
    let variant =
      record.physicalProtocolVariant
      ?? (record.physicalProtocolID.variants.contains(.usb) ? .usb : nil)
    guard
      case .success(let driver) = Self.makeUnobservedDriver(
        protocolID: record.physicalProtocolID,
        variant: variant,
        record: record,
        identifier: identifier,
        transportProfile: record.transportProfile
      )
    else { return nil }
    return ControllerProfileCapabilities(
      physicalInput: capabilities(driver.capabilities.normalized, record: record),
      physicalOutput: driver.outputCapabilities,
      buttonLabels: ControllerButtonLabels(protocolID: record.physicalProtocolID)
    )
  }

  /// Applies the record's evidenced capability corrections to the driver's declared controls.
  public func capabilities(
    _ declared: ControllerCapabilities,
    record: DeviceRuntimeProfile?
  ) -> ControllerCapabilities {
    let delta = record?.capabilityDelta ?? .none
    return ControllerCapabilities(
      controls: declared.controls.subtracting(delta.absentControls).union(delta.presentControls),
      touchContactCount: declared.touchContactCount,
      motion: declared.motion
    )
  }

  func classify(_ device: PhysicalDevice, backend: DeviceAccessBackend) -> ProtocolClassification {
    ProtocolClassifier.classify(device, backend: backend, catalog: catalog)
  }

  /// Whether passively observed USB facts carry a known Xbox USB interface or device signature.
  /// Raw-USB enumeration admits an uncatalogued device only then, so classification can report it.
  public static func carriesProtocolSignature(_ device: PhysicalDevice) -> Bool {
    ProtocolClassifier.carriesSignature(device)
  }

  /// The runtime profile a binding runs with: its catalog record or, for an interface-signature
  /// binding, the family defaults. GIP devices enumerate unconfigured on macOS (their device class
  /// is vendor-specific), so a GIP signature binding sets configuration 1 before the claim whether
  /// this attach saw the device or interface signature, like the catalogued G7 SE row. Nil for
  /// `hid.descriptor` without a record.
  func runtimeProfile(for binding: ProtocolBinding) -> DeviceRuntimeProfile? {
    if let record = binding.record { return record }
    guard binding.rule == .interfaceSignature else { return nil }
    return DeviceCatalog.familyRuntimeProfile(
      binding.protocolID,
      variant: binding.variant,
      needsSetConfiguration: binding.protocolID == .xboxGIP
    )
  }

  /// Builds the driver for a binding.
  ///
  /// A raw-USB binding needs the `claimed` facts: the profile resolved for the opened USB device
  /// and the physical device observed for it. The claimed interface contract is checked before
  /// construction, so a violating or missing claim fails with `interfaceContractMismatch` and no
  /// driver exists. A HID binding passes nil; classification already checked its descriptor
  /// contract, and it runs on the record's profile.
  ///
  /// A claim that observed no interface number has nothing to check: a catalog-record binding
  /// then builds on the claimed profile, vouched for only by its record. After discovery reads
  /// the configuration descriptor of every IOUSBHost device, that happens only on the DriverKit
  /// route, which reports no interface facts. An interface-signature binding fails closed there.
  ///
  /// `slotOrdinal` is the role's index in ``roleProfiles(for:resolution:)``; only an Xbox 360
  /// receiver reads it, as the slot whose ring light it drives.
  func makeDriver(
    for binding: ProtocolBinding,
    identifier: DeviceIdentifier,
    claimed: USBTransportResolution?,
    slotOrdinal: Int = 0
  ) -> Result<any PhysicalProtocolDriver, ProtocolBindingReason> {
    guard let record = runtimeProfile(for: binding) else {
      guard binding.protocolID == .hidDescriptor else { return .failure(.noProtocolMatch) }
      return .success(HIDDescriptorDriver(identifier: identifier))
    }
    var transportProfile = record.transportProfile
    if binding.accessBackend != .ioHID {
      guard let claimed else { return .failure(.interfaceContractMismatch) }
      if let violation = Self.claimedInterfaceViolation(
        of: binding,
        profile: claimed.profile,
        observed: claimed.physicalDevice
      ) {
        return .failure(violation)
      }
      transportProfile = claimed.profile
    }
    return Self.makeUnobservedDriver(
      protocolID: binding.protocolID,
      variant: binding.variant,
      record: record,
      identifier: identifier,
      transportProfile: transportProfile,
      slotOrdinal: slotOrdinal
    )
  }

  /// Builds the driver for one family, variant and record without checking any observed
  /// interface. Not a runtime path: profile capabilities and record rendering have no device,
  /// and ``makeDriver(for:identifier:claimed:)`` calls it only after validation.
  static func makeUnobservedDriver(
    protocolID: PhysicalProtocolID,
    variant: PhysicalProtocolVariantID?,
    record: DeviceRuntimeProfile,
    identifier: DeviceIdentifier,
    transportProfile: DeviceTransportProfile,
    slotOrdinal: Int = 0
  ) -> Result<any PhysicalProtocolDriver, ProtocolBindingReason> {
    if !protocolID.variants.isEmpty {
      guard let variant, protocolID.variants.contains(variant) else {
        return .failure(.unsupportedProtocolVariant)
      }
    }
    switch protocolID {
    case .hidDescriptor: return .success(HIDDescriptorDriver(identifier: identifier))
    case .xboxXID: return .success(XIDDriver(outEndpoint: transportProfile.outputEndpoint))
    case .xboxXUSB:
      guard variant == .receiver else {
        return .success(XUSBDriver(outEndpoint: transportProfile.outputEndpoint))
      }
      guard
        let receiverSlot = XUSBDriver(
          outEndpoint: transportProfile.outputEndpoint,
          slotOrdinal: slotOrdinal
        )
      else { return .failure(.interfaceContractMismatch) }
      return .success(receiverSlot)
    case .xboxGIP:
      return .success(
        GIPDriver(
          transportProfile: transportProfile,
          startupPackets: record.gipStartupPackets,
          keepAlivePolicy: record.gipKeepAlivePolicy,
          usesShareOffset: record.quirks.contains(.shareOffset),
          allowsPhysicalOutput: !record.capabilityDelta.rumbleAbsent
        )
      )
    case .sonySixaxis: return .success(SixaxisDriver(isBluetooth: variant == .bluetoothClassic))
    case .sonyDualShock4:
      return .success(
        DualShock4Driver(
          prefersBluetooth: variant == .bluetoothClassic,
          usesFactoryCalibration: identifier.controllerIdentity.vendorID == 0x054C
        )
      )
    case .sonyDualSense:
      return .success(
        DualSenseDriver(
          prefersBluetooth: variant == .bluetoothClassic,
          hasEdgeButtons: DualSenseDriver.edgeControls.isSubset(
            of: record.capabilityDelta.presentControls
          )
        )
      )
    case .nintendoSwitch1:
      let layout: NintendoControllerLayout
      if record.quirks.contains(.joyConLeft) {
        layout = .leftJoyCon
      } else if record.quirks.contains(.joyConRight) {
        layout = .rightJoyCon
      } else {
        layout = .pro
      }
      return .success(Switch1Driver(layout: layout, isBluetooth: variant == .bluetoothClassic))
    case .valveSteamController:
      return .success(SteamControllerDriver(isWirelessReceiver: variant == .dongle))
    case .vendorFlydigi: return .success(FlydigiDriver())
    case .genericByteLayout: return .success(ByteLayoutDriver())
    case .vendorGameSir:
      switch variant {
      case .usb:
        return .success(
          GameSirDriver(protocol: .g7ProUSB, outEndpoint: transportProfile.outputEndpoint)
        )
      case .enhancedHID:
        return .success(
          GameSirDriver(
            protocol: .enhancedHID,
            hasInnerGrips: record.quirks.contains(.innerGrips),
            usesLightingSlots: record.quirks.contains(.lightingSlots)
          )
        )
      default: return .failure(.unsupportedProtocolVariant)
      }
    }
  }
}
