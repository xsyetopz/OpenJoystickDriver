public import Foundation

/// The D-pad bits of the second button byte.
private let gipDpadMask: UInt8 = 0x0F
/// The bits of a virtual key frame's first byte that show the Xbox button pressed.
private let gipGuideButtonMask: UInt8 = 0x03
/// The maximum positive value of a signed stick axis.
private let gipStickMax: Float = 32767
/// The maximum value of a trigger axis.
private let gipTriggerMax: Float = 1023
/// The most bytes that a length field of a frame header may take.
private let gipMaximumVarintBytes = 5
/// The motor mask of a rumble frame that enables all four motors.
private let gipRumbleAllMotors: UInt8 = 0x0F
/// The length of a rumble frame's sub-command.
private let gipRumbleSubCommandLength: UInt8 = 0x09
/// The on-time byte of a rumble frame.
private let gipRumbleDefaultDuration: UInt8 = 0xFF
/// Motor levels are percentages ([MS-GIPUSB] Table 56).
private let gipRumbleLevelMax: Double = 100

/// One GIP frame taken from the transfer buffer.
private struct GIPFrame {
  /// The command byte.
  let command: UInt8
  /// The option flags.
  let options: UInt8
  /// The sequence number.
  let sequence: UInt8
  /// The payload after the header.
  let payload: Data
  /// A fragment's extra header field: the message's total length in the first fragment, the
  /// fragment's offset in a later one ([MS-GIPUSB] 3.1.5.2).
  let totalLengthOrOffset: Int
}

/// Errors that ``GIPDriver`` can throw during the handshake or while parsing packets.
public enum GIPError: Error, Sendable {
  /// The controller did not complete the handshake within the allowed number of attempts.
  case handshakeTimeout
  /// The handshake failed for a specific reason (for example, no USB handle is provided).
  case handshakeFailed(String)
  /// A received packet is too short or its declared length does not match the actual data.
  case malformedPacket(String)
  /// Authentication sub-protocol error.
  case authFailed(String)
}

/// Driver for Xbox One (GIP) controllers connected over USB.
///
/// Sends the startup packets of the record or the description on connection, then parses buffered
/// GIP frames into controller state. Sends the description's keep-alive when ``keepAlivePolicy``
/// is enabled.
public final class GIPDriver: PhysicalProtocolDriver {

  /// The address of the interrupt OUT endpoint.
  private let outEndpoint: UInt8
  /// The startup packets of the record, or of the description when the record has none.
  private let startup: [USBStartupWrite]
  /// The timeout of one output packet that names none (`usbTransferTimeoutMilliseconds`).
  private let usbTimeoutMilliseconds: Int
  /// Whether the driver sends the keep-alive.
  public let keepAlivePolicy: GIPKeepAlivePolicy
  /// Where the Share button sits, counted back from the packet end; nil keeps the default byte.
  let shareButtonFromEnd: Int?
  /// Whether the row allows rumble output.
  let allowsPhysicalOutput: Bool

  /// The sequence numbers of the packets sent.
  private var sequencer = GIPSequencer()
  /// Answers the authentication sub-protocol.
  private let authHandler: GIPAuthHandler
  /// Bytes of incomplete frames received so far.
  private var pendingInput = Data()
  /// Writes produced while parsing, returned by ``drainPendingWrites()``.
  private var pendingWrites: [PhysicalOutputWrite] = []
  /// Announces received before the controller's first input, for the startup resend.
  private var announcesBeforeInput = 0
  /// Announces between startup resends (`presenceResendReports`).
  let announceResendInterval: Int
  /// Whether input has arrived since the session started.
  private var hasReceivedInput = false
  /// Total length of the fragmented message in transfer, from its first fragment.
  private var fragmentTotalLength = 0

  /// Current device state, driven by auth progress.
  public var deviceState: GIPDeviceState { authHandler.deviceState }

  /// The state after the latest frame that carried input.
  private var state = ControllerState.neutral

