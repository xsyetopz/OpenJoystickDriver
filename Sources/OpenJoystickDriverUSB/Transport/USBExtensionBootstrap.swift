import Foundation
import OpenJoystickDriverKit

/// Injectable bootstrap operations; test providers perform no hardware writes by default.
struct USBExtensionBootstrapOperations: Sendable {
  /// Monotonic discovery clock used to limit retries.
  let clock: @Sendable () -> TimeInterval
  /// Prepares a vacant device and reports whether configuration changed.
  let prepare: @Sendable (USBTransportDevice) async throws -> Bool

  /// Creates a bootstrap dependency with a monotonic system clock by default.
  init(
    clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    prepare: @escaping @Sendable (USBTransportDevice) async throws -> Bool
  ) {
    self.clock = clock
    self.prepare = prepare
  }
}

/// Live device facts used to reject writes against configured or owned interfaces.
struct USBExtensionBootstrapState {
  /// The device's own registry configuration value, or nil when not published.
  let configuration: UInt8?
  /// Whether any interface service already exists beneath the device.
  let hasInterfaces: Bool
  /// Whether the device's exclusive owner names another process.
  let ownedByAnotherClient: Bool

  /// Whether a descriptor/control read may establish that this device is unconfigured.
  var canInspect: Bool {
    (configuration == nil || configuration == 0) && !hasInterfaces && !ownedByAnotherClient
  }
}

/// Device-level preparation before the interface-scoped extension can match.
enum USBExtensionBootstrap {
  /// Validates a vacant device and configures it only after a live GET_CONFIGURATION returns zero.
  ///
  /// Native operations are supplied separately so races and rejected writes can be tested without
  /// accessing hardware. The final state read and configuration write have no suspension between.
  static func prepare(
    state: () throws -> USBExtensionBootstrapState,
    descriptor: () throws -> [UInt8],
    currentConfiguration: () async throws -> UInt8,
    configure: () throws -> Void
  ) async throws -> Bool {
    guard try state().canInspect else { return false }
    let bytes = try descriptor()
    guard try supportsGIPInterface(bytes) else { return false }
    guard try state().canInspect else { return false }
    guard try await currentConfiguration() == 0 else { return false }
    try Task.checkCancellation()
    guard try state().canInspect else { return false }
    try configure()
    return true
  }

  /// Requires configuration 1's data interface to match the same GIP contract as the extension.
  static func supportsGIPInterface(_ bytes: [UInt8]) throws -> Bool {
    let parsed = try PassiveUSBConfigurationDescriptorParser.parse(bytes)
    guard bytes[5] == 1,
      let signature = ProtocolInterfaceSignature.bundled(.xboxGIP, variant: .usb),
      let interfaceNumber = signature.requiredInterfaceNumber
    else { return false }
    return parsed.interfaces.contains { interface in
      interface.number == interfaceNumber && interface.alternateSetting == 0
        && interface.interfaceClass == signature.interfaceClass
        && interface.interfaceSubclass == signature.interfaceSubclass
        && interface.interfaceProtocol == signature.interfaceProtocol
        && interface.endpoints.contains { $0.transferType == "interrupt" && $0.address & 0x80 != 0 }
        && interface.endpoints.contains { $0.transferType == "interrupt" && $0.address & 0x80 == 0 }
    }
  }
}
