import Foundation

extension WiiDriver {
  /// What the extension handshake found on the remote.
  enum ExtensionKind: Equatable {
    /// An id of the description's table, by the kind's name.
    case known(String)
    /// An id the table lacks (`UnknownExtension`), kept as the six bytes read.
    case unknown([UInt8])
  }

  /// What a memory exchange is for.
  enum ExchangePurpose: Equatable {
    /// The EEPROM read of the accelerometer calibration.
    case accelerometerCalibration
    /// The extension handshake (`ExtensionHandshake`).
    case extensionHandshake
    /// The Motion Plus activation (`MotionPlusActivate`).
    case motionPlusActivation
    /// The ID read that names the Motion Plus kind after the activation.
    case motionPlusIdentify
    /// The IR camera setup (`IRSetupSpacing`).
    case irSetup
  }

  /// An exchange that ended without its data (`ExtensionHandshakeFailed` for the handshake).
  struct ExchangeFailure: Equatable {
    /// Why the exchange ended.
    enum Reason: Equatable {
      /// No reply within `replyTimeoutMs`.
      case timeout
      /// The error code of an acknowledgement, or the error nibble of a read reply.
      case error(UInt8)
    }

    /// The exchange.
    let purpose: ExchangePurpose
    /// The index of the script step that failed.
    let step: Int
    /// The reason.
    let reason: Reason
  }

  /// A memory reply the driver did not take.
  enum ReplyRefusal: Equatable {
    /// The reply carries another address than the outstanding read expects.
    case addressMismatch(expected: UInt16, received: UInt16)
  }

  /// A script of memory writes and reads that runs one step at a time: the next step goes out
  /// after the reply to the previous one.
  struct Exchange {
    /// What the exchange is for.
    let purpose: ExchangePurpose
    /// The description's steps.
    let steps: [ProtocolDescription.WiiRemote.Step]
    /// The index of the step on the wire.
    var step = 0
    /// The bytes the outstanding read has received so far.
    var received: [UInt8] = []
    /// The time at which the outstanding step counts as unanswered.
    var deadline: MonotonicTimestamp
    /// When the step was written.
    var sentAt = MonotonicTimestamp(nanoseconds: 0)
    /// The earliest time the step may be written; nil once it is on the wire.
    var notBefore: MonotonicTimestamp?
  }

  /// The zero point and the force of gravity of each accelerometer axis, 10 bits each.
  struct AccelerometerCalibration: Equatable {
    /// The reading at rest in free fall.
    let zero: RawAcceleration
    /// The reading under one g.
    let gravity: RawAcceleration

    /// Reads the calibration block of the EEPROM.
    ///
    /// The block holds the zero point and then gravity. Each has the high eight bits of the three
    /// axes, then a byte whose bits 5-4, 3-2 and 1-0 are the low two bits of X, Y and Z. Nil for a
    /// short block and for an uncalibrated one, whose gravity equals its zero point on some axis.
    init?(_ block: [UInt8]) {
      guard block.count >= 8 else { return nil }
      func reading(_ offset: Int) -> RawAcceleration {
        func axis(_ index: Int, _ shift: Int) -> Int {
          Int(block[offset + index]) << 2 | Int(block[offset + 3] >> shift & 0b11)
        }
        return RawAcceleration(x: axis(0, 4), y: axis(1, 2), z: axis(2, 0))
      }
      zero = reading(0)
      gravity = reading(4)
      guard zero.x != gravity.x, zero.y != gravity.y, zero.z != gravity.z else { return nil }
    }
  }

  /// Queues `purpose` behind the exchanges before it, and sends its first step when none is on
  /// the wire.
  func begin(_ purpose: ExchangePurpose, at now: MonotonicTimestamp) {
    queue(purpose, at: now)
    if exchanges.count == 1 { sendStep(at: now) }
  }

