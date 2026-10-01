import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A HID interface observed over `host`, as IOHID reports it, without descriptor facts.
func hostHIDInterface(_ host: PhysicalTransport?) -> PhysicalInterfaceSignature {
  PhysicalInterfaceSignature(hostTransport: host, accessBackend: .ioHID)
}

/// A HID interface observed over `host` whose descriptor satisfies the `hid.descriptor`
/// contract.
func gamepadHIDInterface(host: PhysicalTransport?) -> PhysicalInterfaceSignature {
  PhysicalInterfaceSignature(
    hostTransport: host,
    accessBackend: .ioHID,
    hidLayout: HIDLayoutSummary(reportDescriptor: Data(GamepadHIDDescriptor.descriptor))
  )
}

/// A USB HID interface of a Steam Controller, numbered as Linux `hid-steam.c` describes the
/// layout (hid-steam.c:1098–1108). The descriptors are synthetic, not a macOS capture: a
/// gamepad interface is a vendor collection with a 64-byte input and a 64-byte feature report,
/// the only kind with a feature report; any other interface is a boot keyboard without one.
func steamHIDInterface(number: UInt8, gamepad: Bool = true) -> PhysicalInterfaceSignature {
  let descriptor: [UInt8] =
    gamepad
    ? [
      0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95,
      0x40, 0x09, 0x01, 0x81, 0x02, 0x09, 0x01, 0xB1, 0x02, 0xC0,
    ]
    : [
      0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7, 0x15, 0x00, 0x25,
      0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02, 0xC0,
    ]
  return PhysicalInterfaceSignature(
    interfaceNumber: number,
    hostTransport: .usb,
    accessBackend: .ioHID,
    hidLayout: HIDLayoutSummary(reportDescriptor: Data(descriptor))
  )
}

/// The host link a catalog row is observed on by default: USB, except for a Bluetooth-only
/// pad, whose USB link only charges it.
func defaultHost(of record: DeviceRuntimeProfile) -> PhysicalTransport {
  record.quirks.contains(.bluetoothOnly) ? .bluetoothClassic : .usb
}

/// Binds a catalog model on its family's access path, as discovery does, and returns the
/// driver the runtime would construct. A HID row is observed over `host`, or its default host;
/// a raw-USB row claims `transportProfile`, or the record's profile, without interface facts.
func catalogParser(
  _ identifier: DeviceIdentifier,
  host: PhysicalTransport? = nil,
  transportProfile: DeviceTransportProfile? = nil,
  registry: ProtocolDriverRegistry = ProtocolDriverRegistry()
) throws -> any PhysicalProtocolDriver {
  let record = try #require(registry.record(for: identifier))
  let isRawUSB = record.usesRawUSB
  let device = PhysicalDevice(
    vendorID: identifier.controllerIdentity.vendorID,
    productID: identifier.controllerIdentity.productID,
    interfaces: isRawUSB ? nil : [gamepadHIDInterface(host: host ?? defaultHost(of: record))]
  )
  let classification = registry.classify(device, backend: isRawUSB ? .ioUSBHost : .ioHID)
  guard case .bound(let binding) = classification else {
    Issue.record("\(identifier) did not bind: \(classification)")
    throw CatalogBindingFailure()
  }
  return try registry.makeDriver(
    for: binding,
    identifier: identifier,
    claimed: isRawUSB
      ? USBTransportResolution(profile: transportProfile ?? record.transportProfile) : nil
  ).get()
}

struct CatalogBindingFailure: Error {}

/// The unsupported outcome that names the family which matched and failed, and the catalog row
/// that named it, if any.
func rejection(
  _ reason: ProtocolBindingReason,
  _ protocolID: PhysicalProtocolID,
  record: String? = nil
) -> ProtocolClassification {
  .unsupported(
    reason,
    rejected: ProtocolBindingResult.RejectedCandidate(
      protocolID: protocolID,
      reason: reason,
      catalogRecordID: record
    )
  )
}

/// The `vvvv-pppp` catalog record ID of an identity.
func recordID(_ vendorID: UInt16, _ productID: UInt16) -> String {
  String(format: "%04x-%04x", vendorID, productID)
}

extension DeviceRuntimeProfile {
  /// This profile under another record ID; everything it runs with is unchanged.
  func withRecordID(_ recordID: String?) -> DeviceRuntimeProfile {
    DeviceRuntimeProfile(
      recordID: recordID,
      transportProfile: transportProfile,
      physicalProtocolID: physicalProtocolID,
      physicalProtocolVariant: physicalProtocolVariant,
      quirks: quirks,
      capabilityDelta: capabilityDelta,
      preferredBackends: preferredBackends,
      gipStartupPackets: gipStartupPackets,
      gipKeepAlivePolicy: gipKeepAlivePolicy,
      assemblyPolicy: assemblyPolicy,
      ownership: ownership,
      rumbleTemplate: rumbleTemplate
    )
  }
}
