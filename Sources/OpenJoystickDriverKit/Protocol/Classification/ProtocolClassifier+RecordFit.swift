import Foundation

extension ProtocolClassifier {
  /// Whether no mode of `record` fits the HID interfaces that `backend` observed.
  ///
  /// A raw-USB record fits none of them, because it claims a USB interface of its own. A HID
  /// record fits none when its mode names an interface range that holds no observed interface.
  static func recordFitsNoInterface(
    _ record: DeviceRuntimeProfile,
    interfaces: [PhysicalInterfaceSignature],
    backend: DeviceAccessBackend
  ) -> Bool {
    guard backend == .hid, !interfaces.isEmpty else { return false }
    if record.usesRawUSB { return true }
    guard let range = record.interfaceRange else { return false }
    let numbers = interfaces.compactMap(\.interfaceNumber)
    return !numbers.isEmpty && !numbers.contains(where: range.contains)
  }

  /// The `HIDDescriptor` binding that serves a device whose `record` fits none of its interfaces,
  /// or nil when a HID interface fails the descriptor contract or the record states that macOS
  /// serves the pad.
  static func descriptorFallback(
    for record: DeviceRuntimeProfile,
    device: PhysicalDevice,
    interfaces: [PhysicalInterfaceSignature],
    backend: DeviceAccessBackend,
    database: SDLGameControllerDatabase
  ) -> ProtocolClassification? {
    guard !(record.statesServer && record.server == .system),
      let interface = descriptorInterface(interfaces)
    else { return nil }
    let resolution = database.resolve(device: device, interface: interface)
    var binding = ProtocolBinding(
      protocolID: .hidDescriptor,
      variant: nil,
      accessBackend: backend,
      interfaceNumber: interface.interfaceNumber,
      rule: resolution.usageMap == nil ? .hidDescriptor : .sdlGameControllerDB,
      matchedPredicates: [.hidDescriptorContract],
      record: nil,
      sdl: resolution
    )
    binding.unfitRecordID = record.recordID
    return .bound(binding)
  }

  /// The rejection of a record that fits no interface and has no fallback.
  ///
  /// A raw-USB record reports the interface mismatch; any other record keeps `result`.
  static func mismatch(
    of record: DeviceRuntimeProfile,
    kept result: ProtocolClassification
  ) -> ProtocolClassification {
    guard record.usesRawUSB else { return result }
    return .unsupported(
      .interfaceContractMismatch,
      rejected: ProtocolBindingResult.RejectedCandidate(
        protocolID: record.physicalProtocolID,
        reason: .interfaceContractMismatch,
        catalogRecordID: record.recordID
      )
    )
  }
}