  /// Appends `purpose` to the exchanges without writing; the caller sends the first step.
  private func queue(_ purpose: ExchangePurpose, at now: MonotonicTimestamp) {
    let scripts = wii.scripts
    let steps: [ProtocolDescription.WiiRemote.Step]
    switch purpose {
    case .accelerometerCalibration: steps = scripts.accelerometerCalibration
    case .extensionHandshake: steps = scripts.handshake
    case .motionPlusActivation: steps = scripts.motionPlus
    // The handshake's last step reads the six ID bytes; its writes would switch Motion Plus off.
    case .motionPlusIdentify: steps = Array(scripts.handshake.suffix(1))
    case .irSetup: steps = scripts.ir
    }
    exchanges.append(Exchange(purpose: purpose, steps: steps, deadline: now))
  }

  /// Ends the exchanges that a timeout is due for: the failure is recorded and nothing is
  /// resent.
  func expireExchange(at now: MonotonicTimestamp) {
    if let exchange = exchanges.first, now >= exchange.deadline { fail(.timeout, at: now) }
  }

  /// Takes an acknowledgement or a memory reply for the outstanding step; any other one is not
  /// for it.
  func handleReply(_ bytes: [UInt8], at now: MonotonicTimestamp) {
    guard let exchange = exchanges.first, exchange.notBefore == nil else { return }
    let step = exchange.steps[exchange.step]
    switch (bytes[0], step) {
    case (Self.acknowledgementReportID, .write), (Self.acknowledgementReportID, .motionPlusMode),
      (Self.acknowledgementReportID, .sensitivity), (Self.acknowledgementReportID, .irMode),
      (Self.acknowledgementReportID, .report):
      guard bytes.count >= 5, bytes[3] == step.outputID else { return }
      if bytes[4] == 0 { advance(at: now) } else { fail(.error(bytes[4]), at: now) }
    case (Self.memoryReplyReportID, .read(let address, let length)):
      guard bytes.count >= 6 else { return }
      let expected = UInt16(truncatingIfNeeded: address) &+ UInt16(exchange.received.count)
      let received = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
      guard received == expected else {
        refusedReply = .addressMismatch(expected: expected, received: received)
        return
      }
      let error = bytes[3] & 0x0F
      guard error == 0 else {
        fail(.error(error), at: now)
        return
      }
      let size = Int(bytes[3] >> 4) + 1
      exchanges[0].received += bytes.dropFirst(6).prefix(size).prefix(
        length - exchange.received.count
      )
      if exchanges[0].received.count == length { advance(at: now) }
    default: return
    }
  }

  /// Returns the controls an extension drove to neutral and ends its handshake.
  func dropExtension(at now: MonotonicTimestamp) {
    extensionKind = nil
    extensionCenters = [:]
    state = ControllerState(pressed: state.pressed.intersection(wii.coreButtons.map(\.control)))
    if exchanges.first?.purpose == .extensionHandshake {
      exchanges.removeFirst()
      if !exchanges.isEmpty { sendStep(at: now) }
    }
    exchanges.removeAll { $0.purpose == .extensionHandshake }
    gyro = nil
  }

  /// Writes the waiting step of the first exchange once its time has come.
  func sendDueStep(at now: MonotonicTimestamp) {
    if let due = exchanges.first?.notBefore, now >= due { sendStep(at: now) }
  }

