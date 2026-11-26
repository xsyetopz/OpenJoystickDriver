import Foundation

/// Deterministic protocol selection from observed facts.
///
/// It performs no I/O.
///
/// Precedence: exact catalog record, then a protocol-standard USB interface
/// signature (the device-descriptor GIP triple only when an unconfigured device
/// exposes no interface facts), then the `HIDDescriptor` contract.
/// `HIDDescriptor` always requires the descriptor contract, including for catalog records.
/// A validation failure never falls through to a lower level. Two exceptions: a record of one
/// Xbox USB family whose device exposes only the other family's interface signature binds by
/// that signature, and a record that fits none of the HID interfaces of the device, when one of
/// them passes the descriptor contract and the record does not state `server` `System`, yields
/// to the `HIDDescriptor` rule.
enum ProtocolClassifier {
  /// Selects the protocol family, variant and interface that drive `device` over `backend`, or
  /// says why none does.
  ///
  /// `modeID` names the mode of the matching catalog record to bind; nil binds the default mode.
  /// - Returns: ``ProtocolClassification`` as a binding, as unsupported when no family fits, or as
  ///   a conflict when more than one fits.
  static func classify(
    _ device: PhysicalDevice,
    backend: DeviceAccessBackend,
    catalog: DeviceCatalog,
    modeID: String? = nil,
    database: SDLGameControllerDatabase = .bundled
  ) -> ProtocolClassification {
    let interfaces = (device.interfaces ?? []).sorted {
      ($0.interfaceNumber ?? .max, $0.alternateSetting ?? .max) < (
        $1.interfaceNumber ?? .max, $1.alternateSetting ?? .max
      )
    }
    if let vendorID = device.vendorID, let productID = device.productID,
      let record = catalog.record(
        for: ControllerModelID(vendorID: vendorID, productID: productID),
        modeID: modeID
      )
    {
      return classify(
        record: record,
        device: device,
        interfaces: interfaces,
        backend: backend,
        modeID: modeID,
        database: database
      )
    }
    if let result = classifySignature(interfaces, backend: backend)
      ?? classifyDeviceSignature(device, backend: backend)
    {
      return result
    }
    guard !backend.usesRawUSB else { return .unsupported(.noProtocolMatch) }
    return classifyDescriptor(device, interfaces: interfaces, backend: backend, database: database)
  }

  /// Classifies `device` by the `HIDDescriptor` contract.
  private static func classifyDescriptor(
    _ device: PhysicalDevice,
    interfaces: [PhysicalInterfaceSignature],
    backend: DeviceAccessBackend,
    database: SDLGameControllerDatabase
  ) -> ProtocolClassification {
    guard let interface = descriptorInterface(interfaces) else {
      guard let line = database.match(for: device) else {
        return .unsupported(.descriptorContractMismatch)
      }
      return .unsupported(
        .descriptorContractMismatch,
        rejected: ProtocolBindingResult.RejectedCandidate(
          protocolID: .hidDescriptor,
          reason: .descriptorContractMismatch,
          inputMapping: InputMapping(
            source: .none,
            guid: line.guid.description,
            match: line.tier,
            unmapped: [],
            rejection: nil
          )
        )
      )
    }
    return .bound(
      descriptorBinding(device: device, interface: interface, backend: backend, database: database)
    )
  }

  /// Classifies `device` by its catalog `record`.
  private static func classify(
    record: DeviceRuntimeProfile,
    device: PhysicalDevice,
    interfaces: [PhysicalInterfaceSignature],
    backend: DeviceAccessBackend,
    modeID: String?,
    database: SDLGameControllerDatabase
  ) -> ProtocolClassification {
    switch record.idleReason {
    case .noControllerLinked?: return .unsupported(.noControllerLinked)
    case .bootloader?: return .unsupported(.bootloaderIdentity)
    case .awaitsReenumeration?: return .unsupported(.awaitsReenumeration)
    case nil: break
    }
    if !record.hasDefaultMode, modeID == nil {
      // No mode matches the device, so no mode of the record fits what it exposes.
      guard backend == .hid, !interfaces.isEmpty else { return .unsupported(.noModeMatched) }
      return descriptorFallback(
        for: record,
        device: device,
        interfaces: interfaces,
        backend: backend,
        database: database
      ) ?? .unsupported(.noModeMatched)
    }
    let result =
      otherXboxFamilyBinding(for: record, interfaces: interfaces, backend: backend)
      ?? bind(record, interfaces: interfaces, backend: backend)
    guard recordFitsNoInterface(record, interfaces: interfaces, backend: backend) else {
      return result
    }
    return descriptorFallback(
      for: record,
      device: device,
      interfaces: interfaces,
      backend: backend,
      database: database
    ) ?? mismatch(of: record, kept: result)
  }

