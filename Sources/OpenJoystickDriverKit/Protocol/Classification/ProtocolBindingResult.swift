import Foundation

/// The redacted, structured record of one binding decision for diagnostics and support reports.
///
/// It carries observed interface class facts and the classifier's typed outcome only. It never
/// carries a serial number, input state, packet payload, or source provenance. The bound protocol
/// and variant and the applied parameters are reported beside it by the controller description.
public struct ProtocolBindingResult: Codable, Equatable, Sendable {
  /// Whether the device bound to a protocol.
  public enum Outcome: String, Codable, Sendable {
    /// The device bound to a protocol.
    case bound = "Bound"
    /// The device did not bind to any protocol.
    case unsupported = "Unsupported"
  }

  /// Class and HID facts of one observed interface.
  ///
  /// The descriptor is named by its fingerprint only; its bytes are never carried.
  public struct InterfaceSummary: Codable, Equatable, Sendable {
    /// One HID usage page and usage pair.
    public struct Usage: Codable, Equatable, Sendable {
      /// The HID usage page; nil when the interface reports no HID layout.
      public let usagePage: UInt32?
      /// The HID usage; nil when the interface reports no HID layout.
      public let usage: UInt32?
    }

    /// The USB interface number; nil when unknown.
    public let interfaceNumber: UInt8?
    /// The USB alternate setting; nil when unknown.
    public let alternateSetting: UInt8?
    /// The USB interface class; nil when unknown.
    public let interfaceClass: UInt8?
    /// The USB interface subclass; nil when unknown.
    public let interfaceSubclass: UInt8?
    /// The USB interface protocol; nil when unknown.
    public let interfaceProtocol: UInt8?
    /// The transport the host reaches the interface over; nil when unknown.
    public let hostTransport: PhysicalTransport?
    /// The primary HID usage; nil when the interface reports no HID layout.
    public let primaryUsage: Usage?
    /// Whether the descriptor has a Game Pad or Joystick collection; nil when undecided.
    public let hasGamePadOrJoystickCollection: Bool?
    /// Lowercase SHA-256 of the reported descriptor bytes.
    public let descriptorFingerprint: String?

    /// Creates a summary of an observed interface's class and HID facts.
    public init(_ interface: PhysicalInterfaceSignature) {
      interfaceNumber = interface.interfaceNumber
      alternateSetting = interface.alternateSetting
      interfaceClass = interface.interfaceClass
      interfaceSubclass = interface.interfaceSubclass
      interfaceProtocol = interface.interfaceProtocol
      hostTransport = interface.hostTransport
      let layout = interface.hidLayout
      primaryUsage = layout?.primaryUsage.map { Usage(usagePage: $0.usagePage, usage: $0.usage) }
      hasGamePadOrJoystickCollection = layout?.hasGamePadOrJoystickCollection
      descriptorFingerprint = layout?.descriptorFingerprint
    }
  }

  /// A protocol family that matched or competed but did not bind, with its own reason.
  public struct RejectedCandidate: Codable, Equatable, Sendable {
    /// The protocol family of the candidate.
    public let protocolID: PhysicalProtocolID
    /// Why the candidate did not bind.
    public let reason: ProtocolBindingReason
    /// The catalog record whose row named this family; nil when no row did.
    public let catalogRecordID: String?
    /// The SDL_GameControllerDB line found for a HID pad that failed the descriptor contract; nil
    /// when none was.
    public let inputMapping: InputMapping?

    /// Creates a candidate from its family, the reason it did not bind, the catalog record that
    /// named it and the database line found for it.
    public init(
      protocolID: PhysicalProtocolID,
      reason: ProtocolBindingReason,
      catalogRecordID: String? = nil,
      inputMapping: InputMapping? = nil
    ) {
      self.protocolID = protocolID
      self.reason = reason
      self.catalogRecordID = catalogRecordID
      self.inputMapping = inputMapping
    }
  }

  /// Whether the device bound.
  public let outcome: Outcome
  /// Why the device is not bound; nil when bound.
  public let reason: ProtocolBindingReason?
  /// The route the device is accessed over.
  public let accessBackend: DeviceAccessBackend
  /// The observed interfaces.
  public let interfaces: [InterfaceSummary]
  /// The classification rule that bound the device; nil when unsupported.
  public let rule: ProtocolBinding.Rule?
  /// The predicates of the binding rule that held.
  public let matchedPredicates: [ProtocolPredicate]
  /// The applied catalog record, named like its `vvvv-pppp.json` file; nil when none applied.
  public let catalogRecordID: String?
  /// Where the HID usage map comes from; nil unless the `HIDDescriptor` protocol bound.
  public let inputMapping: InputMapping?
  /// The candidates that matched or competed but did not bind.
  public let rejectedCandidates: [RejectedCandidate]

  /// The result for a bound device.
  public init(binding: ProtocolBinding, interfaces: [PhysicalInterfaceSignature]) {
    outcome = .bound
    reason = nil
    accessBackend = binding.accessBackend
    self.interfaces = interfaces.map(InterfaceSummary.init)
    rule = binding.rule
    matchedPredicates = binding.matchedPredicates
    catalogRecordID = binding.record?.recordID
    inputMapping = binding.inputMapping
    rejectedCandidates = []
  }

  /// The result for a device no driver bound.
  ///
  /// Each candidate states its own rejection.
  public init(
    reason: ProtocolBindingReason,
    rejectedCandidates: [RejectedCandidate],
    accessBackend: DeviceAccessBackend,
    interfaces: [InterfaceSummary]
  ) {
    outcome = .unsupported
    self.reason = reason
    self.accessBackend = accessBackend
    self.interfaces = interfaces
    rule = nil
    matchedPredicates = []
    catalogRecordID = nil
    inputMapping = nil
    self.rejectedCandidates = rejectedCandidates
  }
}
