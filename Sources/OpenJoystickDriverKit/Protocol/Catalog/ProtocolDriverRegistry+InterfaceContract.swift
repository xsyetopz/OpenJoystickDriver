import Foundation

extension ProtocolDriverRegistry {
  /// Controller slots of one Xbox 360 wireless receiver; `XUSBDriver` lights players 1–4.
  static let receiverSlotCount = 4

  /// The protocol roles a raw-USB claim runs, one pipeline each, in slot order.
  ///
  /// An Xbox 360 wireless receiver (`xbox.xusb:receiver`) has one role per observed interface
  /// that passes ``claimedInterfaceViolation(of:profile:observed:)`` on its own endpoints: the
  /// receiver triple FF/5D/81 with exactly one interrupt IN and one interrupt OUT endpoint, as
  /// `xpad_probe` requires per interface (xpad.c:2042–2137). Roles are ordered by interface
  /// number, and a role's index is its slot ordinal. A matching interface past the fourth is not
  /// a role; it is dropped with a log line. Each role after the first leaves SET_CONFIGURATION
  /// out, because it terminates every open interface of the device.
  ///
  /// Every other family, and a receiver whose claim observed no qualifying interface, runs the
  /// claim itself as its one role, which ``makeDriver(for:identifier:claimed:slotOrdinal:)``
  /// validates as before. So does a receiver whose catalog row pins its interface or endpoints:
  /// a pin names one interface, so it stays authoritative as that single role and is validated
  /// against the observed interface like any pinned claim.
  func roleProfiles(
    for binding: ProtocolBinding,
    resolution: USBTransportResolution
  ) -> [USBTransportResolution] {
    guard binding.protocolID == .xboxXUSB, binding.variant == .receiver,
      !resolution.profile.hasInterfaceOverride, !resolution.profile.hasEndpointOverride
    else { return [resolution] }
    let interfaces = (resolution.physicalDevice?.interfaces ?? []).filter {
      ($0.alternateSetting ?? 0) == 0
    }.sorted { ($0.interfaceNumber ?? 0) < ($1.interfaceNumber ?? 0) }
    var roles: [DeviceTransportProfile] = []
    for interface in interfaces {
      guard let profile = Self.roleProfile(resolution.profile, claiming: interface),
        !roles.contains(where: { $0.interfaceNumber == profile.interfaceNumber }),
        Self.claimedInterfaceViolation(
          of: binding,
          profile: profile,
          observed: resolution.physicalDevice
        ) == nil
      else { continue }
      roles.append(profile)
    }
    guard !roles.isEmpty else { return [resolution] }
    if roles.count > Self.receiverSlotCount {
      print(
        "[ProtocolDriverRegistry] Receiver interfaces beyond slot \(Self.receiverSlotCount)"
          + " are not roles: \(roles.dropFirst(Self.receiverSlotCount).map(\.interfaceNumber))"
      )
    }
    return roles.prefix(Self.receiverSlotCount).enumerated().map { ordinal, profile in
      USBTransportResolution(
        profile: ordinal == 0 ? profile : Self.leavingConfiguration(profile),
        physicalDevice: resolution.physicalDevice
      )
    }
  }

  /// The claim moved to one interface and its interrupt endpoints, or nil when the interface
  /// lacks an interrupt IN or OUT endpoint.
  private static func roleProfile(
    _ claim: DeviceTransportProfile,
    claiming interface: PhysicalInterfaceSignature
  ) -> DeviceTransportProfile? {
    let endpoints = interface.endpoints ?? []
    guard let number = interface.interfaceNumber,
      let input = endpoints.first(where: { $0.transferType == .interrupt && $0.direction == .in })?
        .address,
      let output = endpoints.first(where: { $0.transferType == .interrupt && $0.direction == .out }
      )?.address
    else { return nil }
    return DeviceTransportProfile(
      inputEndpoint: input,
      outputEndpoint: output,
      interfaceNumber: number,
      alternateSetting: 0,
      needsSetConfiguration: claim.needsSetConfiguration,
      postHandshakeSettleNanoseconds: claim.postHandshakeSettleNanoseconds
    )
  }

