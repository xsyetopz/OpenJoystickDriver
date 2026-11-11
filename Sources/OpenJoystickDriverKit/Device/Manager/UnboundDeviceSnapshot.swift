/// A device OJD observed but left unbound, with the binding decision that rejected it.
public struct UnboundDeviceSnapshot: Equatable, Sendable {
  /// The USB vendor ID.
  public let vendorID: UInt16
  /// The USB product ID.
  public let productID: UInt16
  /// The product name the device reported, trimmed; nil when it reported none or a blank one.
  public let name: String?
  /// The connection label, such as "USB" or the HID transport property.
  public let connection: String
  /// The access backend that observed the device.
  public let accessBackend: DeviceAccessBackend
  /// Why no driver bound the device.
  public let reason: ProtocolBindingReason
  /// The candidates that were rejected, each with its reason.
  public let rejectedCandidates: [ProtocolBindingResult.RejectedCandidate]
  /// The interfaces observed for the device.
  public let interfaces: [ProtocolBindingResult.InterfaceSummary]

  /// Creates a snapshot from the observed device and its binding decision.
  public init(
    vendorID: UInt16,
    productID: UInt16,
    name: String?,
    connection: String,
    accessBackend: DeviceAccessBackend,
    reason: ProtocolBindingReason,
    rejectedCandidates: [ProtocolBindingResult.RejectedCandidate],
    interfaces: [ProtocolBindingResult.InterfaceSummary]
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.name = name
    self.connection = connection
    self.accessBackend = accessBackend
    self.reason = reason
    self.rejectedCandidates = rejectedCandidates
    self.interfaces = interfaces
  }

  /// The binding decision as a ``ProtocolBindingResult``.
  public var bindingResult: ProtocolBindingResult {
    ProtocolBindingResult(
      reason: reason,
      rejectedCandidates: rejectedCandidates,
      accessBackend: accessBackend,
      interfaces: interfaces
    )
  }
}
