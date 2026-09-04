import Foundation

private let gipDpadMask: UInt8 = 0x0F
private let gipGuideButtonMask: UInt8 = 0x03
private let gipHandshakeMaxAttempts = 3
private let gipHandshakeRetryDelays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000]
private let gipInitDelayNanoseconds: UInt64 = 50_000_000
private let gipStickMax: Float = 32767
private let gipTriggerMax: Float = 1023
private let gipMaximumVarintBytes = 5
private let gipRumbleAllMotors: UInt8 = 0x0F
private let gipRumbleSubCommandLength: UInt8 = 0x09
private let gipRumbleDefaultDuration: UInt8 = 0xFF
private let gipStatusSubCommandLength: UInt8 = 3
private let gipRumbleTransferTimeoutMs: UInt32 = 2000

private struct GIPFrame {
  let command: UInt8
  let options: UInt8
  let sequence: UInt8
  let payload: Data
  let chunkOffset: Int
}

/// Errors that ``GIPParser`` can throw during the handshake or while parsing packets.
public enum GIPError: Error, Sendable {
  /// The controller did not complete the handshake within the allowed number of attempts.
  case handshakeTimeout
  /// The handshake failed for a specific reason (e.g. no USB handle was provided).
  case handshakeFailed(String)
  /// A received packet is too short or its declared length does not match the actual data.
  case malformedPacket(String)
  /// Authentication sub-protocol error.
  case authFailed(String)
}