  /// Creates the driver for a GIP controller on `transportProfile`.
  /// - Parameters:
  ///   - transportProfile: The USB endpoints and interface the controller uses.
  ///   - startupPackets: Ids of the description's named packets that start the session; used when
  ///     `usbStartupWrites` is empty.
  ///   - usbStartupWrites: The record's startup packets; they replace `startupPackets`.
  ///   - keepAlivePolicy: Whether to send the keep-alive.
  ///   - shareButtonFromEnd: Where the Share button sits, counted back from the payload end; nil
  ///     when the model has none.
  ///   - allowsPhysicalOutput: Whether rumble output is allowed.
  ///   - tuning: The effective tuning of the record; the description's defaults when nil.
  public init(
    transportProfile: DeviceTransportProfile = .gipDefault,
    startupPackets: [String] = [],
    usbStartupWrites: [USBStartupWrite] = [],
    keepAlivePolicy: GIPKeepAlivePolicy = .enabled,
    shareButtonFromEnd: Int? = nil,
    allowsPhysicalOutput: Bool = true,
    tuning: ControllerTuning? = nil
  ) {
    self.outEndpoint = transportProfile.outputEndpoint
    let named = startupPackets.map { identifier in
      guard let write = PhysicalProtocolID.xboxGIP.namedPacketWrite(identifier) else {
        preconditionFailure("\(identifier) is not a named packet of XboxGIP")
      }
      return write
    }
    startup = PhysicalProtocolID.xboxGIP.usbStartupWrites(
      recordWrites: usbStartupWrites.isEmpty ? named : usbStartupWrites,
      variant: .usb,
      parameters: .none
    )
    usbTimeoutMilliseconds = PhysicalProtocolID.xboxGIP.described(
      \.usbTransferTimeoutMilliseconds,
      in: tuning
    )
    self.keepAlivePolicy = keepAlivePolicy
    self.shareButtonFromEnd = shareButtonFromEnd
    self.allowsPhysicalOutput = allowsPhysicalOutput
    self.authHandler = GIPAuthHandler()
    announceResendInterval = PhysicalProtocolID.xboxGIP.described(
      \.presenceResendReports,
      in: tuning
    )
  }

  // MARK: - PhysicalProtocolDriver

  /// The session plan: the description's defaults, the handshake retries, and the USB keep-alive
  /// when the policy enables it.
  public var sessionPlan: DriverSessionPlan {
    // The description sets the attempt count, the delays and the keep-alive interval.
    DriverSessionPlan(
      usbStartupRetryDelays: Array(
        repeating: 0,
        count: PhysicalProtocolID.xboxGIP.described(limit: \.handshakeAttempts) - 1
      ),
      keepAliveChannels: keepAlivePolicy == .enabled ? [.usb] : [],
      armsInputBeforeStartup: true
    ).withDefaults(of: .xboxGIP)
  }

  /// Sends the GIP init sequence of the record or the description, each packet stamped with the
  /// next sequence number for its command.
  public func startupWrites() -> [PhysicalOutputWrite] {
    let session: ([UInt8]) -> UInt8 = { [self] bytes in
      sequencer.next(for: bytes[0], options: bytes[1])
    }
    return startup.map { write in
      write.write(
        defaultEndpoint: outEndpoint,
        defaultTimeoutMilliseconds: usbTimeoutMilliseconds,
        session: session
      )
    }
  }

  /// The description's keep-alive writes, each stamped with the next sequence number of its
  /// command; none unless ``keepAlivePolicy`` is enabled.
  public func keepAliveWrites() -> [PhysicalOutputWrite] {
    guard keepAlivePolicy == .enabled else { return [] }
    return PhysicalProtocolID.xboxGIP.keepAliveWrites(variant: .usb).map { write in
      write.output(
        defaultEndpoint: outEndpoint,
        defaultTimeoutMilliseconds: usbTimeoutMilliseconds
      ) { [self] bytes in sequencer.next(for: bytes[0], options: bytes[1]) }
    }
  }

