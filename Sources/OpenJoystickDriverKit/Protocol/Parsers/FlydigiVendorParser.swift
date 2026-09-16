import Foundation

private let flydigiVendorReportLength = 32
private let flydigiVendorMagic: [UInt8] = [0x04, 0xFE, 0x66]
private let flydigiVendorAxisCenter: UInt8 = 0x7F
private let flydigiVendorAxisSpan: Float = 127
private let flydigiVendorAxisDeadzone: Float = 0.08
private let flydigiVendorTriggerMax: Float = 255
private let flydigiVendorRumbleReportID: UInt8 = 0x05
private let flydigiVendorRumbleCommand: UInt8 = 0x0F
/// The controller plays one frame and decays, so sustained vibration needs the
/// frame resent; 100 ms keeps it continuous without flooding the link.
private let flydigiVendorRumbleIntervalNanoseconds: UInt64 = 100_000_000

/// Parser for the Flydigi vendor protocol carried on HID usage page `0xFFA0`.
///
/// Flydigi controllers on their 2.4 GHz dongle in DInput mode expose a
/// composite device whose vendor interface streams a 32-byte report prefixed
/// `04 FE 66`. This is the only mode in which the back paddles send their own
/// signals; elsewhere they repeat whichever button the controller's firmware
/// assigns them, and no driver can separate them.
///
/// Bytes 4 through 6, 26, 27, 29 and 30 carry motion data that changes
/// continuously even at rest, and bytes 11 through 15 behave as a counter.
/// Neither correlates with any control, so both are ignored.
public final class FlydigiVendorParser: InputParser, PhysicalHIDRumbleOutput, @unchecked Sendable {

  private enum ReportOffset {
    /// Back paddles and the two extra shoulder buttons.
    static let extras = 7
    static let system = 8
    /// D-pad in the low nibble, three face buttons plus Select in the high nibble.
    static let dpadAndFace = 9
    static let shoulders = 10
    static let leftStickX = 17
    static let leftStickY = 19
    static let rightStickX = 21
    static let rightStickY = 22
    static let leftTrigger = 23
    static let rightTrigger = 24
  }

  private enum ExtrasMask {
    static let c: UInt8 = 0x01
    static let z: UInt8 = 0x02
    static let m1: UInt8 = 0x04
    static let m2: UInt8 = 0x08
    static let m3: UInt8 = 0x10
    static let m4: UInt8 = 0x20
  }

  private enum DpadFaceMask {
    static let up: UInt8 = 0x01
    static let right: UInt8 = 0x02
    static let down: UInt8 = 0x04
    static let left: UInt8 = 0x08
    static let a: UInt8 = 0x10
    static let b: UInt8 = 0x20
    static let back: UInt8 = 0x40
    static let x: UInt8 = 0x80
  }

  private enum ShoulderMask {
    static let y: UInt8 = 0x01
    static let start: UInt8 = 0x02
    static let leftBumper: UInt8 = 0x04
    static let rightBumper: UInt8 = 0x08
    static let leftTrigger: UInt8 = 0x10
    static let rightTrigger: UInt8 = 0x20
    static let leftStick: UInt8 = 0x40
    static let rightStick: UInt8 = 0x80
  }

  private enum SystemMask { static let guide: UInt8 = 0x08 }

  private var prevExtras: UInt8 = 0
  private var prevSystem: UInt8 = 0
  private var prevDpadAndFace: UInt8 = 0
  private var prevShoulders: UInt8 = 0
  private var prevLeftTrigger: UInt8 = 0
  private var prevRightTrigger: UInt8 = 0
  private var prevLeftX = flydigiVendorAxisCenter
  private var prevLeftY = flydigiVendorAxisCenter
  private var prevRightX = flydigiVendorAxisCenter
  private var prevRightY = flydigiVendorAxisCenter
  private let stateLock = NSLock()

  /// Creates a new FlydigiVendorParser.
  public init() {}

