import Foundation

/// Answers the GIP authentication sub-protocol (command 0x06) of a controller.
///
/// Each answer has the right framing and a zero-filled payload. The handler tracks the device
/// power state as authentication progresses.
final class GIPAuthHandler {
  /// The power state of the device, driven by the auth messages it sent.
  private(set) var deviceState: GIPDeviceState = .start

  /// The host state that answers each device state.
  private static let responseMap: [GIPAuthState: GIPAuthState] = [
    .devInit: .hostInit, .devCertificate: .hostResponse1, .devIntermediate: .hostResponse2,
    .devData1: .hostResponse3, .devData2: .hostResponse4, .devFinal: .hostResponse5,
    .devComplete: .hostComplete,
  ]

  /// Reads an auth message from the device and builds the packet that answers it.
  ///
  /// The first message moves the device state from start to enroll, and a complete or status
  /// message moves it from enroll to full power. The sub-header is checked first.
  /// - Returns: The packet to send, or nil when the payload is too short, is not from the device,
  ///   names an unknown state, or needs no answer.
  func handleAuthMessage(payload: Data, sequencer: inout GIPSequencer) -> [UInt8]? {
    guard payload.count >= 6 else {
      print("[GIPAuth] Auth payload too short: \(payload.count) bytes")
      return nil
    }

    let type = payload[0]
    let state = payload[2]

    guard type == GIPAuthType.device else {
      print("[GIPAuth] Unexpected auth type: 0x\(String(type, radix: 16))")
      return nil
    }

    guard let deviceAuthState = GIPAuthState(rawValue: state) else {
      print("[GIPAuth] Unknown auth state: 0x\(String(state, radix: 16))")
      return nil
    }

    print("[GIPAuth] Received \(deviceAuthState)")

    if deviceState == .start {
      deviceState = .enroll
      print("[GIPAuth] State -> \(deviceState)")
    }

    if deviceAuthState == .devComplete || deviceAuthState == .devStatus {
      if deviceState == .enroll {
        deviceState = .fullPower
        print("[GIPAuth] State -> \(deviceState)")
      }
    }

    guard let responseState = Self.responseMap[deviceAuthState] else {
      print("[GIPAuth] No response needed for \(deviceAuthState)")
      return nil
    }

    let responsePayload = buildAuthResponse(state: responseState)
    let packet = authPacket(payload: responsePayload, sequencer: &sequencer)
    print("[GIPAuth] Prepared \(responseState)")
    return packet
  }

  /// The auth payload of the host's answer in `state`: the type, version, state, a zero byte, the
  /// big-endian payload size, and a zero-filled body.
  ///
  /// Empty when `state` is not a host state.
  func buildAuthResponse(state: GIPAuthState) -> [UInt8] {
    guard let size = state.expectedPayloadSize else { return [] }
    var response: [UInt8] = [
      GIPAuthType.host, GIPAuthType.version, state.rawValue, 0x00, UInt8((size >> 8) & 0xFF),
      UInt8(size & 0xFF),
    ]
    response += [UInt8](repeating: 0, count: size)
    return response
  }

  /// Wraps `payload` in a command 0x06 packet.
  ///
  /// A payload over 127 bytes uses a two-byte length with the high bit set on the first byte.
  private func authPacket(payload: [UInt8], sequencer: inout GIPSequencer) -> [UInt8] {
    let seq = sequencer.next(for: GIPCommand.authenticate, options: GIPOption.internal)
    var packet: [UInt8] = [GIPCommand.authenticate, GIPOption.internal, seq]

    if payload.count > 127 {
      let len = payload.count
      packet.append(UInt8((len >> 8) & 0x7F) | 0x80)
      packet.append(UInt8(len & 0xFF))
    } else {
      packet.append(UInt8(payload.count))
    }

    packet += payload
    return packet
  }
}