  /// Binds a catalog `record` to the interfaces and access path that `backend` observed.
  ///
  /// Rejects the record when its raw-USB use differs from the backend, when the transport variant
  /// cannot be told, or, for a `HIDDescriptor` record, when no interface passes the descriptor
  /// contract.
  private static func bind(
    _ record: DeviceRuntimeProfile,
    interfaces: [PhysicalInterfaceSignature],
    backend: DeviceAccessBackend
  ) -> ProtocolClassification {
    let isRawUSB = backend.usesRawUSB
    func reject(_ reason: ProtocolBindingReason) -> ProtocolClassification {
      .unsupported(
        reason,
        rejected: ProtocolBindingResult.RejectedCandidate(
          protocolID: record.physicalProtocolID,
          reason: reason,
          catalogRecordID: record.recordID
        )
      )
    }
    guard record.usesRawUSB == isRawUSB else { return reject(.unsupportedTransportVariant) }
    var predicates: [ProtocolPredicate] = [.catalogIdentity, .catalogAccessPath]
    let variants = transportVariants(of: record)
    let variant: PhysicalProtocolVariantID?
    if let stored = record.physicalProtocolVariant {
      variant = stored
    } else if variants.isEmpty {
      variant = nil
    } else {
      let observed = isRawUSB ? .usb : hostTransportVariant(interfaces)
      guard let observed, variants.contains(observed) else {
        return reject(.unsupportedTransportVariant)
      }
      variant = observed
      predicates.append(.hostTransport)
    }
    var interfaceNumber =
      isRawUSB
      ? record.transportProfile.interfaceNumber
      : boundInterfaceNumber(of: record, in: interfaces)
    // A catalog row adds identity to `HIDDescriptor`; it never replaces validation.
    if record.physicalProtocolID == .hidDescriptor {
      guard let interface = descriptorInterface(interfaces) else {
        return reject(.descriptorContractMismatch)
      }
      interfaceNumber = interface.interfaceNumber
      predicates.append(.hidDescriptorContract)
    }
    return .bound(
      ProtocolBinding(
        protocolID: record.physicalProtocolID,
        variant: variant,
        accessBackend: backend,
        interfaceNumber: interfaceNumber,
        rule: .catalogRecord,
        matchedPredicates: predicates,
        record: record
      )
    )
  }

  /// The signature binding of a device whose record names one Xbox USB family but whose interfaces
  /// carry only the other's.
  ///
  /// One VID:PID can ship either firmware mode (8BitDo `2dc8:3106` is XUSB in Linux `xpad.c` and
  /// GIP in SDL `controller_list.h`), and the claimed interface class is what the device speaks.
  /// Nil when the record's own signature is present.
  private static func otherXboxFamilyBinding(
    for record: DeviceRuntimeProfile,
    interfaces: [PhysicalInterfaceSignature],
    backend: DeviceAccessBackend
  ) -> ProtocolClassification? {
    let xboxUSB: Set<PhysicalProtocolID> = [.xboxXUSB, .xboxGIP]
    guard xboxUSB.contains(record.physicalProtocolID) else { return nil }
    let observed = Set(
      signatures.filter { signature in interfaces.contains(where: signature.matches) }.map(
        \.protocolID
      )
    )
    guard !observed.contains(record.physicalProtocolID),
      !observed.isDisjoint(with: xboxUSB.subtracting([record.physicalProtocolID]))
    else { return nil }
    return classifySignature(interfaces, backend: backend)
  }

  /// The interface a HID record binds to: the lowest one inside the mode's `interface` range, or
  /// the only one when the record names no range.
  private static func boundInterfaceNumber(
    of record: DeviceRuntimeProfile,
    in interfaces: [PhysicalInterfaceSignature]
  ) -> UInt8? {
    guard let range = record.interfaceRange else {
      return interfaces.count == 1 ? interfaces[0].interfaceNumber : nil
    }
    return interfaces.compactMap(\.interfaceNumber).filter(range.contains).min()
  }