  /// Parses one vendor input report and returns zero or more controller events.
  public func parse(data: Data) throws -> [ControllerEvent] {
    let bytes = [UInt8](data)
    guard bytes.count == flydigiVendorReportLength, Array(bytes.prefix(3)) == flydigiVendorMagic
    else { return [] }

    return stateLock.withLock {
      var events: [ControllerEvent] = []
      events += extrasEvents(bytes[ReportOffset.extras])
      events += systemEvents(bytes[ReportOffset.system])
      events += faceEvents(bytes[ReportOffset.dpadAndFace])
      events += dpadEvents(bytes[ReportOffset.dpadAndFace])
      events += shoulderEvents(bytes[ReportOffset.shoulders])
      events += triggerEvents(bytes)
      events += stickEvents(bytes)
      prevExtras = bytes[ReportOffset.extras]
      prevSystem = bytes[ReportOffset.system]
      prevDpadAndFace = bytes[ReportOffset.dpadAndFace]
      prevShoulders = bytes[ReportOffset.shoulders]
      prevLeftTrigger = bytes[ReportOffset.leftTrigger]
      prevRightTrigger = bytes[ReportOffset.rightTrigger]
      prevLeftX = bytes[ReportOffset.leftStickX]
      prevLeftY = bytes[ReportOffset.leftStickY]
      prevRightX = bytes[ReportOffset.rightStickX]
      prevRightY = bytes[ReportOffset.rightStickY]
      return events
    }
  }

  // MARK: - Physical output

  /// Both motors are independently addressable and differ in strength: the
  /// left is weaker than the right on the tested hardware.
  public var physicalRumbleMotors: [PhysicalRumbleMotor] { [.leftMain, .rightMain] }

  public var minimumPhysicalOutputIntervalNanoseconds: UInt64 {
    flydigiVendorRumbleIntervalNanoseconds
  }

  /// Builds the four-byte vendor rumble frame.
  ///
  /// The frame latches: the motors run until a frame with zero magnitudes
  /// arrives, so a caller that stops sending without sending a stop leaves
  /// them running. The controller has no trigger actuators, so `lt` and `rt`
  /// are ignored.
  public func physicalRumbleReport(
    left: UInt8,
    right: UInt8,
    lt _: UInt8,
    rt _: UInt8
  ) -> PhysicalHIDOutputReport {
    PhysicalHIDOutputReport(
      reportID: flydigiVendorRumbleReportID,
      bytes: [flydigiVendorRumbleReportID, flydigiVendorRumbleCommand, left, right]
    )
  }

  // MARK: - Input

  /// Maps the six controls that only this transport reports separately.
  private func extrasEvents(_ value: UInt8) -> [ControllerEvent] {
    let pairs: [(UInt8, Button)] = [
      (ExtrasMask.c, .leftFunction), (ExtrasMask.z, .rightFunction), (ExtrasMask.m1, .leftPaddle),
      (ExtrasMask.m2, .rightPaddle), (ExtrasMask.m3, .leftGrip), (ExtrasMask.m4, .rightGrip),
    ]
    return pairs.flatMap {
      transition(mask: $0.0, current: value, previous: prevExtras, button: $0.1)
    }
  }

  /// Maps Home, the only control in byte 8.
  private func systemEvents(_ value: UInt8) -> [ControllerEvent] {
    transition(mask: SystemMask.guide, current: value, previous: prevSystem, button: .guide)
  }

  /// Maps the three face buttons and Select that share byte 9 with the
  /// D-pad. Y sits in the shoulder byte instead.
  private func faceEvents(_ value: UInt8) -> [ControllerEvent] {
    let pairs: [(UInt8, Button)] = [
      (DpadFaceMask.a, .a), (DpadFaceMask.b, .b), (DpadFaceMask.x, .x), (DpadFaceMask.back, .back),
    ]
    return pairs.flatMap {
      transition(mask: $0.0, current: value, previous: prevDpadAndFace, button: $0.1)
    }
  }

