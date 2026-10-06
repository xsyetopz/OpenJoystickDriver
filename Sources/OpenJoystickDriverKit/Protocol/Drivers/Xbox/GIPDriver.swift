import Foundation

private let gipDpadMask: UInt8 = 0x0F
private let gipGuideButtonMask: UInt8 = 0x03
private let gipHandshakeMaxAttempts = 3
private let gipAnnounceResendInterval = 4
private let gipAnnounceResendLimit = 8
private let gipHandshakeRetryDelays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000]
private let gipInitDelayNanoseconds: UInt64 = 50_000_000
private let gipKeepAliveInterval: UInt64 = 4_000_000_000
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

/// Errors that ``GIPDriver`` can throw during the handshake or while parsing packets.
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

/// Driver for Xbox One (GIP) controllers connected over USB.
///
/// Sends the three-packet GIP init sequence on connection, then parses
/// incoming interrupt-transfer packets into controller state snapshots.
/// Sends a keep-alive ping every ~4 seconds when the device profile permits it.
public final class GIPDriver: PhysicalProtocolDriver {

  private let outEndpoint: UInt8
  private let startupPackets: [GIPStartupPacket]
  public let keepAlivePolicy: GIPKeepAlivePolicy
  let usesShareOffset: Bool
  let allowsPhysicalOutput: Bool

  private var sequencer = GIPSequencer()
  private let authHandler: GIPAuthHandler
  private var pendingInput = Data()
  private var pendingWrites: [PhysicalOutputWrite] = []
  /// Announces received before the controller's first input, for the startup resend.
  private var announcesBeforeInput = 0
  private var hasReceivedInput = false

  /// Current device state, driven by auth progress.
  public var deviceState: GIPDeviceState { authHandler.deviceState }

  private var state = ControllerState.neutral

  /// Creates a new GIPDriver with the given endpoint configuration.
  public init(
    transportProfile: DeviceTransportProfile = .gipDefault,
    startupPackets: [GIPStartupPacket] = GIPStartupPacket.defaultSequence,
    keepAlivePolicy: GIPKeepAlivePolicy = .enabled,
    usesShareOffset: Bool = false,
    allowsPhysicalOutput: Bool = true
  ) {
    self.outEndpoint = transportProfile.outputEndpoint
    self.startupPackets = startupPackets
    self.keepAlivePolicy = keepAlivePolicy
    self.usesShareOffset = usesShareOffset
    self.allowsPhysicalOutput = allowsPhysicalOutput
    self.authHandler = GIPAuthHandler()
  }