  /// The USB write of `bytes` to the OUT endpoint.
  private func usbWrite(_ bytes: [UInt8]) -> PhysicalOutputWrite {
    .usb(
      PhysicalUSBOutputPacket(
        endpoint: outEndpoint,
        bytes: bytes,
        timeoutMilliseconds: UInt32(usbTimeoutMilliseconds)
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

  /// Takes the next complete frame out of the buffer; nil while the buffer holds less than one.
  /// - Throws: ``GIPError/malformedPacket(_:)`` when a header length field exceeds the largest
  ///   size.
  private func nextFrame() throws -> GIPFrame? {
    guard pendingInput.count >= 4 else { return nil }
    let bytes = Array(pendingInput)

    let command = bytes[0]
    let options = bytes[1]
    let sequence = bytes[2]
    guard let (payloadLength, afterLength) = try decodeVarint(bytes, start: 3) else { return nil }
    var headerLength = afterLength
    var totalLengthOrOffset = 0
    if options & GIPOption.chunk != 0 {
      guard let (value, afterValue) = try decodeVarint(bytes, start: headerLength) else {
        return nil
      }
      totalLengthOrOffset = value
      headerLength = afterValue
    }
    guard pendingInput.count >= headerLength + payloadLength else { return nil }

    let payload = Data(bytes[headerLength..<(headerLength + payloadLength)])
    pendingInput.removeFirst(headerLength + payloadLength)
    return GIPFrame(
      command: command,
      options: options,
      sequence: sequence,
      payload: payload,
      totalLengthOrOffset: totalLengthOrOffset
    )
  }

  /// Reads a GIP length field at `start`: its value and the offset after it.
  ///
  /// Nil while the buffer ends inside the field.
  /// - Throws: ``GIPError/malformedPacket(_:)`` when the field runs past the largest size.
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
    let isFragment = frame.options & GIPOption.chunk != 0
    let isFirstFragment = isFragment && frame.options & GIPOption.chunkStart != 0
    if isFirstFragment { fragmentTotalLength = frame.totalLengthOrOffset }
    if frame.options & GIPOption.acknowledge != 0 {
      let offset = isFragment && !isFirstFragment ? frame.totalLengthOrOffset : 0
      let received = offset + frame.payload.count
      sendAcknowledgement(
        for: frame,
        received: received,
        remaining: isFragment ? fragmentTotalLength - received : 0
      )
    }
    guard frame.options & GIPOption.chunk == 0 else { return false }

    switch frame.command {
    case GIPCommand.input:
      hasReceivedInput = true
      return decodeMainInput(payload: frame.payload, into: &next)
    case GIPCommand.virtualKey:
      hasReceivedInput = true
      // [MS-GIPUSB] Table 2 names the key `VK_LWIN` (0x5B), but Linux xpad, which serves
      // third-party pads such as PowerA's, reads only the first byte, so a pad that sends another
      // key or none still presses Xbox (#53).
      guard let down = frame.payload.first else { return false }
      next.set(.guide, pressed: down & gipGuideButtonMask != 0)
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

  /// Acknowledges the bytes of the frame's message received so far and the bytes still to come (SDL
  /// `GIP_Acknowledge`).
  ///
  /// A fragment that runs past its message's total length, or counts that do not fit the 16-bit
  /// fields, get no acknowledgement, as in SDL, which fails the transfer.
  private func sendAcknowledgement(for frame: GIPFrame, received: Int, remaining: Int) {
    guard let ackReceived = UInt16(exactly: received), let ackRemaining = UInt16(exactly: remaining)
    else { return }
    let packet = Self.acknowledgementPacket(
      command: frame.command,
      options: frame.options,
      sequence: frame.sequence,
      received: ackReceived,
      remaining: ackRemaining
    )
    pendingWrites.append(usbWrite(packet))
  }

  /// A controller still booting when the startup sequence arrives ignores it and keeps announcing
  /// (about every 500 ms).
  ///
  /// Until its first input, the sequence is resent on the first announce and every fourth one after
  /// it, a bounded number of times; SDL's GIP driver likewise initializes after the announce.
  private func resendStartupAfterAnnounce() {
    guard !hasReceivedInput else { return }
    defer { announcesBeforeInput += 1 }
    guard announcesBeforeInput.isMultiple(of: announceResendInterval),
      announcesBeforeInput / announceResendInterval
        < PhysicalProtocolID.xboxGIP.described(limit: \.announceResendLimit)
    else { return }
    pendingWrites += startupWrites()
  }

  /// Clears the state of the session: sequences restart at 1, as on first attach, and no partial
  /// frame, pending write or announce count carries over.
  public func resetProtocolState() {
    sequencer = GIPSequencer()
    pendingInput.removeAll()
    pendingWrites.removeAll()
    hasReceivedInput = false
    announcesBeforeInput = 0
    fragmentTotalLength = 0
    state = .neutral
  }

  /// Returns the queued writes and clears the queue.
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
      mainMotors: (motorLevel(intensities.lowFrequency), motorLevel(intensities.highFrequency)),
      triggerMotors: (motorLevel(intensities.leftTrigger), motorLevel(intensities.rightTrigger))
    )
    let write = PhysicalUSBOutputPacket(
      endpoint: outEndpoint,
      bytes: packet,
      timeoutMilliseconds: UInt32(usbTimeoutMilliseconds)
    )
    return PhysicalOutputPlan(writes: [.usb(write)])
  }

  // MARK: - Private

  /// The motor level of `intensity` as a percentage.
  private func motorLevel(_ intensity: UnipolarValue) -> UInt8 {
    UInt8((Double(intensity.rawValue) * gipRumbleLevelMax / Double(UInt16.max)).rounded())
  }

  /// The rumble frame that sets the main and trigger motor levels.
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

  /// Folds a main input payload into `next`; false when the payload is too short.
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
    if let share = shareByte(in: bytes) { next.set(.capture, pressed: share & 1 != 0) }
    next.hat = mapDpad(bytes[1] & gipDpadMask)
    next.leftStick = StickPosition(x: normalizeStick(lsx), y: -normalizeStick(lsy))
    next.rightStick = StickPosition(x: normalizeStick(rsx), y: -normalizeStick(rsy))
    next.leftTrigger = UnipolarValue(normalized: Float(parseLT(from: bytes)) / gipTriggerMax)
    next.rightTrigger = UnipolarValue(normalized: Float(parseRT(from: bytes)) / gipTriggerMax)
    return true
  }

  /// Button byte index (0 or 1), bit and the standard-label control it reports.
  private static let buttonTable: [(Int, UInt8, Control)] = [
    (0, 4, .start), (0, 8, .back), (0, 16, .south), (0, 32, .east), (0, 64, .west),
    (0, 128, .north), (1, 16, .leftShoulder), (1, 32, .rightShoulder), (1, 64, .leftStickClick),
    (1, 128, .rightStickClick),
  ]

  /// The byte holding Share, `shareButtonFromEnd` bytes back from the end; nil for a pad whose
  /// record names no Share.
  ///
  /// Linux xpad reads `data[len - 18]` of the packet, or `data[len - 26]` with `MAP_SHARE_OFFSET`;
  /// the 4-byte GIP header leaves the same offset from the payload end.
  private func shareByte(in bytes: [UInt8]) -> UInt8? {
    guard let shareButtonFromEnd else { return nil }
    let index = bytes.count - shareButtonFromEnd
    guard index >= 0, index < bytes.count else { return 0 }
    return bytes[index]
  }

  /// The stick axis `raw` as -1...1.
  private func normalizeStick(_ raw: Int16) -> Float { Float(raw) / gipStickMax }

}