  /// Maps Y, Start, both bumpers and both stick clicks. The trigger bits in
  /// this byte are handled by ``triggerEvents(_:)`` instead.
  private func shoulderEvents(_ value: UInt8) -> [ControllerEvent] {
    let pairs: [(UInt8, Button)] = [
      (ShoulderMask.y, .y), (ShoulderMask.start, .start), (ShoulderMask.leftBumper, .leftBumper),
      (ShoulderMask.rightBumper, .rightBumper), (ShoulderMask.leftStick, .leftStick),
      (ShoulderMask.rightStick, .rightStick),
    ]
    return pairs.flatMap {
      transition(mask: $0.0, current: value, previous: prevShoulders, button: $0.1)
    }
  }

  /// Emits a press or release only when the masked bit changed.
  private func transition(
    mask: UInt8,
    current: UInt8,
    previous: UInt8,
    button: Button
  ) -> [ControllerEvent] {
    let isPressed = current & mask != 0
    guard isPressed != (previous & mask != 0) else { return [] }
    return [isPressed ? .buttonPressed(button) : .buttonReleased(button)]
  }

  /// The D-pad occupies the low nibble as four direction bits in up, right,
  /// down, left order rather than as a hat value.
  private func dpadEvents(_ value: UInt8) -> [ControllerEvent] {
    let current = value & 0x0F
    guard current != prevDpadAndFace & 0x0F else { return [] }
    return [.dpadChanged(Self.direction(for: current))]
  }

  /// Resolves four direction bits to a compass direction, treating any
  /// adjacent pair as the diagonal between them.
  private static func direction(for bits: UInt8) -> DpadDirection {
    let up = bits & DpadFaceMask.up != 0
    let right = bits & DpadFaceMask.right != 0
    let down = bits & DpadFaceMask.down != 0
    let left = bits & DpadFaceMask.left != 0
    switch (up, right, down, left) {
    case (true, true, _, _): return .northEast
    case (true, _, _, true): return .northWest
    case (_, true, true, _): return .southEast
    case (_, _, true, true): return .southWest
    case (true, _, _, _): return .north
    case (_, true, _, _): return .east
    case (_, _, true, _): return .south
    case (_, _, _, true): return .west
    default: return .neutral
    }
  }

  /// The digital trigger bits in the shoulder byte accompany the analog values
  /// rather than replacing them, so position comes from the analog bytes alone.
  private func triggerEvents(_ bytes: [UInt8]) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    let left = bytes[ReportOffset.leftTrigger]
    let right = bytes[ReportOffset.rightTrigger]
    if left != prevLeftTrigger {
      events.append(.leftTriggerChanged(Float(left) / flydigiVendorTriggerMax))
    }
    if right != prevRightTrigger {
      events.append(.rightTriggerChanged(Float(right) / flydigiVendorTriggerMax))
    }
    return events
  }

  /// Converts one axis byte to -1...1 about its `0x7F` centre.
  static func axis(_ raw: UInt8) -> Float {
    let offset = Float(Int(raw) - Int(flydigiVendorAxisCenter))
    let normalized = max(-1, min(1, offset / flydigiVendorAxisSpan))
    return abs(normalized) < flydigiVendorAxisDeadzone ? 0 : normalized
  }

  /// Emits a stick event when either of its axes moved, so paired
  /// coordinates stay consistent.
  private func stickEvents(_ bytes: [UInt8]) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    let leftX = bytes[ReportOffset.leftStickX]
    let leftY = bytes[ReportOffset.leftStickY]
    if leftX != prevLeftX || leftY != prevLeftY {
      events.append(.leftStickChanged(x: Self.axis(leftX), y: Self.axis(leftY)))
    }
    let rightX = bytes[ReportOffset.rightStickX]
    let rightY = bytes[ReportOffset.rightStickY]
    if rightX != prevRightX || rightY != prevRightY {
      events.append(.rightStickChanged(x: Self.axis(rightX), y: Self.axis(rightY)))
    }
    return events
  }
}