  /// Writes the step of the first exchange, with the clock of its reply timeout started.
  private func sendStep(at now: MonotonicTimestamp) {
    exchanges[0].deadline = MonotonicTimestamp(
      nanoseconds: now.nanoseconds + replyTimeoutNanoseconds
    )
    exchanges[0].sentAt = now
    exchanges[0].notBefore = nil
    let exchange = exchanges[0]
    switch exchange.steps[exchange.step] {
    case .write(let address, let bytes):
      pendingWrites.append(registerWrite(address, bytes))
    case .read(let address, let length):
      pendingWrites.append(memoryOutput(Self.memoryReadOutputID, address, [0, UInt8(length)]))
    case .motionPlusMode(let address):
      let key = Self.passthroughModeKeys[passthroughBase ?? ""] ?? "standalone"
      pendingWrites.append(registerWrite(address, [wii.motionPlusModeBytes[key] ?? 0]))
    case .report(let id, let data):
      pendingWrites.append(outputReport([id] + data))
    case .sensitivity(let block, let address):
      let level = wii.irSensitivityLevels[wii.defaultIRSensitivityLevel - 1]
      pendingWrites.append(registerWrite(address, block == 1 ? level.block1 : level.block2))
    case .irMode(let address):
      pendingWrites.append(registerWrite(address, [wii.irModeBytes[irFormat ?? .irBasic] ?? 0]))
    }
  }

  /// A memory write of `bytes`; the report always carries sixteen data bytes, zero-padded.
  func registerWrite(_ address: UInt32, _ bytes: [UInt8]) -> PhysicalOutputWrite {
    memoryOutput(
      Self.memoryWriteOutputID,
      address,
      [UInt8(bytes.count)] + bytes + [UInt8](repeating: 0, count: 16 - bytes.count)
    )
  }

  /// An output report of memory report `id`: the space flag, the 24-bit address, then `tail`.
  private func memoryOutput(_ id: UInt8, _ address: UInt32, _ tail: [UInt8]) -> PhysicalOutputWrite
  {
    let space = address > 0xFFFF ? Self.registerSpaceFlag : 0
    let head = [id, space] + (0..<3).map { UInt8(address >> (16 - 8 * UInt32($0)) & 0xFF) }
    return outputReport(head + tail)
  }

  /// Moves to the next step of the first exchange, or finishes it.
  private func advance(at now: MonotonicTimestamp) {
    exchanges[0].step += 1
    if exchanges[0].step < exchanges[0].steps.count {
      if exchanges[0].purpose == .irSetup {
        let due = MonotonicTimestamp(
          nanoseconds: exchanges[0].sentAt.nanoseconds + irWriteIntervalNanoseconds
        )
        exchanges[0].notBefore = due
        exchanges[0].deadline = MonotonicTimestamp(
          nanoseconds: due.nanoseconds + replyTimeoutNanoseconds
        )
        sendDueStep(at: now)
      } else {
        sendStep(at: now)
      }
      return
    }
    let finished = exchanges.removeFirst()
    let mode = chosenFeatures
    switch finished.purpose {
    case .accelerometerCalibration:
      accelerometerCalibration = AccelerometerCalibration(finished.received)
    case .extensionHandshake, .motionPlusIdentify:
      extensionCenters = [:]
      extensionKind =
        wii.extensions.first { $0.id == finished.received }.map { .known($0.kind) }
        ?? .unknown(finished.received)
      if activatesMotionPlus(after: finished.purpose) { queue(.motionPlusActivation, at: now) }
    case .motionPlusActivation:
      motionPlusActive = true
      queue(.motionPlusIdentify, at: now)
    case .irSetup:
      isIRReady = true
    }
    if chosenFeatures != mode { pendingWrites.append(reportModeWrite()) }
    if !exchanges.isEmpty { sendStep(at: now) }
  }

  /// Records a failure of the first exchange and goes on with the next one; nothing is resent.
  private func fail(_ reason: ExchangeFailure.Reason, at now: MonotonicTimestamp) {
    let exchange = exchanges.removeFirst()
    if exchange.purpose == .motionPlusIdentify { motionPlusActive = false }
    failure = ExchangeFailure(purpose: exchange.purpose, step: exchange.step, reason: reason)
    if !exchanges.isEmpty { sendStep(at: now) }
  }
}

extension ProtocolDescription.WiiRemote.Step {
  /// The output report whose acknowledgement answers the step.
  fileprivate var outputID: UInt8 {
    if case .report(let id, _) = self { return id }
    return WiiDriver.memoryWriteOutputID
  }
}