  // MARK: - PhysicalProtocolDriver

  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan(
      usbStartupIntervalNanoseconds: gipInitDelayNanoseconds,
      usbStartupRetryDelays: Array(gipHandshakeRetryDelays.prefix(gipHandshakeMaxAttempts - 1)),
      usbKeepAliveIntervalNanoseconds: keepAlivePolicy == .enabled ? gipKeepAliveInterval : nil
    )
  }

  /// Sends the GIP init sequence to the controller.
  public func startupWrites() -> [PhysicalOutputWrite] {
    startupPackets.map { packet in
      var bytes = packet.packet(sequence: 0)
      bytes[2] = sequencer.next(for: bytes[0], options: bytes[1])
      return usbWrite(bytes)
    }
  }

  /// Builds the periodic host-side GIP status packet (CMD=0x03).
  public func keepAliveWrites() -> [PhysicalOutputWrite] {
    guard keepAlivePolicy == .enabled else { return [] }
    let seq = sequencer.next(for: GIPCommand.status, options: GIPOption.internal)
    return [
      usbWrite([
        GIPCommand.status, GIPOption.internal, seq, gipStatusSubCommandLength, 0x00, 0x00, 0x00,
      ])
    ]
  }

  private func usbWrite(_ bytes: [UInt8]) -> PhysicalOutputWrite {
    .usb(
      PhysicalUSBOutputPacket(
        endpoint: outEndpoint,
        bytes: bytes,
        timeoutMilliseconds: gipRumbleTransferTimeoutMs
      )
    )
  }

  /// Parses complete GIP frames buffered across one or more interrupt transfers; the state is
  /// committed once, after every complete frame of the transfer decoded.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    pendingInput.append(data)
    var next = state
    var carriesInput = false
    do {
      while let frame = try nextFrame() {
        carriesInput = process(frame, into: &next) || carriesInput
      }
    } catch {
      // A malformed header never completes; keeping it would fail every later transfer.
      pendingInput.removeAll()
      throw error
    }
    guard carriesInput else { return nil }
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
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

  /// Folds one frame into `next`; true when the frame carried input.
  private func process(_ frame: GIPFrame, into next: inout ControllerState) -> Bool {
    let totalLength = frame.chunkOffset + frame.payload.count
    if frame.options & GIPOption.acknowledge != 0 {
      sendAcknowledgement(for: frame, totalLength: totalLength)
    }
    guard frame.options & GIPOption.chunk == 0 else { return false }

    switch frame.command {
    case GIPCommand.input:
      hasReceivedInput = true
      return decodeMainInput(payload: frame.payload, into: &next)
    case GIPCommand.virtualKey:
      hasReceivedInput = true
      guard let first = frame.payload.first else { return false }
      next.set(.guide, pressed: first & gipGuideButtonMask != 0)
      return true
    case GIPCommand.announce:
      resendStartupAfterAnnounce()
      return false
    case GIPCommand.authenticate:
      if let packet = authHandler.handleAuthMessage(payload: frame.payload, sequencer: &sequencer) {
        pendingWrites.append(usbWrite(packet))
      }
      return false
    default: return false
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
    pendingWrites.append(usbWrite(packet))
  }

  /// A controller still booting when the startup sequence arrives ignores it and keeps announcing
  /// (about every 500 ms). Until its first input, the sequence is resent on the first announce and
  /// every fourth one after it, a bounded number of times; SDL's GIP driver likewise initializes
  /// after the announce.
  private func resendStartupAfterAnnounce() {
    guard !hasReceivedInput else { return }
    defer { announcesBeforeInput += 1 }
    guard announcesBeforeInput.isMultiple(of: gipAnnounceResendInterval),
      announcesBeforeInput / gipAnnounceResendInterval < gipAnnounceResendLimit
    else { return }
    pendingWrites += startupWrites()
  }

  /// A new transport session is a new GIP session: sequences restart at 1, as on first
  /// attach, and no partial frame, pending write or announce count carries over.
  public func resetProtocolState() {
    sequencer = GIPSequencer()
    pendingInput.removeAll()
    pendingWrites.removeAll()
    hasReceivedInput = false
    announcesBeforeInput = 0
    state = .neutral
  }

  public func drainPendingWrites() -> [PhysicalOutputWrite] {
    defer { pendingWrites.removeAll(keepingCapacity: true) }
    return pendingWrites
  }

  /// Rumble only, on rows that allow physical output.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    let intensities: RumbleIntensities
    switch command {
    case .setRumble(let requested, _) where allowsPhysicalOutput: intensities = requested
    case .stopRumble where allowsPhysicalOutput: intensities = .off
    default: throw .unsupportedCapability(command.capability)
    }
    let packet = rumbleFrame(
      sequence: sequencer.next(for: GIPCommand.rumble, options: 0),
      mainMotors: (intensities.leftMain.byte, intensities.rightMain.byte),
      triggerMotors: (intensities.leftTrigger.byte, intensities.rightTrigger.byte)
    )
    let write = PhysicalUSBOutputPacket(
      endpoint: outEndpoint,
      bytes: packet,
      timeoutMilliseconds: gipRumbleTransferTimeoutMs
    )
    return PhysicalOutputPlan(writes: [.usb(write)])
  }

  // MARK: - Private

  private func rumbleFrame(
    sequence: UInt8,
    mainMotors: (left: UInt8, right: UInt8),
    triggerMotors: (left: UInt8, right: UInt8)
  ) -> [UInt8] {
    // The options byte must be 0x00: controllers silently discard rumble frames
    // flagged with GIPOption.internal (verified on 045E:02D1 hardware), matching
    // the unflagged rumble commands sent by the Linux xone and xpad drivers.
    [
      GIPCommand.rumble, 0x00, sequence, gipRumbleSubCommandLength, 0x00, gipRumbleAllMotors,
      // on=255, off=0, repeat=255
      triggerMotors.left, triggerMotors.right, mainMotors.left, mainMotors.right,
      gipRumbleDefaultDuration, 0x00, 0xFF,
    ]
  }

  private func decodeMainInput(payload: Data, into next: inout ControllerState) -> Bool {
    guard payload.count >= 14 else {
      print("[GIPDriver] Main input payload too short: " + "\(payload.count)")
      return false
    }
    let bytes = Array(payload)
    let (lsx, lsy, rsx, rsy) = parseSticks(from: bytes)
    for (index, bit, control) in Self.buttonTable {
      next.set(control, pressed: bytes[index] & bit != 0)
    }
    next.set(.share, pressed: shareByte(in: bytes) & 1 != 0)
    next.hat = mapDpad(bytes[1] & gipDpadMask)
    next.leftStick = StickPosition(x: normalizeStick(lsx), yDown: -normalizeStick(lsy))
    next.rightStick = StickPosition(x: normalizeStick(rsx), yDown: -normalizeStick(rsy))
    next.leftTrigger = UnipolarValue(normalized: Float(parseLT(from: bytes)) / gipTriggerMax)
    next.rightTrigger = UnipolarValue(normalized: Float(parseRT(from: bytes)) / gipTriggerMax)
    return true
  }

  /// Button byte index (0 or 1), bit and the standard-label control it reports.
  private static let buttonTable: [(Int, UInt8, ControlID)] = [
    (0, 4, .menu), (0, 8, .view), (0, 16, .faceSouth), (0, 32, .faceEast), (0, 64, .faceWest),
    (0, 128, .faceNorth), (1, 16, .leftShoulder), (1, 32, .rightShoulder), (1, 64, .leftStickClick),
    (1, 128, .rightStickClick),
  ]

  private func shareByte(in bytes: [UInt8]) -> UInt8 {
    if usesShareOffset {
      // Linux xpad: data[len - 26] of the packet, which is the payload after a 4-byte GIP
      // header; SDL reads byte 18 of the 44-byte Series X firmware 5.5 payload.
      let index = bytes.count - 26
      guard index >= 0, index < bytes.count else { return 0 }
      return bytes[index]
    }
    // GameSir G7 SE and typical 32-byte GIP payloads put Share at payload[14]
    // (URB offset 18 on a 4-byte header). Series X uses the share-offset quirk instead.
    guard bytes.count > 14 else { return 0 }
    return bytes[14]
  }

  private func normalizeStick(_ raw: Int16) -> Float { Float(raw) / gipStickMax }

}
