public import Foundation

/// The report ID of the state report.
private let shieldStateReportID: UInt8 = 0x01
/// The report ID of the touch report.
private let shieldTouchReportID: UInt8 = 0x02
/// The length of the state report of the 2015 Shield controller (V103).
private let shieldV103StateLength = 16
/// The shortest V104 state report.
private let shieldV104StateLength = 23
/// The raw value of a centered stick axis.
private let shieldAxisCenter = 0x8000
/// The largest distance of a raw stick axis from its center.
private let shieldAxisMagnitude: Float = 32767
/// The maximum raw value of a trigger.
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

  /// The bit masks of the face buttons, shoulders and stick clicks in the button byte.
  private enum FaceMask {
    /// The south button.
    static let south: UInt8 = 0x01
    /// The east button.
    static let east: UInt8 = 0x02
    /// The west button.
    static let west: UInt8 = 0x04
    /// The north button.
    static let north: UInt8 = 0x08
    /// The left shoulder.
    static let leftShoulder: UInt8 = 0x10
    /// The right shoulder.
    static let rightShoulder: UInt8 = 0x20
    /// The left stick click.
    static let leftStick: UInt8 = 0x40
    /// The right stick click.
    static let rightStick: UInt8 = 0x80
  }

  /// Whether the controller is the 2015 controller (V103).
  private let isV103: Bool
  /// The V103 rumble report; nil for the 2017 controller, which has no plain rumble.
  private let rumbleTemplate: RumbleOutputTemplate?
  /// The state after the latest report.
  private var state = ControllerState.neutral
  /// The rumble that the latest command set.
  private var lastRumble = RumbleIntensities.off

  /// Creates a driver for the 2017 controller, or for the 2015 controller when its record declares
  /// the `reportRevision: Shield2015` parameter; only the 2015 controller has plain rumble.
  ///
  /// - Parameters:
  ///   - isShield2015: Whether the controller is the 2015 controller.
  ///   - rumbleTemplate: The record's rumble template for the 2015 controller; the description's
  ///     when nil.
  public init(isShield2015: Bool, rumbleTemplate: RumbleOutputTemplate? = nil) {
    isV103 = isShield2015
    self.rumbleTemplate =
      isShield2015
      ? PhysicalProtocolID.vendorNVIDIAShield.describedRumbleTemplate(
        variant: nil,
        record: rumbleTemplate
      ) : nil
  }

  /// Clears the state and the latest rumble, so the next report starts from neutral.
  public func resetProtocolState() {
    state = .neutral
    lastRumble = .off
  }

  /// The session plan: the rumble resend of the template, if there is one.
  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan().withRumbleResend(of: rumbleTemplate)
  }

  /// The last rumble again while a motor runs, when the template names a resend interval.
  public func keepAliveWrites() -> [PhysicalOutputWrite] {
    guard let rumbleTemplate, let intensities = rumbleTemplate.resendIntensities(after: lastRumble)
    else { return [] }
    return [rumbleTemplate.write(intensities)]
  }
  /// The rumble motors of the rumble template; none without a template.
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    rumbleTemplate?.outputCapabilities ?? .none
  }
  /// No default colour: the controller has no light to restore.
  public var defaultColor: ControllerColor? { nil }

  /// Always nil: the report carries no logical connection.
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  /// The controls of the description, plus the touchpad click on the 2015 controller.
  public var capabilities: ControllerCapabilities {
    PhysicalProtocolID.vendorNVIDIAShield.describedControls.union(
      ControllerCapabilities(controls: isV103 ? [.touchpadClick] : [])
    )
  }

  /// V103 rumble through the rumble template; the 2017 controller has none.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    guard let rumbleTemplate else { throw .unsupportedCapability(command.capability) }
    let plan = try rumbleTemplate.encode(command)
    lastRumble = command.rumbleIntensities
    return plan
  }

  /// Decodes a state report (16 bytes for V103, 23 or more for V104) or a V103 touch report; any
  /// other report is ignored.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) -> ControllerEvent? {
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

  /// Applies a V103 state report to `next`.
  private static func applyV103State(_ bytes: [UInt8], to next: inout ControllerState) {
    next.hat = direction(for: bytes[3])
    applyFaceAndShoulders(bytes[1], to: &next)
    next.set(.start, pressed: bytes[2] & 0x02 != 0)
    next.set(.back, pressed: bytes[2] & 0x40 != 0)
    next.set(.guide, pressed: bytes[2] & 0x80 != 0)
    applyAxes(bytes, sticks: 4, triggers: 12, to: &next)
  }

  /// Applies a V104 state report to `next`.
  private static func applyV104State(_ bytes: [UInt8], to next: inout ControllerState) {
    next.hat = direction(for: bytes[2])
    applyFaceAndShoulders(bytes[3], to: &next)
    next.set(.start, pressed: bytes[4] & 0x01 != 0)
    next.set(.guide, pressed: bytes[17] & 0x01 != 0)
    next.set(.back, pressed: bytes[17] & 0x02 != 0)
    applyAxes(bytes, sticks: 9, triggers: 19, to: &next)
  }

  /// Applies the face buttons, shoulders and stick clicks of `byte` to `next`.
  private static func applyFaceAndShoulders(_ byte: UInt8, to next: inout ControllerState) {
    for (mask, control) in [
      (FaceMask.south, Control.south), (FaceMask.east, .east), (FaceMask.west, .west),
      (FaceMask.north, .north), (FaceMask.leftShoulder, .leftShoulder),
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
    next.leftStick = StickPosition(x: stick(sticks), y: stick(sticks + 2))
    next.rightStick = StickPosition(x: stick(sticks + 4), y: stick(sticks + 6))
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
