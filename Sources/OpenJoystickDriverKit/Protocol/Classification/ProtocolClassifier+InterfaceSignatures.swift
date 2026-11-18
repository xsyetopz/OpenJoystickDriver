import Foundation

/// A USB interface class, subclass and protocol triple that binds a family variant without a
/// catalog record, from the bundled protocol descriptions.
public struct ProtocolInterfaceSignature: Equatable, Sendable {
  /// The protocol family that the class triple identifies.
  public let protocolID: PhysicalProtocolID
  /// The variant of the family that the class triple identifies.
  public let variant: PhysicalProtocolVariantID
  /// The USB interface class.
  public let interfaceClass: UInt8
  /// The USB interface subclass.
  public let interfaceSubclass: UInt8
  /// The USB interface protocol.
  public let interfaceProtocol: UInt8
  /// GIP shares its triple across interfaces; only this interface carries data.
  public let requiredInterfaceNumber: UInt8?

  /// The bundled signature of the `variant` of `protocolID`, or nil when it has none.
  public static func bundled(
    _ protocolID: PhysicalProtocolID,
    variant: PhysicalProtocolVariantID
  ) -> Self? {
    ProtocolClassifier.signatures.first { $0.protocolID == protocolID && $0.variant == variant }
  }

  /// Whether `interface` has this signature's class, subclass and protocol.
  func matches(_ interface: PhysicalInterfaceSignature) -> Bool {
    interface.interfaceClass == interfaceClass && interface.interfaceSubclass == interfaceSubclass
      && interface.interfaceProtocol == interfaceProtocol
  }
}

extension ProtocolClassifier {
  /// The `interfaceSignatures` of the bundled protocol descriptions (`Resources/Protocols/`), in
  /// family order, as ``ProtocolDescription`` decodes them.
  ///
  /// The Xbox triples are pinned against Linux `xpad.c` at the `ControllerSources.lock.json`
  /// commit: the `'X','B',0` table entry, `XPAD_XBOX360_VENDOR` (subclass 93, protocols 1 and 129),
  /// `XPAD_XBOXONE_VENDOR` (subclass 71, protocol 208), the GIP data interface number, and the
  /// interrupt IN+OUT endpoint requirement in `xpad_probe`.
  static var signatures: [ProtocolInterfaceSignature] {
    PhysicalProtocolID.allCases.flatMap {
      ProtocolDescription.bundled[$0]?.interfaceSignatures ?? []
    }
      + DocumentedProtocolFamilies.all.flatMap(\.interfaceSignatures)
  }
}
