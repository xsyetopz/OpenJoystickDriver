import Foundation

/// A validated raw-USB test plan loaded from a canonical controller record.
///
/// The plan uses the runtime's profile construction and driver factory, so a probed
/// record behaves exactly as the runtime would drive it.
public struct ControllerRecordProbePlan: Equatable, Sendable {
  /// The probe's name for the controller, from its vendor and product IDs.
  public let name: String
  /// The USB vendor ID of the record.
  public let vendorID: UInt16
  /// The USB product ID of the record.
  public let productID: UInt16
  /// The raw USB protocol binding of the record.
  public let protocolBinding: ProtocolBindingID
  /// The USB transport profile of the record.
  public let transportProfile: DeviceTransportProfile
  /// The GIP startup packets of the record; empty for a protocol other than GIP.
  public let startupPackets: [String]
  /// How the probe keeps a GIP controller alive.
  public let keepAlivePolicy: GIPKeepAlivePolicy
  /// The runtime profile that the record builds.
  private let profile: DeviceRuntimeProfile

  /// Loads the record file at `url`.
  ///
  /// - Throws: The error of reading the file, or the errors of ``init(data:)``.
  public init(contentsOf url: URL) throws { try self.init(data: Data(contentsOf: url)) }

  /// Decodes and validates a controller record in `data` as the catalog reads a record file: plain
  /// UTF-8, one JSON object, no member named twice.
  ///
  /// - Throws: ``ControllerRecordProbeError/invalidProfile(_:)`` when the record does not decode or
  ///   does not build a runtime profile, and ``ControllerRecordProbeError/unsupportedProtocol(_:)``
  ///   when its protocol is not `XboxGIP` or `XboxXUSB` or it has no raw USB binding, and
  ///   ``ControllerRecordProbeError/bootloaderIdentity`` when it names an 8BitDo bootloader identity.
  public init(data: Data) throws {
    let (decoded, profile) = try Self.validatedRecord(data)
    guard !decoded.model.isBootloaderIdentity else {
      throw ControllerRecordProbeError.bootloaderIdentity
    }
    // The signing-free probe drives only the raw-USB Xbox families it can start safely.
    guard Self.probeableProtocols.contains(profile.physicalProtocolID) else {
      throw ControllerRecordProbeError.unsupportedProtocol(profile.physicalProtocolID.rawValue)
    }
    guard let binding = profile.rawUSBBinding else {
      throw ControllerRecordProbeError.unsupportedProtocol(profile.physicalProtocolID.rawValue)
    }
    vendorID = decoded.model.vendorID
    productID = decoded.model.productID
    name = String(format: "Controller %04x:%04x", vendorID, productID)
    protocolBinding = binding
    transportProfile = profile.transportProfile
    startupPackets = profile.physicalProtocolID == .xboxGIP ? profile.gipStartupPackets : []
    keepAlivePolicy = profile.gipKeepAlivePolicy
    self.profile = profile
  }

  /// The protocols whose records the probe can drive.
  public static let probeableProtocols: [PhysicalProtocolID] = [.xboxGIP, .xboxXUSB]

  /// Checks that `data` is a controller record that builds a runtime profile, without building a
  /// probe plan, so the check holds for every protocol.
  ///
  /// - Returns: The protocol of the record's default mode.
  /// - Throws: ``ControllerRecordProbeError/invalidProfile(_:)`` when the record does not decode
  ///   or does not build a runtime profile.
  public static func validate(data: Data) throws -> PhysicalProtocolID {
    try validatedRecord(data).profile.physicalProtocolID
  }

  /// Decodes `data` as the catalog reads a record file and builds its runtime profile.
  private static func validatedRecord(
    _ data: Data
  ) throws -> (
    decoded: (model: ControllerModelID, document: ControllerRecordDocument),
    profile: DeviceRuntimeProfile
  ) {
    do {
      let decoded = try ControllerRecordSet.decode(ControllerRecordSet.ordered(data))
      return (decoded, try DeviceCatalog.makeRuntimeProfile(decoded.document))
    } catch {
      // A coded reason leads with its code, like every other `E5001: ...` message.
      let reason =
        ControllerRecordSet.problemCode(error).map {
          "\($0.rawValue): "
            + ControllerRecordSet.problemDescription(
              error,
              includingCode: false,
              document: "record"
            )
        } ?? "Invalid controller record: \(error)"
      throw ControllerRecordProbeError.invalidProfile(reason)
    }
  }

  /// Builds the record's driver without an observed device, to render the plan.
  ///
  /// A probe that writes to a device uses ``makeDriver(for:claimed:)``.
  public func makeUnobservedDriver() -> any PhysicalProtocolDriver {
    let result = ProtocolDriverRegistry.makeUnobservedDriver(
      protocolID: profile.physicalProtocolID,
      variant: variant,
      record: profile,
      model: ControllerModelID(vendorID: vendorID, productID: productID),
      transportProfile: transportProfile
    )
    guard case .success(let driver) = result else {
      preconditionFailure("validated probe plan has no driver for \(protocolBinding)")
    }
    return driver
  }

  /// Builds the record's driver for one enumerated device through the runtime's validating
  /// factory. `claimed` holds the profile resolved for the device and the facts observed for it;
  /// a claimed interface that violates the family contract fails before any write.
  public func makeDriver(
    for device: USBTransportDevice,
    claimed: USBTransportResolution
  ) -> Result<any PhysicalProtocolDriver, ProtocolBindingReason> {
    let binding = ProtocolBinding(
      protocolID: profile.physicalProtocolID,
      variant: variant,
      accessBackend: DeviceAccessBackend(route: device.route),
      interfaceNumber: transportProfile.interfaceNumber,
      rule: .catalogRecord,
      matchedPredicates: [.catalogIdentity, .catalogAccessPath],
      record: profile
    )
    return ProtocolDriverRegistry().makeDriver(
      for: binding,
      model: ControllerModelID(vendorID: device.vendorID, productID: device.productID),
      claimed: claimed
    )
  }

  /// GIP's variant follows the transport, which is raw USB here.
  private var variant: PhysicalProtocolVariantID? { profile.physicalProtocolVariant ?? .usb }
}

/// Errors reported before the probe opens or writes to a physical device.
public enum ControllerRecordProbeError: Error, Equatable, LocalizedError, Sendable {
  /// The record does not decode or does not build a runtime profile; the value is the reason.
  case invalidProfile(String)
  /// The record's protocol is one the probe cannot drive; the value names it.
  case unsupportedProtocol(String)
  /// The record names an 8BitDo bootloader identity, which OJD sends nothing.
  case bootloaderIdentity

  /// The description of the error for the user.
  public var errorDescription: String? {
    switch self {
    case .invalidProfile(let message): message
    case .bootloaderIdentity: "The record probe sends nothing to a controller in bootloader mode"
    case .unsupportedProtocol(let binding):
      "The signing-free record probe does not support protocol \(binding)"
    }
  }
}
