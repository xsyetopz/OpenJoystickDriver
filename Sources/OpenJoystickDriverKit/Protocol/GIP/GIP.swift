import Foundation

/// The command byte of a GIP packet.
public enum GIPCommand {
  /// Command byte of an acknowledgement.
  static let acknowledge: UInt8 = 0x01
  /// Command byte of the controller's announce packet.
  static let announce: UInt8 = 0x02
  /// Command byte of a status packet.
  static let status: UInt8 = 0x03
  /// Command byte of a power-state packet.
  static let power: UInt8 = 0x05
  /// Command byte of the authentication sub-protocol.
  static let authenticate: UInt8 = 0x06
  /// Command byte of a virtual-key (Guide button) packet.
  static let virtualKey: UInt8 = 0x07
  /// Command byte of a rumble output packet.
  static let rumble: UInt8 = 0x09
  /// Command byte of an LED output packet.
  static let led: UInt8 = 0x0A
  /// Command byte of an input report.
  static let input: UInt8 = 0x20
}

/// Flags in the options byte of a GIP packet header.
public enum GIPOption {
  /// The sender asks for an acknowledgement.
  static let acknowledge: UInt8 = 0x10
  /// The packet is internal to the GIP session.
  static let `internal`: UInt8 = 0x20
  /// The packet starts a fragmented transfer.
  static let chunkStart: UInt8 = 0x40
  /// The packet is a fragment of a transfer.
  static let chunk: UInt8 = 0x80
}

/// Power states of a GIP device.
public enum GIPDeviceState: UInt8, Sendable, CustomStringConvertible {
  /// The device is starting.
  case start = 0x00
  /// The device is stopping.
  case stop = 0x01
  /// The device is in standby.
  case standby = 0x02
  /// The device runs at full power.
  case fullPower = 0x03
  /// The device is off.
  case off = 0x04
  /// The device is quiescing.
  case quiesce = 0x05
  /// The device is enrolling.
  case enroll = 0x06
  /// The device is resetting.
  case reset = 0x07

  /// A short uppercase label for the device state.
  public var description: String {
    switch self {
    case .start: "START"
    case .stop: "STOP"
    case .standby: "STANDBY"
    case .fullPower: "FULL_POWER"
    case .off: "OFF"
    case .quiesce: "QUIESCE"
    case .enroll: "ENROLL"
    case .reset: "RESET"
    }
  }
}

/// States of the authentication sub-protocol; states below 0x20 come from the device and the rest
/// from the host.
public enum GIPAuthState: UInt8, Sendable, CustomStringConvertible {
  // Device -> Host
  /// The device's first message; the host answers with ``hostInit``.
  case devInit = 0x01
  /// The device's certificate; the host answers with ``hostResponse1``.
  case devCertificate = 0x02
  /// The device's intermediate message; the host answers with ``hostResponse2``.
  case devIntermediate = 0x03
  /// The device's first data message; the host answers with ``hostResponse3``.
  case devData1 = 0x04
  /// The device's second data message; the host answers with ``hostResponse4``.
  case devData2 = 0x05
  /// The device's final message; the host answers with ``hostResponse5``.
  case devFinal = 0x06
  /// The device completes authentication; the host answers with ``hostComplete`` and the
  /// device state becomes full power.
  case devComplete = 0x07
  /// The device reports its status; the host sends no response, and the device state becomes
  /// full power.
  case devStatus = 0x08
  /// The device's first acknowledgement; the host sends no response.
  case devAck1 = 0x0B
  /// The device's second acknowledgement; the host sends no response.
  case devAck2 = 0x0C
  // Host -> Device
  /// The host's answer to ``devInit``.
  case hostInit = 0x21
  /// The host's answer to ``devCertificate``.
  case hostResponse1 = 0x22
  /// The host's answer to ``devIntermediate``.
  case hostResponse2 = 0x23
  /// The host's answer to ``devData1``.
  case hostResponse3 = 0x24
  /// The host's answer to ``devData2``.
  case hostResponse4 = 0x25
  /// The host's answer to ``devFinal``.
  case hostResponse5 = 0x26
  /// The host's answer to ``devComplete``.
  case hostComplete = 0x27

  /// The payload size of a host-to-device message in bytes; nil for a device-to-host state.
  public var expectedPayloadSize: Int? {
    switch self {
    case .hostInit: 40
    case .hostResponse1: 176
    case .hostResponse2: 772
    case .hostResponse3: 132
    case .hostResponse4: 68
    case .hostResponse5: 36
    case .hostComplete: 68
    default: nil
    }
  }

  /// Whether the state is a device-to-host message.
  public var isDeviceToHost: Bool { rawValue < 0x20 }

  /// A short uppercase label for the auth state.
  public var description: String {
    switch self {
    case .devInit: "DEV_INIT"
    case .devCertificate: "DEV_CERTIFICATE"
    case .devIntermediate: "DEV_INTERMEDIATE"
    case .devData1: "DEV_DATA_1"
    case .devData2: "DEV_DATA_2"
    case .devFinal: "DEV_FINAL"
    case .devComplete: "DEV_COMPLETE"
    case .devStatus: "DEV_STATUS"
    case .devAck1: "DEV_ACK_1"
    case .devAck2: "DEV_ACK_2"
    case .hostInit: "HOST_INIT"
    case .hostResponse1: "HOST_RESPONSE_1"
    case .hostResponse2: "HOST_RESPONSE_2"
    case .hostResponse3: "HOST_RESPONSE_3"
    case .hostResponse4: "HOST_RESPONSE_4"
    case .hostResponse5: "HOST_RESPONSE_5"
    case .hostComplete: "HOST_COMPLETE"
    }
  }
}

/// The markers of the auth message type and the protocol version.
public enum GIPAuthType {
  /// Type of a message from the host.
  static let host: UInt8 = 0x41  // 'A'
  /// Type of a message from the device.
  static let device: UInt8 = 0x42  // 'B'
  /// The version of the auth message format.
  static let version: UInt8 = 0x01
}
