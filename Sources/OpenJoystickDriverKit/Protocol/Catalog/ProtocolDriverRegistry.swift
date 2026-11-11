import Foundation

/// Binds observed devices to protocol drivers and constructs them.
///
/// Classification goes through ``ProtocolClassifier``; driver construction keys only
/// on the bound ``PhysicalProtocolID`` and ``PhysicalProtocolVariantID``, after the claimed
/// interface contract holds. A device that does not bind has no driver.
public final class ProtocolDriverRegistry: Sendable {
  /// The current catalog; it changes when the service applies new user controller records.
  private var catalog: DeviceCatalog { DeviceCatalog.current.withLock { $0 } }

  /// Creates a registry that reads the current catalog.
  public init() {}

  /// Exact catalog models whose records declare raw USB access, read when called.
  public var rawUSBModels: [ControllerModelID] { catalog.rawUSBModels }

  /// Exact catalog models whose records declare HID access; they may not advertise
  /// GamePad usage.
  public var hidModels: [ControllerModelID] { catalog.hidModels }

  /// The exact catalog record for this model, or nil for an uncatalogued model.
  public func record(for model: ControllerModelID) -> DeviceRuntimeProfile? {
    catalog.record(for: model)
  }

  /// Profile-editor capabilities for an exact catalog model.
  ///
  /// No device is observed, so a family whose variant follows the host transport is
  /// described by its USB variant; the transport variant does not change capabilities.
  ///
  /// The physical outputs are the driver's full set and are not narrowed to `MacOSOwnedOutput`:
  /// whether macOS serves the controller (`GCController.supportsHIDDevice`) is known only for a
  /// live device, and a profile also runs where OJD owns output. A connected controller reports
  /// its narrowed outputs, and the profile editor uses those instead.
  public func profileCapabilities(
    for model: ControllerModelID
  ) -> ControllerProfileCapabilities? {
    guard let record = catalog.record(for: model) else { return nil }
    let variant =
      record.physicalProtocolVariant
      ?? (record.physicalProtocolID.variants.contains(.usb) ? .usb : nil)
    guard
      case .success(let driver) = Self.makeUnobservedDriver(
        protocolID: record.physicalProtocolID,
        variant: variant,
        record: record,
        model: model,
        transportProfile: record.transportProfile
      )
    else { return nil }
    return ControllerProfileCapabilities(
      physicalInput: capabilities(driver.capabilities, record: record),
      physicalOutput: driver.outputCapabilities
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

  /// Classifies a device; `modeID` runs the catalog record's selected mode instead of its default.
  func classify(
    _ device: PhysicalDevice,
    backend: DeviceAccessBackend,
    modeID: String? = nil
  ) -> ProtocolClassification {
    ProtocolClassifier.classify(device, backend: backend, catalog: catalog, modeID: modeID)
  }

  /// Chooses the mode of a catalogued model by its match keys; ``ControllerModeSelection/noModes``
  /// for a model whose record has none.
  func selectMode(
    of model: ControllerModelID,
    backend: DeviceAccessBackend,
    reader: any ControllerModeProbeReader,
    device: PhysicalDevice = PhysicalDevice()
  ) async -> ControllerModeSelection {
    guard let record = catalog.record(for: model) else { return .noModes }
    return await ControllerModeSelector.select(
      from: record,
      model: model,
      backend: backend,
      reader: reader,
      device: device
    )
  }

  /// Whether passively observed USB facts carry a known Xbox USB interface or device signature.
  ///
  /// Raw-USB enumeration admits an uncatalogued device only then, so classification can report it.
  public static func carriesProtocolSignature(_ device: PhysicalDevice) -> Bool {
    ProtocolClassifier.carriesSignature(device)
  }

  /// The runtime profile a binding runs with: its catalog record or, for an interface-signature
  /// binding, the family defaults.
  ///
  /// GIP devices enumerate unconfigured on macOS (their device class is vendor-specific), so a GIP
  /// signature binding sets configuration 1 before the claim whether this attach saw the device or
  /// interface signature, like the catalogued G7 SE row. Nil for `HIDDescriptor` without a record.
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
  /// receiver reads it, and only to reject a slot past the fourth. `reportDescriptor` is the bound
  /// HID interface's report descriptor; only `HIDDescriptor` reads it, to choose its layout.
  func makeDriver(
    for binding: ProtocolBinding,
    model: ControllerModelID,
    claimed: USBTransportResolution?,
    slotOrdinal: Int = 0,
    reportDescriptor: Data? = nil
  ) -> Result<any PhysicalProtocolDriver, ProtocolBindingReason> {
    guard let record = runtimeProfile(for: binding) else {
      guard binding.protocolID == .hidDescriptor else { return .failure(.noProtocolMatch) }
      return .success(
        HIDDescriptorDriver(
          model: model,
          reportDescriptor: reportDescriptor,
          usageMap: binding.sdl?.usageMap
        )
      )
    }
    var transportProfile = record.transportProfile
    if binding.accessBackend.usesRawUSB {
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
      model: model,
      transportProfile: transportProfile,
      slotOrdinal: slotOrdinal,
      reportDescriptor: reportDescriptor
    )
  }

  /// Builds the driver for one family, variant and record without checking any observed interface.
  ///
  /// Not a runtime path: profile capabilities and record rendering have no device, and
  /// ``makeDriver(for:model:claimed:)`` calls it only after validation.
  ///
  /// A record's input layouts of a family that decodes with its own driver are layered over that
  /// driver (``LayeredInputDriver``).
  static func makeUnobservedDriver(
    protocolID: PhysicalProtocolID,
    variant: PhysicalProtocolVariantID?,
    record: DeviceRuntimeProfile,
    model: ControllerModelID,
    transportProfile: DeviceTransportProfile,
    slotOrdinal: Int = 0,
    reportDescriptor: Data? = nil
  ) -> Result<any PhysicalProtocolDriver, ProtocolBindingReason> {
    let family = makeFamilyDriver(
      protocolID: protocolID,
      variant: variant,
      record: record,
      model: model,
      transportProfile: transportProfile,
      slotOrdinal: slotOrdinal,
      reportDescriptor: reportDescriptor
    )
    guard case .success(let driver) = family, let layouts = record.inputLayouts,
      protocolID != .hidReportLayout, protocolID != .hidDescriptor
    else { return family }
    return .success(LayeredInputDriver(family: driver, layouts: layouts))
  }

  private static func makeFamilyDriver(
    protocolID: PhysicalProtocolID,
    variant: PhysicalProtocolVariantID?,
    record: DeviceRuntimeProfile,
    model: ControllerModelID,
    transportProfile: DeviceTransportProfile,
    slotOrdinal: Int,
    reportDescriptor: Data?
  ) -> Result<any PhysicalProtocolDriver, ProtocolBindingReason> {
    if !protocolID.variants.isEmpty {
      guard let variant, protocolID.variants.contains(variant) else {
        return .failure(.unsupportedProtocolVariant)
      }
    }
    let tuning = protocolID.driverTuning(variant: variant, record: record.tuning)
    switch protocolID {
    case .hidDescriptor:
      return .success(
        HIDDescriptorDriver(
          model: model,
          reportDescriptor: reportDescriptor,
          usageMap: record.hidUsageMap,
          rumbleTemplate: record.rumbleTemplate
        )
      )
    case .hidReportLayout:
      // Only a record carries a layout; a family profile has nothing to decode with.
      guard let layouts = record.inputLayouts else { return .failure(.noProtocolMatch) }
      return .success(ReportLayoutDriver(layouts: layouts, rumbleTemplate: record.rumbleTemplate))
    case .xboxXID, .nintendoSwitchInputOnly, .vendorFlydigi:
      return .success(
        ReportLayoutDriver(
          describedBy: protocolID,
          variant: variant,
          rumbleTemplate: record.rumbleTemplate,
          outEndpoint: transportProfile.outputEndpoint,
          tuning: tuning
        )
      )
    case .xboxXUSB:
      guard variant == .receiver else {
        return .success(
          XUSBDriver(
            outEndpoint: transportProfile.outputEndpoint,
            tuning: tuning,
            usbStartupWrites: record.usbStartupWrites,
            rumbleTemplate: record.rumbleTemplate
          )
        )
      }
      guard
        let receiverSlot = XUSBDriver(
          outEndpoint: transportProfile.outputEndpoint,
          slotOrdinal: slotOrdinal,
          tuning: tuning,
          usbStartupWrites: record.usbStartupWrites,
          rumbleTemplate: record.rumbleTemplate
        )
      else { return .failure(.interfaceContractMismatch) }
      return .success(receiverSlot)
    case .xboxGIP:
      return .success(
        GIPDriver(
          transportProfile: transportProfile,
          startupPackets: record.gipStartupPackets,
          usbStartupWrites: record.usbStartupWrites,
          keepAlivePolicy: record.gipKeepAlivePolicy,
          shareButtonFromEnd: record.parameters.shareButton?.fromEnd,
          allowsPhysicalOutput: !record.capabilityDelta.rumbleAbsent,
          tuning: tuning
        )
      )
    case .sonySixaxis: return .success(SixaxisDriver(isBluetooth: variant == .bluetoothClassic))
    case .sonyDualShock4:
      return .success(
        DualShock4Driver(
          prefersBluetooth: variant == .bluetoothClassic,
          usesFactoryCalibration: record.parameters.motionCalibration == .factory,
          model: DualShock4Model(parameters: record.parameters),
          tuning: tuning
        )
      )
    case .sonyDualSense:
      return .success(
        DualSenseDriver(
          prefersBluetooth: variant == .bluetoothClassic,
          hasEdgeButtons: DualSenseDriver.edgeControls.isSubset(
            of: record.capabilityDelta.presentControls
          ),
          parameters: record.parameters,
          tuning: tuning
        )
      )
    case .nintendoSwitch2:
      let layout: Switch2ControllerLayout =
        switch record.parameters.layout {
        case .gameCube: .gameCube
        case .joyConLeft: .leftJoyCon
        case .joyConRight: .rightJoyCon
        case .pro, nil: .pro
        }
      let link: Switch2Link
      switch variant {
      case .usb: link = .usb
      case .bluetoothLE: link = .bluetoothLE
      default: return .failure(.unsupportedProtocolVariant)
      }
      return .success(
        Switch2Driver(
          layout: layout,
          link: link,
          tuning: tuning,
          usbStartupWrites: record.usbStartupWrites
        )
      )
    case .nintendoSwitch1:
      let layout: NintendoControllerLayout =
        switch record.parameters.layout {
        case .joyConLeft: .leftJoyCon
        case .joyConRight: .rightJoyCon
        case .pro, .gameCube, nil: .pro
        }
      return .success(
        Switch1Driver(
          layout: layout,
          isBluetooth: variant == .bluetoothClassic,
          rumbleTemplate: record.rumbleTemplate
        )
      )
    case .valveSteamTriton:
      return .success(SteamTritonDriver(isDongle: variant == .dongle, tuning: tuning))
    case .valveSteamDeck: return .success(SteamDeckDriver())
    case .valveSteamController:
      return .success(
        SteamControllerDriver(
          isWirelessReceiver: variant == .dongle,
          isBluetooth: variant == .bluetoothLE
        )
      )
    case .vendorPS3ThirdParty:
      return .success(
        PS3ThirdPartyDriver(
          model: model,
          rumbleTemplate: record.rumbleTemplate,
          hatFromPressureOnly: record.parameters.hatSource == .dpadPressure
        )
      )
    case .nintendoWii: return .success(WiiDriver(tuning: tuning))
    case .vendorNVIDIAShield:
      return .success(
        NVIDIAShieldDriver(
          isShield2015: record.parameters.reportRevision == .shield2015,
          rumbleTemplate: record.rumbleTemplate
        )
      )
    case .vendorGameSir:
      switch variant {
      case .usb:
        return .success(
          GameSirDriver(
            protocol: .g7ProUSB,
            outEndpoint: transportProfile.outputEndpoint,
            tuning: tuning
          )
        )
      case .enhancedHID:
        return .success(
          GameSirDriver(
            protocol: .enhancedHID,
            hasInnerGrips: record.parameters.innerGrips == true,
            usesLightingSlots: record.parameters.lightingMemory == .profileSlots,
            tuning: tuning,
            rumbleTemplate: record.rumbleTemplate
          )
        )
      default: return .failure(.unsupportedProtocolVariant)
      }
    }
  }
}
