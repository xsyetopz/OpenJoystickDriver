import Foundation

/// Machine-readable reasons a device is not bound.
public enum ProtocolBindingReason: String, CaseIterable, Codable, Error, Sendable {
  /// No protocol family matches the device.
  case noProtocolMatch = "NoProtocolMatch"
  /// More than one protocol family matches the device.
  case ambiguousProtocolMatch = "AmbiguousProtocolMatch"
  /// The device's interfaces do not meet the family's interface contract.
  case interfaceContractMismatch = "InterfaceContractMismatch"
  /// The device's HID descriptor does not meet the family's descriptor contract.
  case descriptorContractMismatch = "DescriptorContractMismatch"
  /// The family does not implement the variant.
  case unsupportedProtocolVariant = "UnsupportedProtocolVariant"
  /// The family does not support the variant that the observed transport implies.
  case unsupportedTransportVariant = "UnsupportedTransportVariant"
  /// No virtual HID profile is available for the selected binding.
  case virtualProfileUnavailable = "VirtualProfileUnavailable"
  /// The host refused OJD's read of the device's USB configuration while it reported another
  /// exclusive owner of the device.
  case deviceInUse = "DeviceInUse"
  /// The device's USB configuration could not be read, and nothing OJD observes clears the cause
  /// before the device reconnects.
  case configurationUnreadable = "ConfigurationUnreadable"
  /// The device is an 8BitDo bootloader identity, or its matching mode is idle with the reason
  /// `Bootloader`; it receives no traffic.
  case bootloaderIdentity = "BootloaderIdentity"
  /// The device's record has no `default` mode and no mode of it matched the device.
  case noModeMatched = "NoModeMatched"
  /// The device's matching mode is idle with the reason `NoControllerLinked`, such as a receiver
  /// with no controller linked.
  case noControllerLinked = "NoControllerLinked"
  /// The device's matching mode is idle with the reason `AwaitsReenumeration`: OJD holds it and
  /// sends nothing until it changes identity.
  case awaitsReenumeration = "AwaitsReenumeration"
}

extension ProtocolBindingReason {
  /// The catalog key of the sentence that tells a person why the device is not served.
  ///
  /// Every reason has one in every language; the app and `ojd` show it with ``nextStepKey``.
  public var explanationKey: String { "ui.controllers.\(keySegment)" }

  /// The catalog key of the sentence that tells a person what to do about the reason.
  public var nextStepKey: String { "ui.controllers.\(keySegment).nextStep" }

  /// The reason's ID in lowerCamelCase, the segment of its catalog keys.
  private var keySegment: String { CommandLineName.keySegment(rawValue) }
}

/// Observed facts that supported a binding.
public enum ProtocolPredicate: String, Codable, Sendable {
  /// The catalog names the device's vendor and product.
  case catalogIdentity = "CatalogIdentity"
  /// The catalog access path of the record matches the device.
  case catalogAccessPath = "CatalogAccessPath"
  /// The host transport matches.
  case hostTransport = "HostTransport"
  /// An interface has the family's class signature.
  case interfaceSignature = "InterfaceSignature"
  /// The device descriptor's class triple on an unconfigured device with no interface facts.
  case deviceClassSignature = "DeviceClassSignature"
  /// The device has the family's pair of interrupt endpoints.
  case interruptEndpointPair = "InterruptEndpointPair"
  /// The HID descriptor meets ``HIDDescriptorContract``.
  case hidDescriptorContract = "HIDDescriptorContract"
}

/// One selected protocol for one physical device.
public struct ProtocolBinding: Equatable, Sendable {
  /// The rule that selected the protocol.
  public enum Rule: String, Codable, Sendable {
    /// A catalog record named the protocol.
    case catalogRecord = "CatalogRecord"
    /// An interface class signature identified the protocol.
    case interfaceSignature = "InterfaceSignature"
    /// The HID descriptor contract identified the protocol.
    case hidDescriptor = "HIDDescriptor"
    /// The HID descriptor contract identified the protocol and an SDL_GameControllerDB line maps
    /// its inputs.
    case sdlGameControllerDB = "SDLGameControllerDB"
  }

  /// The protocol family.
  public let protocolID: PhysicalProtocolID
  /// The variant of the family; nil when the family has none.
  public let variant: PhysicalProtocolVariantID?
  /// The route the device is accessed over.
  public let accessBackend: DeviceAccessBackend
  /// The number of the interface the protocol drives; nil when the device is not split by
  /// interface.
  public let interfaceNumber: UInt8?
  /// The rule that selected the protocol.
  public let rule: Rule
  /// The facts that supported the binding.
  public let matchedPredicates: [ProtocolPredicate]
  /// The catalog record that applied; nil when none did.
  public let record: DeviceRuntimeProfile?
  /// What the database gave a HID pad without a record; nil for a record or another family.
  var sdl: SDLBindingResolution?
  /// The record that fit no interface of the device when the `HIDDescriptor` rule serves it
  /// instead; nil otherwise.
  var unfitRecordID: String?

  /// Where the HID usage map of a `HIDDescriptor` binding comes from; nil for another family.
  public var inputMapping: InputMapping? {
    guard protocolID == .hidDescriptor else { return nil }
    var mapping = sdl?.inputMapping ?? (record == nil ? .standardHIDUsageMap : .record)
    mapping.unfitRecordID = unfitRecordID
    return mapping
  }

  /// The binding as a family and variant.
  public var id: ProtocolBindingID { ProtocolBindingID(protocolID, variant: variant) }
}

/// The outcome of classifying one device.
public enum ProtocolClassification: Equatable, Sendable {
  /// The device is bound to a protocol.
  case bound(ProtocolBinding)
  /// `rejected` names the family that matched and then failed its contract; nil when none matched.
  case unsupported(ProtocolBindingReason, rejected: ProtocolBindingResult.RejectedCandidate? = nil)
  /// More than one protocol family claims the device.
  case conflict(ProtocolBindingReason, candidates: [PhysicalProtocolID])
}