  /// The first interface whose observed HID facts satisfy the descriptor contract.
  static func descriptorInterface(
    _ interfaces: [PhysicalInterfaceSignature]
  ) -> PhysicalInterfaceSignature? {
    interfaces.first { HIDDescriptorContract.violation(in: $0.hidLayout) == nil }
  }

  /// The family's variants this model has a link for: all of them, except for a Bluetooth-only
  /// Switch pad, whose USB link only charges it.
  private static func transportVariants(
    of record: DeviceRuntimeProfile
  ) -> [PhysicalProtocolVariantID] {
    let variants = record.physicalProtocolID.variants
    guard record.parameters.usbProtocol == .chargingOnly else { return variants }
    return variants.filter { $0 != .usb }
  }

  /// The single host transport shared by every interface; unknown when any is absent.
  private static func hostTransportVariant(
    _ interfaces: [PhysicalInterfaceSignature]
  ) -> PhysicalProtocolVariantID? {
    guard let transport = interfaces.first?.hostTransport,
      interfaces.allSatisfy({ $0.hostTransport == transport })
    else { return nil }
    switch transport {
    case .usb: return .usb
    case .bluetoothClassic: return .bluetoothClassic
    case .bluetoothLE: return .bluetoothLE
    case .proprietaryRadioReceiver: return nil
    }
  }

  /// Binds the protocol-standard USB interface signature that `interfaces` match, or nil when none
  /// matches.
  ///
  /// Signatures of different families conflict. A signature needs a raw-USB backend and an
  /// interface with an interrupt IN and OUT endpoint pair; HID access never binds one.
  private static func classifySignature(
    _ interfaces: [PhysicalInterfaceSignature],
    backend: DeviceAccessBackend
  ) -> ProtocolClassification? {
    var matched: [ProtocolInterfaceSignature] = []
    for interface in interfaces {
      for signature in signatures where signature.matches(interface) && !matched.contains(signature)
      { matched.append(signature) }
    }
    guard let signature = matched.first else { return nil }
    var candidates: [PhysicalProtocolID] = []
    for match in matched where !candidates.contains(match.protocolID) {
      candidates.append(match.protocolID)
    }
    // Different families conflict. Variants of one family resolve to the variant of the lowest
    // interface number, since interfaces are matched in that order.
    guard candidates.count == 1 else {
      return .conflict(.ambiguousProtocolMatch, candidates: candidates)
    }
    // These are raw-USB variants; HID access cannot drive them and must not reach
    // `HIDDescriptor`.
    guard backend.usesRawUSB else {
      return .unsupported(
        .unsupportedTransportVariant,
        rejected: ProtocolBindingResult.RejectedCandidate(
          protocolID: signature.protocolID,
          reason: .unsupportedTransportVariant
        )
      )
    }
    guard
      let interface = interfaces.first(where: {
        signature.matches($0)
          && (signature.requiredInterfaceNumber == nil
            || $0.interfaceNumber == signature.requiredInterfaceNumber)
          // Registry-only facts carry no endpoints; claimed-interface validation checks them.
          && ($0.endpoints == nil || hasInterruptPair($0))
      })
    else {
      return .unsupported(
        .interfaceContractMismatch,
        rejected: ProtocolBindingResult.RejectedCandidate(
          protocolID: signature.protocolID,
          reason: .interfaceContractMismatch
        )
      )
    }
    return .bound(
      ProtocolBinding(
        protocolID: signature.protocolID,
        variant: signature.variant,
        accessBackend: backend,
        interfaceNumber: interface.interfaceNumber,
        rule: .interfaceSignature,
        matchedPredicates: interface.endpoints == nil
          ? [.interfaceSignature] : [.interfaceSignature, .interruptEndpointPair],
        record: nil
      )
    )
  }

  /// Whether `interface` has an addressed interrupt IN endpoint and an addressed interrupt OUT
  /// endpoint.
  static func hasInterruptPair(_ interface: PhysicalInterfaceSignature) -> Bool {
    let endpoints = interface.endpoints ?? []
    return [USBEndpointDirection.in, .out].allSatisfy { direction in
      endpoints.contains {
        $0.address != nil && $0.transferType == .interrupt && $0.direction == direction
      }
    }
  }
}