  private static func leavingConfiguration(
    _ profile: DeviceTransportProfile
  ) -> DeviceTransportProfile {
    DeviceTransportProfile(
      inputEndpoint: profile.inputEndpoint,
      outputEndpoint: profile.outputEndpoint,
      interfaceNumber: profile.interfaceNumber,
      alternateSetting: profile.alternateSetting,
      hasInterfaceOverride: profile.hasInterfaceOverride,
      hasEndpointOverride: profile.hasEndpointOverride,
      needsSetConfiguration: false,
      postHandshakeSettleNanoseconds: profile.postHandshakeSettleNanoseconds
    )
  }

  /// Checks the interface a raw-USB binding will claim, after passive observation and before the
  /// driver exists, so before the first protocol write.
  ///
  /// Pinned to Linux `xpad.c` at the locked commit: `xpad_table` binds XUSB and GIP only by their
  /// interface class triples and XID by class or device ID, and `xpad_probe` requires exactly one
  /// interrupt IN and one interrupt OUT endpoint, with GIP data on interface 0.
  ///
  /// Whenever an interface number is observed, the claimed interface and alternate setting must
  /// exist with the family's class triple. Its endpoints are checked when they were observed:
  /// the profile's IN and OUT endpoints, catalog pins included, must be interrupt endpoints of
  /// that interface. Returns nil when the contract holds or when no interface number was observed
  /// (the DriverKit route reports none), which leaves nothing to check.
  ///
  /// An interface-signature binding has no catalog record to vouch for the device, so it fails
  /// closed: the claimed interface and its endpoints must be observed. The IOUSBHost registry
  /// exposes interface triples without endpoints, so only the device's own configuration
  /// descriptor can satisfy it, and a device never runs on family-default endpoints.
  static func claimedInterfaceViolation(
    of binding: ProtocolBinding,
    profile: DeviceTransportProfile,
    observed device: PhysicalDevice?
  ) -> ProtocolBindingReason? {
    let requiresObservation = binding.rule == .interfaceSignature
    let interfaces = (device?.interfaces ?? []).filter { $0.interfaceNumber != nil }
    guard !interfaces.isEmpty else { return requiresObservation ? .interfaceContractMismatch : nil }
    guard
      let interface = interfaces.first(where: {
        $0.interfaceNumber == profile.interfaceNumber
          && ($0.alternateSetting ?? 0) == profile.alternateSetting
      }), acceptsInterfaceClass(interface, for: binding),
      interface.endpoints == nil && !requiresObservation
        || hasProfileEndpoints(
          interface,
          profile,
          // xpad's rule; GameSir's vendor interface has no pinned endpoint-count source.
          exactPair: binding.protocolID != .vendorGameSir
        )
    else { return .interfaceContractMismatch }
    return nil
  }

  private static func acceptsInterfaceClass(
    _ interface: PhysicalInterfaceSignature,
    for binding: ProtocolBinding
  ) -> Bool {
    switch binding.protocolID {
    case .xboxXUSB, .xboxGIP:
      return ProtocolClassifier.signatures.contains {
        $0.protocolID == binding.protocolID && $0.variant == binding.variant
          && $0.matches(interface)
          && ($0.requiredInterfaceNumber == nil
            || $0.requiredInterfaceNumber == interface.interfaceNumber)
      }
    case .xboxXID: return true
    case .vendorGameSir: return interface.interfaceClass == 0xFF
    case .hidDescriptor, .sonySixaxis, .sonyDualShock4, .sonyDualSense, .nintendoSwitch1,
      .valveSteamController, .vendorFlydigi, .genericByteLayout:
      return false
    }
  }

  private static func hasProfileEndpoints(
    _ interface: PhysicalInterfaceSignature,
    _ profile: DeviceTransportProfile,
    exactPair: Bool
  ) -> Bool {
    guard let endpoints = interface.endpoints, !exactPair || endpoints.count == 2 else {
      return false
    }
    return endpoints.contains {
      $0.address == profile.inputEndpoint && $0.transferType == .interrupt && $0.direction == .in
    }
      && endpoints.contains {
        $0.address == profile.outputEndpoint && $0.transferType == .interrupt
          && $0.direction == .out
      }
  }
}
