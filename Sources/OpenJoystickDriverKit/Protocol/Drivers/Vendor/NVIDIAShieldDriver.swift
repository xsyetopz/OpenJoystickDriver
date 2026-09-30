import Foundation

private let shieldStateReportID: UInt8 = 0x01
private let shieldTouchReportID: UInt8 = 0x02
private let shieldV103ProductID: UInt16 = 0x7210
private let shieldV103StateLength = 16
private let shieldV104StateLength = 23
private let shieldV103RumbleReportID: UInt8 = 0x01
private let shieldAxisCenter = 0x8000
private let shieldAxisMagnitude: Float = 32767
private let shieldTriggerMax: Float = 65535

/// Driver for the NVIDIA SHIELD controllers: the 2015 controller (`0955:7210`, V103) and the 2017
/// controller (`0955:7214`, V104).
///
/// Both report ID 1 state reports on IOHID, but not in the Xbox layout their XInput-style
/// descriptor suggests. The layout follows SDL `SDL_hidapi_shield.c`: a 16-byte report is V103,
/// anything of 23 bytes or more is V104. V103 carries rumble in a plain output report. V104 carries
/// rumble and battery in sequenced command reports, which SDL disables on macOS because the output
/// write hangs for several seconds; this driver follows SDL and exposes V104 as input-only.
public final class NVIDIAShieldDriver: PhysicalProtocolDriver {

  private enum FaceMask {
    static let south: UInt8 = 0x01
    static let east: UInt8 = 0x02
    static let west: UInt8 = 0x04
    static let north: UInt8 = 0x08
    static let leftShoulder: UInt8 = 0x10
    static let rightShoulder: UInt8 = 0x20
    static let leftStick: UInt8 = 0x40
    static let rightStick: UInt8 = 0x80
  }

  private let isV103: Bool
  private var state = ControllerState.neutral

  /// Creates a driver for the SHIELD controller with `productID`; only V103 has plain rumble.
  public init(productID: UInt16) { isV103 = productID == shieldV103ProductID }

  public func resetProtocolState() { state = .neutral }

  public var sessionPlan: DriverSessionPlan { DriverSessionPlan() }
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    isV103 ? .dualMainRumble : .none
  }
  public var defaultColor: ControllerColor? { nil }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  public var capabilities: ControllerCapabilities {
    ControllerCapabilities(
      controls: ControlID.xboxLayout.union(isV103 ? [.guide, .touchpadClick] : [.guide])
    )
  }

  /// V103 rumble: `[1, 0, low, 0, high, 0, 0]`, one byte per motor.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    guard isV103 else { throw .unsupportedCapability(command.capability) }
    let (left, right): (UInt8, UInt8)
    switch command {
    case .setRumble(let intensities, _):
      (left, right) = (intensities.leftMain.byte, intensities.rightMain.byte)
    case .stopRumble: (left, right) = (0, 0)
    default: throw .unsupportedCapability(command.capability)
    }
    let bytes: [UInt8] = [shieldV103RumbleReportID, 0x00, left, 0x00, right, 0x00, 0x00]
    return PhysicalOutputPlan(writes: [
      .hidOutput(PhysicalHIDOutputReport(reportID: shieldV103RumbleReportID, bytes: bytes))
    ])
  }

  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = [UInt8](data)
    var next = state
    switch bytes.first {
    case shieldStateReportID where bytes.count == shieldV103StateLength:
      Self.applyV103State(bytes, to: &next)
    case shieldStateReportID where bytes.count >= shieldV104StateLength:
      Self.applyV104State(bytes, to: &next)
    case shieldTouchReportID where isV103 && bytes.count >= 2:
      next.set(.touchpadClick, pressed: bytes[1] & 0x01 != 0)
    default: return nil
    }
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  private static func applyV103State(_ bytes: [UInt8], to next: inout ControllerState) {
    next.hat = direction(for: bytes[3])
    applyFaceAndShoulders(bytes[1], to: &next)
    next.set(.menu, pressed: bytes[2] & 0x02 != 0)
    next.set(.view, pressed: bytes[2] & 0x40 != 0)
    next.set(.guide, pressed: bytes[2] & 0x80 != 0)
    applyAxes(bytes, sticks: 4, triggers: 12, to: &next)
  }

  private static func applyV104State(_ bytes: [UInt8], to next: inout ControllerState) {
    next.hat = direction(for: bytes[2])
    applyFaceAndShoulders(bytes[3], to: &next)
    next.set(.menu, pressed: bytes[4] & 0x01 != 0)
    next.set(.guide, pressed: bytes[17] & 0x01 != 0)
    next.set(.view, pressed: bytes[17] & 0x02 != 0)
    applyAxes(bytes, sticks: 9, triggers: 19, to: &next)
  }

  private static func applyFaceAndShoulders(_ byte: UInt8, to next: inout ControllerState) {
    for (mask, control) in [
      (FaceMask.south, ControlID.faceSouth), (FaceMask.east, .faceEast), (FaceMask.west, .faceWest),
      (FaceMask.north, .faceNorth), (FaceMask.leftShoulder, .leftShoulder),
      (FaceMask.rightShoulder, .rightShoulder), (FaceMask.leftStick, .leftStickClick),
      (FaceMask.rightStick, .rightStickClick),
    ] { next.set(control, pressed: byte & mask != 0) }
  }

  /// Four stick words from `sticks` (LX, LY, RX, RY) and two trigger words from `triggers`, all
  /// little-endian 16-bit; sticks center on 0x8000 with Y positive down, triggers rest at 0.
  private static func applyAxes(
    _ bytes: [UInt8],
    sticks: Int,
    triggers: Int,
    to next: inout ControllerState
  ) {
    func word(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
    func stick(_ offset: Int) -> Float {
      max(-1, min(1, Float(word(offset) - shieldAxisCenter) / shieldAxisMagnitude))
    }
    next.leftStick = StickPosition(x: stick(sticks), yDown: stick(sticks + 2))
    next.rightStick = StickPosition(x: stick(sticks + 4), yDown: stick(sticks + 6))
    next.leftTrigger = UnipolarValue(normalized: Float(word(triggers)) / shieldTriggerMax)
    next.rightTrigger = UnipolarValue(normalized: Float(word(triggers + 2)) / shieldTriggerMax)
  }

  /// 0 = up, increasing clockwise to 7 = up-left; anything else is neutral.
  private static func direction(for hat: UInt8) -> HatDirection {
    switch hat {
    case 0: return .north
    case 1: return .northEast
    case 2: return .east
    case 3: return .southEast
    case 4: return .south
    case 5: return .southWest
    case 6: return .west
    case 7: return .northWest
    default: return .neutral
    }
  }
}
