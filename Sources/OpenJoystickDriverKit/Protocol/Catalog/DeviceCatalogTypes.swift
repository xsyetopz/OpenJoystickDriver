import Foundation

/// Per-device transport configuration resolved from controller records.
public struct DeviceTransportProfile: Equatable, Sendable {
  public let inputEndpoint: UInt8
  public let outputEndpoint: UInt8
  public let interfaceNumber: UInt8
  public let alternateSetting: UInt8
  public let hasInterfaceOverride: Bool
  public let hasEndpointOverride: Bool
  /// When true, pipeline calls setConfiguration(1) before claiming interface.
  /// Required for controllers that enumerate unconfigured (e.g. Vader 5S).
  public let needsSetConfiguration: Bool
  /// Delay after protocol handshake and before the first IN read.
  public let postHandshakeSettleNanoseconds: UInt64

  public init(
    inputEndpoint: UInt8,
    outputEndpoint: UInt8,
    interfaceNumber: UInt8 = 0,
    alternateSetting: UInt8 = 0,
    hasInterfaceOverride: Bool = false,
    hasEndpointOverride: Bool = false,
    needsSetConfiguration: Bool,
    postHandshakeSettleNanoseconds: UInt64 = 0
  ) {
    self.inputEndpoint = inputEndpoint
    self.outputEndpoint = outputEndpoint
    self.interfaceNumber = interfaceNumber
    self.alternateSetting = alternateSetting
    self.hasInterfaceOverride = hasInterfaceOverride
    self.hasEndpointOverride = hasEndpointOverride
    self.needsSetConfiguration = needsSetConfiguration
    self.postHandshakeSettleNanoseconds = postHandshakeSettleNanoseconds
  }

  public static let gipDefault = Self(
    inputEndpoint: 0x82,
    outputEndpoint: 0x02,
    needsSetConfiguration: false
  )
}

/// Controller protocol family/variant used for long-term compatibility metadata.
public enum ControllerProtocolVariant: String, Codable, Hashable, Sendable {
  case xboxOriginal
  case xbox360
  case xbox360Wireless
  case xboxOne
  case dualShock3
  case dualShock4
  case dualSense
  case steamController
  case switchPro
  case xboxAdaptiveJoystick
  case genericHID
  case unknown
}

/// Stable mapping flags modeled after Linux xpad's per-device quirks.
public struct ControllerMappingOptions: OptionSet, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) { self.rawValue = rawValue }

  public static let dpadToButtons = Self(rawValue: 1 << 0)
  public static let triggersToButtons = Self(rawValue: 1 << 1)
  public static let sticksToNull = Self(rawValue: 1 << 2)
  public static let shareButton = Self(rawValue: 1 << 3)
  public static let paddles = Self(rawValue: 1 << 4)
  public static let profileButton = Self(rawValue: 1 << 5)
  public static let shareOffset = Self(rawValue: 1 << 6)

  public var names: [String] {
    var result: [String] = []
    if contains(.dpadToButtons) { result.append("dpadToButtons") }
    if contains(.triggersToButtons) { result.append("triggersToButtons") }
    if contains(.sticksToNull) { result.append("sticksToNull") }
    if contains(.shareButton) { result.append("shareButton") }
    if contains(.paddles) { result.append("paddles") }
    if contains(.profileButton) { result.append("profileButton") }
    if contains(.shareOffset) { result.append("shareOffset") }
    return result
  }
}

/// Whether the GIP parser sends periodic host-side keep-alive packets.
public enum GIPKeepAlivePolicy: String, Codable, Sendable {
  case enabled
  case disabled
}

/// Complete runtime profile for one physical controller model.
public struct DeviceRuntimeProfile: Sendable {
  public let parserName: String
  public let virtualProfile: VirtualDeviceProfile
  public let transportProfile: DeviceTransportProfile
  public let protocolVariant: ControllerProtocolVariant
  public let mappingFlags: [String]
  public let mappingOptions: ControllerMappingOptions
  public let preferredBackends: [VirtualControllerBackendID]
  public let gipStartupPackets: [GIPStartupPacket]
  public let gipKeepAlivePolicy: GIPKeepAlivePolicy
  public let hardwareVerified: Bool
}
