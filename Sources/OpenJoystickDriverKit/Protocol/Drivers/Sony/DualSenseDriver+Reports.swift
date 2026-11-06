import Foundation

extension DualSenseDriver {
  /// The lightbar color a DualSense shows before the host sets one: blue.
  public var defaultColor: ControllerColor? { ControllerColor(red: 0, green: 0, blue: 255) }

  /// DualSense Edge function buttons and back paddles: the description's record capability.
  public static var edgeControls: Set<Control> {
    PhysicalProtocolID.sonyDualSense.protocolDescription.recordCapabilities.presentControls
  }

  /// Output waits for a connected controller on a third-party dongle, and feature replies are
  /// validated.
  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan(
      requiresInputConnectionBeforeOutput: thirdParty?.isDongle == true,
      validatesFeatureReplies: true
    )
  }

  /// Returns and clears the connection change that is pending.
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? {
    defer { pendingConnectionState = nil }
    return pendingConnectionState
  }

  /// The controls of the description, with the Edge buttons added when ``hasEdgeButtons`` is true.
  public var capabilities: ControllerCapabilities {
    let edge = PhysicalProtocolID.sonyDualSense.protocolDescription.recordCapabilities
      .presentControls
    return PhysicalProtocolID.sonyDualSense.describedControls.union(
      ControllerCapabilities(controls: hasEdgeButtons ? edge : [])
    )
  }

  /// The byte offsets of the fields in the input payload that follows the report header.
  private enum ReportOffset {
    /// The left stick X.
    static let leftStickX = 0
    /// The left stick Y.
    static let leftStickY = 1
    /// The right stick X.
    static let rightStickX = 2
    /// The right stick Y.
    static let rightStickY = 3
    /// The left trigger.
    static let l2Trigger = 4
    /// The right trigger.
    static let r2Trigger = 5
    /// The first button byte: the face buttons and the D-pad hat.
    static let buttons0 = 7
    /// The second button byte: the shoulders, triggers, stick clicks, Back and Start.
    static let buttons1 = 8
    /// The third button byte: the Guide, touchpad click and microphone buttons, and the Edge
    /// buttons.
    static let buttons2 = 9
  }

  /// Output limited to the controller's features; adaptive triggers only on Sony controllers.
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    var lighting: [PhysicalLightingFeature] = []
    if features.contains(.playerIndicator) { lighting.append(.playerIndicator) }
    if features.contains(.lightbar) { lighting.append(.programmableColor) }
    return PhysicalControllerOutputCapabilities(
      rumbleMotors: features.contains(.vibration) ? [.lowFrequency, .highFrequency] : [],
      lightingFeatures: lighting,
      adaptiveTriggers: thirdParty == nil ? PhysicalAdaptiveTrigger.allCases : []
    )
  }

  /// Calibration, preceded on a third-party controller by SDL's capability probe.
  public func startupFeatureReads() -> [PhysicalHIDFeatureReadRequest] {
    let calibration = PhysicalHIDFeatureReadRequest(reportID: 0x05, length: 41)
    guard thirdParty != nil else { return [calibration] }
    let probe = PhysicalHIDFeatureReadRequest(
      reportID: dualSenseCapabilitiesReportID,
      length: dualSenseCapabilitiesReportLength
    )
    return [probe, calibration]
  }

  /// Installs the factory motion calibration, or the third-party capability probe, from a feature
  /// reply.
  /// - Returns: Whether the reply was valid and installed. A calibration reply with the wrong
  ///   length or ID, or that fails the Bluetooth CRC, is rejected.
  public func consumeFeatureReply(_ data: Data, request: PhysicalHIDFeatureReadRequest) -> Bool {
    let bytes = Array(data)
    if request.reportID == dualSenseCapabilitiesReportID { return applyCapabilityReply(bytes) }
    guard request.reportID == 5, request.length == 41, data.count == 41 else { return false }
    if isBluetoothVariant || connectionMode == .bluetooth,
      !SonyBluetoothCRC32.isValid(seed: 0xA3, report: bytes)
    {
      return false
    }
    guard let calibrated = SonyMotionCalibration.dualSenseFactory(bytes) else { return false }
    motionCalibration = calibrated.installed(after: motionCalibration)
    return true
  }

  /// Decodes one DualSense HID input report into the full controller state and its samples.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = try reportPayload(from: data)
    guard bytes.count >= 10, acceptsDongleReport(bytes, receivedAt: receivedAt.nanoseconds) else {
      return nil
    }
    var next = state
    next.leftStick = StickPosition(
      x: normalizeHID(bytes[ReportOffset.leftStickX]),
      y: normalizeHID(bytes[ReportOffset.leftStickY])
    )
    next.rightStick = StickPosition(
      x: normalizeHID(bytes[ReportOffset.rightStickX]),
      y: normalizeHID(bytes[ReportOffset.rightStickY])
    )
    next.leftTrigger = trigger(
      bytes[ReportOffset.l2Trigger],
      button: bytes[ReportOffset.buttons1] & 0x04 != 0
    )
    next.rightTrigger = trigger(
      bytes[ReportOffset.r2Trigger],
      button: bytes[ReportOffset.buttons1] & 0x08 != 0
    )
    next.hat = mapHat(bytes[ReportOffset.buttons0] & 0x0F)
    for (offset, mask, control) in buttonTable {
      next.set(control, pressed: bytes[offset] & mask != 0)
    }
    var samples =
      usesAlternateReport
      ? SonySensorSamples.dualSenseAlternate(
        bytes,
        receivedAt: receivedAt.nanoseconds,
        clock: &sensorClock,
        calibration: motionCalibration
      )
      : SonySensorSamples.dualSense(
        bytes,
        receivedAt: receivedAt.nanoseconds,
        clock: &sensorClock,
        calibration: motionCalibration
      )
    if !features.contains(.sensors) { samples.motion = [] }
    if !features.contains(.touchpad) { samples.touch = [] }
    next.recordTouch(samples.touch)
    state = next
    return ControllerEvent(
      timestamp: receivedAt,
      state: next,
      motion: samples.motion,
      touchFrames: samples.touch
    )
  }

  /// A digital trigger with an idle analog byte reads fully pulled, as SDL reads it; arcade
  /// sticks report only the digital bit.
  private func trigger(_ raw: UInt8, button: Bool) -> UnipolarValue {
    UnipolarValue(normalized: raw == 0 && button ? 1 : Float(raw) / dualSenseTriggerMax)
  }

  /// Payload byte, mask and PlayStation-label control of each button; Edge buttons only on Edge.
  private var buttonTable: [(Int, UInt8, Control)] {
    let base: [(Int, UInt8, Control)] = [
      (ReportOffset.buttons0, 0x10, .west), (ReportOffset.buttons0, 0x20, .south),
      (ReportOffset.buttons0, 0x40, .east), (ReportOffset.buttons0, 0x80, .north),
      (ReportOffset.buttons1, 0x01, .leftShoulder), (ReportOffset.buttons1, 0x02, .rightShoulder),
      (ReportOffset.buttons1, 0x04, .leftTrigger),
      (ReportOffset.buttons1, 0x08, .rightTrigger), (ReportOffset.buttons1, 0x10, .back),
      (ReportOffset.buttons1, 0x20, .start), (ReportOffset.buttons1, 0x40, .leftStickClick),
      (ReportOffset.buttons1, 0x80, .rightStickClick), (ReportOffset.buttons2, 0x01, .guide),
      (ReportOffset.buttons2, 0x02, .touchpadClick), (ReportOffset.buttons2, 0x04, .microphone),
    ]
    guard hasEdgeButtons else { return base }
    return base + [
      (ReportOffset.buttons2, 0x10, .auxiliary1), (ReportOffset.buttons2, 0x20, .auxiliary2),
      (ReportOffset.buttons2, 0x40, .leftPaddle1), (ReportOffset.buttons2, 0x80, .rightPaddle1),
    ]
  }

  /// Encodes a rumble, player indicator, lightbar color or adaptive trigger command as one output
  /// report for the current connection.
  /// - Throws: ``ControllerOutputError/unsupportedCapability(_:)`` when the controller lacks the
  ///   feature or the command is a light brightness change.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    guard supports(command) else { throw .unsupportedCapability(command.capability) }
    switch command {
    case .setRumble(let intensities, _):
      return output(
        validFlag0: dualSenseCompatibleVibrationFlags,
        motorRight: intensities.highFrequency.byte,
        motorLeft: intensities.lowFrequency.byte
      )
    case .stopRumble: return output(validFlag0: dualSenseCompatibleVibrationFlags)
    case .setPlayerIndicator(let indicator):
      let patterns: [PhysicalPlayerIndicator: UInt8] = [
        .off: 0, .player1: 0x04, .player2: 0x0A, .player3: 0x15, .player4: 0x1B,
      ]
      return output(
        validFlag1: dualSensePlayerIndicatorFlag,
        playerIndicator: patterns[indicator] ?? 0
      )
    case .setRGB(let color):
      return output(
        validFlag1: dualSenseLightbarFlag,
        red: color.red,
        green: color.green,
        blue: color.blue
      )
    case .setAdaptiveTrigger(let trigger, let effect):
      let encoded = Self.encodedAdaptiveTriggerEffect(effect)
      switch trigger {
      case .left:
        return output(validFlag0: dualSenseLeftTriggerEffectFlag, leftTriggerEffect: encoded)
      case .right:
        return output(validFlag0: dualSenseRightTriggerEffectFlag, rightTriggerEffect: encoded)
      }
    case .setLightBrightness: throw .unsupportedCapability(command.capability)
    }
  }

  /// Whether the controller has the output feature that `command` needs.
  private func supports(_ command: ControllerOutputCommand) -> Bool {
    let output = outputCapabilities
    switch command {
    case .setRumble, .stopRumble: return output.supportsRumble
    case .setPlayerIndicator: return output.supportsPlayerIndicator
    case .setRGB: return output.lightingFeatures.contains(.programmableColor)
    case .setAdaptiveTrigger: return output.supportsAdaptiveTriggers
    case .setLightBrightness: return true
    }
  }

  /// The 11-byte trigger effect field of `effect`: a resistance effect, or all zeros for any other
  /// kind or an invalid effect.
  static func encodedAdaptiveTriggerEffect(_ effect: PhysicalAdaptiveTriggerEffect) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 11)
    guard (try? effect.validate()) != nil, effect.kind == .resistance else { return bytes }
    bytes[0] = 0x01
    bytes[1] = UInt8((effect.startPosition * 9).rounded())
    bytes[2] = UInt8((effect.strength * 8).rounded())
    return bytes
  }

  /// One output report carrying only the flagged fields.
  private func output(
    validFlag0: UInt8 = 0,
    validFlag1: UInt8 = 0,
    motorRight: UInt8 = 0,
    motorLeft: UInt8 = 0,
    rightTriggerEffect: [UInt8] = [UInt8](repeating: 0, count: 11),
    leftTriggerEffect: [UInt8] = [UInt8](repeating: 0, count: 11),
    playerIndicator: UInt8 = 0,
    red: UInt8 = 0,
    green: UInt8 = 0,
    blue: UInt8 = 0
  ) -> PhysicalOutputPlan {
    switch connectionMode {
    case .usb:
      var report = [UInt8](repeating: 0, count: dualSenseUSBOutputReportLength)
      report[0] = dualSenseUSBOutputReportID
      report[1] = validFlag0
      report[2] = validFlag1
      report[3] = motorRight
      report[4] = motorLeft
      report.replaceSubrange(11..<22, with: rightTriggerEffect)
      report.replaceSubrange(22..<33, with: leftTriggerEffect)
      report[44] = playerIndicator
      report[45] = red
      report[46] = green
      report[47] = blue
      let output = PhysicalHIDOutputReport(reportID: dualSenseUSBOutputReportID, bytes: report)
      return PhysicalOutputPlan(writes: [.hidOutput(output)])
    case .bluetooth:
      var report = [UInt8](repeating: 0, count: dualSenseBluetoothOutputReportLength)
      report[0] = dualSenseBluetoothOutputReportID
      report[1] = outputSequence << 4
      outputSequence = (outputSequence + 1) & 0x0F
      report[2] = dualSenseOutputTag
      report[3] = validFlag0
      report[4] = validFlag1
      report[5] = motorRight
      report[6] = motorLeft
      report.replaceSubrange(13..<24, with: rightTriggerEffect)
      report.replaceSubrange(24..<35, with: leftTriggerEffect)
      report[46] = playerIndicator
      report[47] = red
      report[48] = green
      report[49] = blue
      SonyBluetoothCRC32.writeTrailer(seed: dualSenseOutputCRC32Seed, report: &report)
      let output = PhysicalHIDOutputReport(
        reportID: dualSenseBluetoothOutputReportID,
        bytes: report
      )
      return PhysicalOutputPlan(writes: [.hidOutput(output)])
    }
  }

  /// The input payload of `data` without its report header and Bluetooth trailer; empty when the
  /// report is not a DualSense input report.
  ///
  /// Sets the connection mode to the report's transport.
  /// - Throws: ``DualSenseDriverError/invalidBluetoothCRC`` when a Bluetooth report fails its CRC.
  private func reportPayload(from data: Data) throws -> [UInt8] {
    let bytes = Array(data)
    // SDL reads a third-party report of any length but 10, its simple Bluetooth report.
    let usbLength = thirdParty == nil ? dualSenseUSBInputReportLength : 11
    if bytes.first == dualSenseUSBInputReportID, bytes.count >= usbLength {
      connectionMode = .usb
      return Array(bytes.dropFirst())
    }
    if bytes.first == dualSenseBluetoothInputReportID,
      bytes.count >= dualSenseBluetoothInputReportLength
    {
      try validateBluetoothCRC(report: bytes)
      connectionMode = .bluetooth
      return Array(bytes.dropFirst(2).dropLast(4))
    }
    if bytes.first == dualSenseBluetoothHIDInputTransaction,
      bytes.dropFirst().first == dualSenseBluetoothInputReportID,
      bytes.count >= dualSenseBluetoothInputReportLength + 1
    {
      let report = Array(bytes.dropFirst())
      try validateBluetoothCRC(report: report)
      connectionMode = .bluetooth
      return Array(report.dropFirst(2).dropLast(4))
    }
    return []
  }

  /// Checks the CRC trailer of a Bluetooth input report.
  /// - Throws: ``DualSenseDriverError/invalidBluetoothCRC`` when the trailer does not match.
  private func validateBluetoothCRC(report: [UInt8]) throws {
    guard SonyBluetoothCRC32.isValid(seed: dualSenseInputCRC32Seed, report: report) else {
      throw DualSenseDriverError.invalidBluetoothCRC
    }
  }

  /// The stick axis `raw` as -1...1, centered on 128.
  private func normalizeHID(_ raw: UInt8) -> Float {
    let centered = Float(raw) - dualSenseAxisCenter
    let divisor = centered >= 0 ? dualSenseAxisPositiveMax : dualSenseAxisNegativeMax
    let normalized = centered / divisor
    return max(-1, min(1, normalized))
  }

  /// The hat direction of the D-pad nibble.
  private func mapHat(_ hat: UInt8) -> HatDirection {
    switch hat {
    case 0: .north
    case 1: .northEast
    case 2: .east
    case 3: .southEast
    case 4: .south
    case 5: .southWest
    case 6: .west
    case 7: .northWest
    default: .neutral
    }
  }
}
