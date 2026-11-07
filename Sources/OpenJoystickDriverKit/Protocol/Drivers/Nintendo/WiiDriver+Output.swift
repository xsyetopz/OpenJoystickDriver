import Foundation

extension WiiDriver {
  /// Builds the output report `bytes` (report id first) with the rumble bit set while the motor
  /// runs, in bit `rumbleBit` of the first data byte (`RumbleBitCarry`).
  ///
  /// Every output report the driver sends goes through here, so none silences or starts the motor.
  func outputReport(_ bytes: [UInt8]) -> PhysicalOutputWrite {
    var bytes = bytes
    if isRumbling { bytes[1] |= 1 << UInt8(wii.rumbleBit) }
    return .hidOutput(PhysicalHIDOutputReport(reportID: bytes[0], bytes: bytes))
  }

  /// Runs the motor for any intensity above zero (the motor is binary) and lights the LED of a
  /// player (`PlayerIndicator`); any other command is unsupported.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    switch command {
    case .setRumble(let intensities, _):
      isRumbling = intensities.lowFrequency != .min
      return PhysicalOutputPlan(writes: [outputReport([Self.rumbleOutputID, 0])])
    case .stopRumble:
      isRumbling = false
      return PhysicalOutputPlan(writes: [outputReport([Self.rumbleOutputID, 0])])
    case .setPlayerIndicator(let player):
      let leds = player == .off ? 0 : 1 << (wii.ledFirstBit + player.rawValue - 1)
      return PhysicalOutputPlan(writes: [outputReport([wii.ledReport, UInt8(leds)])])
    case .speaker(let output): return try speakerPlan(output)
    default: throw .unsupportedCapability(command.capability)
    }
  }
}
