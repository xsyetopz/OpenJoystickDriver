import Foundation

@testable import OpenJoystickDriverKit

final class RecoveryInputParser: PhysicalProtocolDriver, @unchecked Sendable {
  let capabilities = ControllerCapabilities(controls: Control.xboxLayout)
  let sessionPlan = DriverSessionPlan()
  let outputCapabilities = PhysicalControllerOutputCapabilities.none
  let defaultColor: ControllerColor? = nil
  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }
  private let lock = NSLock()
  private var storedResetCount = 0

  var resetCount: Int { lock.withLock { storedResetCount } }

  func parse(report data: Data, receivedAt: MonotonicTimestamp) -> ControllerEvent? {
    data == Data([1]) ? ControllerEvent([.press(.south)], at: receivedAt.nanoseconds) : nil
  }

  func resetProtocolState() { lock.withLock { storedResetCount += 1 } }
}

final class RecoveryRumbleParser: PhysicalProtocolDriver, @unchecked Sendable {
  let capabilities = ControllerCapabilities(controls: Control.xboxLayout)
  let sessionPlan = DriverSessionPlan()
  let outputCapabilities = PhysicalControllerOutputCapabilities(rumbleMotors: [
    .lowFrequency, .highFrequency, .leftTrigger, .rightTrigger,
  ])
  let defaultColor: ControllerColor? = nil
  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  func parse(report data: Data, receivedAt: MonotonicTimestamp) -> ControllerEvent? {
    data == Data([1]) ? ControllerEvent([.press(.south)], at: receivedAt.nanoseconds) : nil
  }

  func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    let intensities: RumbleIntensities
    switch command {
    case .setRumble(let requested, _): intensities = requested
    case .stopRumble: intensities = .off
    default: throw .unsupportedCapability(command.capability)
    }
    let bytes = [PhysicalRumbleMotor.lowFrequency, .highFrequency, .leftTrigger, .rightTrigger].map
    {
      intensities[$0].byte
    }
    return PhysicalOutputPlan(writes: [
      .usb(PhysicalUSBOutputPacket(endpoint: 2, bytes: bytes, timeoutMilliseconds: 2_000))
    ])
  }

  /// The USB packets of one rumble request.
  func rumblePackets(
    _ left: UInt8,
    _ right: UInt8,
    _ lt: UInt8,
    _ rt: UInt8
  ) -> [PhysicalUSBOutputPacket] {
    let intensities: [PhysicalRumbleMotor: UInt8] = [
      .lowFrequency: left, .highFrequency: right, .leftTrigger: lt, .rightTrigger: rt,
    ]
    let command = ControllerOutputCommand.setRumble(
      RumbleIntensities(bytes: intensities),
      duration: .milliseconds(0)
    )
    return encoded(command)?.writes.usbPackets ?? []
  }
}