/// Parser for Xbox One (GIP) controllers connected over USB.
///
/// Sends the three-packet GIP init sequence on connection, then parses
/// incoming interrupt-transfer packets into ``ControllerEvent`` values.
/// Sends a keep-alive ping every ~4 seconds when the device profile permits it.
public final class GIPParser: InputParser, PhysicalRumbleOutput, USBDeferredOutputProvider,
  @unchecked Sendable
{

  // MARK: - Thread safety
  //
  // @unchecked Sendable safety:
  // - Only the owning DevicePipeline actor accesses mutable state
  //   (prevButtons, sequencer, authHandler, handle) through
  //   feedHIDData/feedUSBData, so access is serial.

  private let outEndpoint: UInt8
  private let startupPackets: [GIPStartupPacket]
  public let keepAlivePolicy: GIPKeepAlivePolicy
  private let mappingOptions: ControllerMappingOptions

  private var sequencer = GIPSequencer()
  private let authHandler: GIPAuthHandler
  private var pendingInput = Data()
  private var pendingUSBOutputPackets: [[UInt8]] = []

  /// Current device state, driven by auth progress.
  public var deviceState: GIPDeviceState { authHandler.deviceState }

  private var prevButtons0: UInt8 = 0
  private var prevButtons1: UInt8 = 0
  private var prevButtons2: UInt8 = 0
  private var prevLT: UInt16?
  private var prevRT: UInt16?
  private var prevLSX: Int16?
  private var prevLSY: Int16?
  private var prevRSX: Int16?
  private var prevRSY: Int16?

  /// Creates a new GIPParser with the given endpoint configuration.
  public init(
    transportProfile: DeviceTransportProfile = .gipDefault,
    startupPackets: [GIPStartupPacket] = GIPStartupPacket.defaultSequence,
    keepAlivePolicy: GIPKeepAlivePolicy = .enabled,
    mappingOptions: ControllerMappingOptions = []
  ) {
    self.outEndpoint = transportProfile.outputEndpoint
    self.startupPackets = startupPackets
    self.keepAlivePolicy = keepAlivePolicy
    self.mappingOptions = mappingOptions
    self.authHandler = GIPAuthHandler()
  }

  // MARK: - InputParser

  /// Sends the GIP init sequence to the controller.
  public func performHandshake(handle: (any USBTransportSession)?) async throws {
    guard let handle else {
      throw GIPError.handshakeFailed("No USB handle provided for GIP handshake")
    }
    for attempt in 0..<gipHandshakeMaxAttempts {
      do {
        try await sendInitSequence(handle: handle)
        print(
          "[GIPParser] Init sequence sent" + " (attempt \(attempt + 1))"
            + " outEP=0x\(String(outEndpoint, radix: 16))"
        )
        return
      } catch {
        print("[GIPParser] Init attempt \(attempt + 1) " + "failed: \(error)")
        guard attempt < gipHandshakeMaxAttempts - 1 else { throw GIPError.handshakeTimeout }
        try await Task.sleep(nanoseconds: gipHandshakeRetryDelays[attempt])
      }
    }
  }

  /// Sends the periodic host-side GIP status packet (CMD=0x03).
  public func keepAlive(handle: (any USBTransportSession)?) async throws {
    guard keepAlivePolicy == .enabled else { return }
    guard let handle else { return }
    let seq = sequencer.next(for: GIPCommand.status)
    let packet: [UInt8] = [
      GIPCommand.status, GIPOption.internal, seq, gipStatusSubCommandLength, 0x00, 0x00, 0x00
    ]
    _ = try await handle.writeInterruptPacket(
      endpoint: outEndpoint,
      data: packet,
      timeout: gipRumbleTransferTimeoutMs
    )
  }

  /// Builds the ACK frame required by a GIP packet with the acknowledge option bit set.
  static func acknowledgementPacket(
    command: UInt8,
    options: UInt8,
    sequence: UInt8,
    totalLength: UInt16,
    remaining: UInt16 = 0
  ) -> [UInt8] {
    let clientAndInternal = (options & 0x0F) | GIPOption.internal
    return [
      GIPCommand.acknowledge, clientAndInternal, sequence, 9, 0, command, clientAndInternal,
      UInt8(truncatingIfNeeded: totalLength), UInt8(truncatingIfNeeded: totalLength >> 8), 0, 0,
      UInt8(truncatingIfNeeded: remaining), UInt8(truncatingIfNeeded: remaining >> 8)
    ]
  }

  /// Parses complete GIP frames buffered across one or more interrupt transfers.
  public func parse(data: Data) throws -> [ControllerEvent] {
    pendingInput.append(data)
    var events: [ControllerEvent] = []
    while let frame = try nextFrame() { events += process(frame) }
    return events
  }

  private func nextFrame() throws -> GIPFrame? {
    guard pendingInput.count >= 4 else { return nil }
    let bytes = Array(pendingInput)

    let command = bytes[0]
    let options = bytes[1]
    let sequence = bytes[2]
    guard let (payloadLength, afterLength) = try decodeVarint(bytes, start: 3) else { return nil }
    var headerLength = afterLength
    var chunkOffset = 0
    if options & GIPOption.chunk != 0 {
      guard let (offset, afterOffset) = try decodeVarint(bytes, start: headerLength) else {
        return nil
      }
      chunkOffset = offset
      headerLength = afterOffset
    }
    guard pendingInput.count >= headerLength + payloadLength else { return nil }

    let payload = Data(bytes[headerLength..<(headerLength + payloadLength)])
    pendingInput.removeFirst(headerLength + payloadLength)
    return GIPFrame(
      command: command,
      options: options,
      sequence: sequence,
      payload: payload,
      chunkOffset: chunkOffset
    )
  }

  private func decodeVarint(_ bytes: [UInt8], start: Int) throws -> (Int, Int)? {
    var value = 0
    var shift = 0
    for index in 0..<gipMaximumVarintBytes {
      let offset = start + index
      guard offset < bytes.count else { return nil }
      let byte = bytes[offset]
      value |= Int(byte & 0x7F) << shift
      if byte & 0x80 == 0 { return (value, offset + 1) }
      shift += 7
    }
    throw GIPError.malformedPacket("Header varint exceeds \(gipMaximumVarintBytes) bytes")
  }

  private func process(_ frame: GIPFrame) -> [ControllerEvent] {
    let totalLength = frame.chunkOffset + frame.payload.count
    if frame.options & GIPOption.acknowledge != 0 {
      sendAcknowledgement(for: frame, totalLength: totalLength)
    }
    guard frame.options & GIPOption.chunk == 0 else { return [] }

    switch frame.command {
    case GIPCommand.input: return parseMainInput(payload: frame.payload)
    case GIPCommand.virtualKey: return parseGuideButton(payload: frame.payload)
    case GIPCommand.authenticate:
      if let packet = authHandler.handleAuthMessage(payload: frame.payload, sequencer: &sequencer) {
        pendingUSBOutputPackets.append(packet)
      }
      return []
    default: return []
    }
  }

  private func sendAcknowledgement(for frame: GIPFrame, totalLength: Int) {
    guard let length = UInt16(exactly: totalLength) else { return }
    let packet = Self.acknowledgementPacket(
      command: frame.command,
      options: frame.options,
      sequence: frame.sequence,
      totalLength: length
    )
    pendingUSBOutputPackets.append(packet)
  }

  public func consumeUSBOutputPackets() -> [[UInt8]] {
    defer { pendingUSBOutputPackets.removeAll(keepingCapacity: true) }
    return pendingUSBOutputPackets
  }

  /// Sends a GIP rumble command (CMD=0x09) to the physical controller.
  ///
  /// - Parameters:
  ///   - handle: Active USB device handle for the physical controller.
  ///   - left: Left main motor intensity (0–255).
  ///   - right: Right main motor intensity (0–255).
  ///   - ltMotor: Left trigger motor intensity (0–255).
  ///   - rtMotor: Right trigger motor intensity (0–255).
  public func sendRumble(
    handle: any USBTransportSession,
    left: UInt8,
    right: UInt8,
    ltMotor: UInt8,
    rtMotor: UInt8
  ) async throws {
    let seq = sequencer.next(for: GIPCommand.rumble)
    let activation: UInt8 = gipRumbleAllMotors
    // The options byte must be 0x00: controllers silently discard rumble frames
    // flagged with GIPOption.internal (verified on 045E:02D1 hardware), matching
    // the unflagged rumble commands sent by the Linux xone and xpad drivers.
    let packet: [UInt8] = [
      GIPCommand.rumble, 0x00, seq, gipRumbleSubCommandLength, 0x00, activation, ltMotor, rtMotor,
      left, right, gipRumbleDefaultDuration, 0x00, 0xFF  // on=255, off=0, repeat=255
    ]
    _ = try await handle.writeInterruptPacket(
      endpoint: outEndpoint,
      data: packet,
      timeout: gipRumbleTransferTimeoutMs
    )
  }

  public var physicalRumbleMotors: [PhysicalRumbleMotor] {
    [.leftMain, .rightMain, .leftTrigger, .rightTrigger]
  }

  public func sendPhysicalRumble(
    handle: any USBTransportSession,
    left: UInt8,
    right: UInt8,
    lt: UInt8,
    rt: UInt8
  ) async throws {
    try await sendRumble(handle: handle, left: left, right: right, ltMotor: lt, rtMotor: rt)
  }

  // MARK: - Private

  /// Send the profile-selected GIP init sequence with a short delay between packets.
  private func sendInitSequence(handle: any USBTransportSession) async throws {
    let initDelay = gipInitDelayNanoseconds

    for (index, startupPacket) in startupPackets.enumerated() {
      let seq = sequencer.next(for: startupPacket.command)
      _ = try await handle.writeInterruptPacket(
        endpoint: outEndpoint,
        data: startupPacket.packet(sequence: seq),
        timeout: 2000
      )
      if index < startupPackets.count - 1 { try await Task.sleep(nanoseconds: initDelay) }
    }
  }

  private func parseMainInput(payload: Data) -> [ControllerEvent] {
    guard payload.count >= 14 else {
      print("[GIPParser] Main input payload too short: " + "\(payload.count)")
      return []
    }
    let bytes = Array(payload)

    let buttons0 = bytes[0]
    let buttons1 = bytes[1]
    let share = shareByte(in: bytes)
    let lt = parseLT(from: bytes)
    let rt = parseRT(from: bytes)
    let (lsx, lsy, rsx, rsy) = parseSticks(from: bytes)

    var events: [ControllerEvent] = []
    events += parseFaceButtons(curr: buttons0)
    events += parseShoulderButtons(curr: buttons1)
    events += parseExtendedButtons(curr: share)
    events += parseDpad(curr: buttons1)
    events += parseSticksEvents(lsx: lsx, lsy: lsy, rsx: rsx, rsy: rsy)
    events += parseTriggers(lt: lt, rt: rt)

    prevButtons0 = buttons0
    prevButtons1 = buttons1
    prevButtons2 = share
    prevLT = lt
    prevRT = rt

    return events
  }

  private func parseLT(from bytes: [UInt8]) -> UInt16 { UInt16(bytes[2]) | (UInt16(bytes[3]) << 8) }

  private func parseRT(from bytes: [UInt8]) -> UInt16 { UInt16(bytes[4]) | (UInt16(bytes[5]) << 8) }

  private func parseSticks(from bytes: [UInt8]) -> (Int16, Int16, Int16, Int16) {
    let lsx = Int16(bitPattern: UInt16(bytes[6]) | (UInt16(bytes[7]) << 8))
    let lsy = Int16(bitPattern: UInt16(bytes[8]) | (UInt16(bytes[9]) << 8))
    let rsx = Int16(bitPattern: UInt16(bytes[10]) | (UInt16(bytes[11]) << 8))
    let rsy = Int16(bitPattern: UInt16(bytes[12]) | (UInt16(bytes[13]) << 8))
    return (lsx, lsy, rsx, rsy)
  }

  private func parseFaceButtons(curr: UInt8) -> [ControllerEvent] {
    diffButtons(
      prev: prevButtons0,
      curr: curr,
      mapping: [(4, .start), (8, .back), (16, .a), (32, .b), (64, .x), (128, .y)]
    )
  }

  private func parseShoulderButtons(curr: UInt8) -> [ControllerEvent] {
    diffButtons(
      prev: prevButtons1,
      curr: curr,
      mapping: [(16, .leftBumper), (32, .rightBumper), (64, .leftStick), (128, .rightStick)]
    )
  }

  private func parseExtendedButtons(curr: UInt8) -> [ControllerEvent] {
    diffButtons(prev: prevButtons2, curr: curr, mapping: [(1, .share)])
  }

  private func shareByte(in bytes: [UInt8]) -> UInt8 {
    if mappingOptions.contains(.shareOffset) {
      // Linux xpad: data[len - 26] with a 4-byte GIP header.
      let index = bytes.count - 22
      guard index >= 0, index < bytes.count else { return 0 }
      return bytes[index]
    }
    // 32-byte GIP payloads put Share at payload[15] (URB offset 19).
    guard bytes.count > 15 else { return 0 }
    return bytes[15]
  }

  private func parseDpad(curr: UInt8) -> [ControllerEvent] {
    let dpad = curr & gipDpadMask
    let prevDpad = prevButtons1 & gipDpadMask
    if dpad != prevDpad { return [.dpadChanged(mapDpad(dpad))] }
    return []
  }

  private func parseSticksEvents(lsx: Int16, lsy: Int16, rsx: Int16, rsy: Int16)
    -> [ControllerEvent]
  {
    var events: [ControllerEvent] = []
    if lsx != prevLSX || lsy != prevLSY {
      let lx = normalizeStick(lsx)
      let ly = -normalizeStick(lsy)
      events.append(.leftStickChanged(x: lx, y: ly))
      prevLSX = lsx
      prevLSY = lsy
    }
    if rsx != prevRSX || rsy != prevRSY {
      let rx = normalizeStick(rsx)
      let ry = -normalizeStick(rsy)
      events.append(.rightStickChanged(x: rx, y: ry))
      prevRSX = rsx
      prevRSY = rsy
    }
    return events
  }

  private func parseTriggers(lt: UInt16, rt: UInt16) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    if lt != prevLT { events.append(.leftTriggerChanged(Float(lt) / gipTriggerMax)) }
    if rt != prevRT { events.append(.rightTriggerChanged(Float(rt) / gipTriggerMax)) }
    prevLT = lt
    prevRT = rt
    return events
  }

  private func parseGuideButton(payload: Data) -> [ControllerEvent] {
    guard let first = payload.first else { return [] }
    if (first & gipGuideButtonMask) != 0 { return [.buttonPressed(.guide)] }
    return [.buttonReleased(.guide)]
  }

  private func normalizeStick(_ raw: Int16) -> Float { Float(raw) / gipStickMax }

  private func mapDpad(_ value: UInt8) -> DpadDirection {
    // bits: up=1, down=2, left=4, right=8
    switch value {
    case 1: .north
    case 2: .south
    case 4: .west
    case 8: .east
    case 9: .northEast  // up + right
    case 5: .northWest  // up + left
    case 10: .southEast  // down + right
    case 6: .southWest  // down + left
    default: .neutral
    }
  }
}
