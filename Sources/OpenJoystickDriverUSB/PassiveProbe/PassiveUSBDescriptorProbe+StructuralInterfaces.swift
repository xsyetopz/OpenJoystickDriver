import Foundation
import OpenJoystickDriverKit

extension PassiveUSBDescriptorProbe {
  /// Walks a configuration descriptor by length and type only.
  ///
  /// Nil when the descriptor framing itself is broken. An interface alternate setting whose
  /// endpoints do not decode (a reserved address bit, a duplicate address, or a count other than
  /// declared) keeps its class triple but reports no endpoints, so claimed-interface validation
  /// rejects it if OJD would claim it.
  static func structuralInterfaces(
    _ bytes: [UInt8],
    configurationValue: UInt8?,
    route: USBTransportRoute
  ) -> [PhysicalInterfaceSignature]? {
    guard bytes.count >= 9, bytes[1] == 2 else { return nil }
    var alternates: [StructuralAlternate] = []
    var offset = 0
    while offset < bytes.count {
      let length = Int(bytes[offset])
      guard length >= 2, offset + length <= bytes.count else { return nil }
      let chunk = Array(bytes[offset..<(offset + length)])
      if chunk[1] == 4, length >= 9 {
        alternates.append(StructuralAlternate(header: chunk))
      } else if chunk[1] == 5, length >= 7, !alternates.isEmpty {
        alternates[alternates.count - 1].add(endpoint: chunk)
      }
      offset += length
    }
    return alternates.map { $0.signature(configurationValue: configurationValue, route: route) }
  }
}

/// One alternate setting of an interface with its endpoints, as a structural walk reads it.
private struct StructuralAlternate {
  /// The interface descriptor bytes.
  let header: [UInt8]
  /// The endpoints in the order the walk read them.
  var endpoints: [PhysicalEndpointSignature] = []
  /// Whether an endpoint is invalid or repeated.
  var isMalformed = false

  /// Creates an alternate setting from its interface descriptor bytes.
  init(header: [UInt8]) { self.header = header }

  /// Adds the endpoint descriptor `chunk`.
  mutating func add(endpoint chunk: [UInt8]) {
    let address = chunk[2]
    guard address & 0x70 == 0, address & 0x0F != 0,
      !endpoints.contains(where: { $0.address == address })
    else {
      isMalformed = true
      return
    }
    let transferType: USBEndpointTransferType =
      switch chunk[3] & 0x03 {
      case 0: .control
      case 1: .isochronous
      case 2: .bulk
      default: .interrupt
      }
    endpoints.append(
      PhysicalEndpointSignature(
        address: address,
        direction: address & 0x80 == 0 ? .out : .in,
        transferType: transferType,
        maxPacketSize: UInt16(chunk[4]) | (UInt16(chunk[5]) << 8),
        interval: chunk[6]
      )
    )
  }

  /// Returns the interface signature of the alternate setting; it is complete when no endpoint is
  /// malformed and every declared endpoint is present.
  func signature(configurationValue: UInt8?, route: USBTransportRoute) -> PhysicalInterfaceSignature
  {
    let isComplete = !isMalformed && endpoints.count == Int(header[4])
    return PhysicalInterfaceSignature(
      interfaceNumber: header[2],
      alternateSetting: header[3],
      interfaceClass: header[5],
      interfaceSubclass: header[6],
      interfaceProtocol: header[7],
      configurationValue: configurationValue,
      hostTransport: .usb,
      accessBackend: route == .usbExtension ? .usbExtension : nil,
      usbRoute: route,
      endpoints: isComplete ? endpoints : nil
    )
  }
}
