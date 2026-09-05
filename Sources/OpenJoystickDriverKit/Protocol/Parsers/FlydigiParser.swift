import Foundation

private let flydigiInputReportID: UInt8 = 0x01
private let flydigiReportLength = 15
private let flydigiAxisDeadzone: Float = 0.08
private let flydigiAxisMagnitude: Float = 127
private let flydigiTriggerMax: Float = 255
private let flydigiHatNeutral: UInt8 = 0

/// Parser for Flydigi Vader-family controllers on Bluetooth Low Energy.
///
/// The report declares GamePad usage and standard Generic Desktop axes, but
/// packs the right stick into Z/Rz and the analog triggers into the Simulation
/// page, so the descriptor-driven fallback maps neither correctly. Button
/// usages are also non-contiguous, which shifts every index after the first
/// gap. This parser reads the observed 15-byte layout by offset instead.
public final class FlydigiParser: InputParser, @unchecked Sendable {

  private enum ReportOffset {
    static let leftStickX: Int = 1
    static let leftStickY: Int = 2
    static let rightStickX: Int = 3
    static let rightStickY: Int = 4
    /// Low nibble is the D-pad hat; high nibble carries the face buttons.
    static let hatAndFace: Int = 9
    static let shoulders: Int = 10
    static let extras: Int = 11
    static let system: Int = 12
    static let leftTrigger: Int = 13
    static let rightTrigger: Int = 14
  }

  private enum FaceMask {
    static let a: UInt8 = 0x10
    static let b: UInt8 = 0x20
    static let x: UInt8 = 0x40
    static let y: UInt8 = 0x80
  }

  private enum ShoulderMask {
    static let leftBumper: UInt8 = 0x01
    static let rightBumper: UInt8 = 0x02
    static let leftTrigger: UInt8 = 0x04
    static let rightTrigger: UInt8 = 0x08
    static let back: UInt8 = 0x10
    static let start: UInt8 = 0x20
    static let leftStick: UInt8 = 0x40
    static let rightStick: UInt8 = 0x80
  }

  private enum SystemMask {
    static let guide: UInt8 = 0x80
  }

  private var prevHatAndFace: UInt8 = 0
  private var prevShoulders: UInt8 = 0
  private var prevSystem: UInt8 = 0
  private var prevLeftTrigger: UInt8 = 0
  private var prevRightTrigger: UInt8 = 0
  private var prevLeftStickX: UInt8 = 0xFF
  private var prevLeftStickY: UInt8 = 0xFF
  private var prevRightStickX: UInt8 = 0xFF
  private var prevRightStickY: UInt8 = 0xFF
  private let stateLock = NSLock()

  /// Creates a new FlydigiParser.
  public init() {}

  /// No-op because the controller streams input without a handshake.
  public func performHandshake(handle: (any USBTransportSession)?) throws {
    // Required by InputParser; Flydigi BLE needs no handshake.
  }

  /// Parses one Flydigi input report and returns zero or more controller events.
  public func parse(data: Data) throws -> [ControllerEvent] {
    let bytes = reportPayload(from: data)
    guard bytes.count >= flydigiReportLength else { return [] }

    return stateLock.withLock {
      var events: [ControllerEvent] = []
      events += faceEvents(bytes[ReportOffset.hatAndFace])
      events += hatEvents(bytes[ReportOffset.hatAndFace])
      events += shoulderEvents(bytes[ReportOffset.shoulders])
      events += systemEvents(bytes[ReportOffset.system])
      events += triggerEvents(bytes)
      events += stickEvents(bytes)
      prevHatAndFace = bytes[ReportOffset.hatAndFace]
      prevShoulders = bytes[ReportOffset.shoulders]
      prevSystem = bytes[ReportOffset.system]
      prevLeftTrigger = bytes[ReportOffset.leftTrigger]
      prevRightTrigger = bytes[ReportOffset.rightTrigger]
      prevLeftStickX = bytes[ReportOffset.leftStickX]
      prevLeftStickY = bytes[ReportOffset.leftStickY]
      prevRightStickX = bytes[ReportOffset.rightStickX]
      prevRightStickY = bytes[ReportOffset.rightStickY]
      return events
    }
  }

  /// Strips the leading report ID when IOKit delivers it inline.
  private func reportPayload(from data: Data) -> [UInt8] {
    let bytes = [UInt8](data)
    guard bytes.count == flydigiReportLength, bytes.first == flydigiInputReportID else {
      return bytes
    }
    return bytes
  }

  /// Maps the A, B, X, and Y bits packed into the high nibble of byte 9.
  private func faceEvents(_ value: UInt8) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    let pairs: [(UInt8, Button)] = [
      (FaceMask.a, .a), (FaceMask.b, .b), (FaceMask.x, .x), (FaceMask.y, .y)
    ]
    for (mask, button) in pairs {
      events += transition(mask: mask, current: value, previous: prevHatAndFace, button: button)
    }
    return events
  }

  /// Maps bumpers, Select, Start, and stick clicks. The trigger bits in this
  /// byte are handled by ``triggerEvents(_:)`` instead.
  private func shoulderEvents(_ value: UInt8) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    let pairs: [(UInt8, Button)] = [
      (ShoulderMask.leftBumper, .leftBumper),
      (ShoulderMask.rightBumper, .rightBumper),
      (ShoulderMask.back, .back),
      (ShoulderMask.start, .start),
      (ShoulderMask.leftStick, .leftStick),
      (ShoulderMask.rightStick, .rightStick)
    ]
    for (mask, button) in pairs {
      events += transition(mask: mask, current: value, previous: prevShoulders, button: button)
    }
    return events
  }

  /// Maps the Home button, which is the only control in byte 12.
  private func systemEvents(_ value: UInt8) -> [ControllerEvent] {
    transition(mask: SystemMask.guide, current: value, previous: prevSystem, button: .guide)
  }

  /// Emits a press or release only when the masked bit changed.
  private func transition(mask: UInt8, current: UInt8, previous: UInt8, button: Button)
    -> [ControllerEvent]
  {
    let isPressed = current & mask != 0
    guard isPressed != (previous & mask != 0) else { return [] }
    return [isPressed ? .buttonPressed(button) : .buttonReleased(button)]
  }

  /// The D-pad is a 4-bit hat in the low nibble, 1 = up and increasing clockwise.
  private func hatEvents(_ value: UInt8) -> [ControllerEvent] {
    let hat = value & 0x0F
    guard hat != prevHatAndFace & 0x0F else { return [] }
    return [.dpadChanged(Self.direction(for: hat))]
  }

  /// Converts a hat value to a compass direction; anything outside 1...8 is neutral.
  private static func direction(for hat: UInt8) -> DpadDirection {
    switch hat {
    case 1: return .north
    case 2: return .northEast
    case 3: return .east
    case 4: return .southEast
    case 5: return .south
    case 6: return .southWest
    case 7: return .west
    case 8: return .northWest
    default: return .neutral
    }
  }

  /// The digital bit in the shoulder byte tracks the analog value, so the
  /// analog byte alone drives the reported trigger position.
  private func triggerEvents(_ bytes: [UInt8]) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    let left = bytes[ReportOffset.leftTrigger]
    let right = bytes[ReportOffset.rightTrigger]
    if left != prevLeftTrigger {
      events.append(.leftTriggerChanged(Float(left) / flydigiTriggerMax))
    }
    if right != prevRightTrigger {
      events.append(.rightTriggerChanged(Float(right) / flydigiTriggerMax))
    }
    return events
  }

  /// Emits a stick event when either axis of that stick moved, so paired
  /// coordinates stay consistent.
  private func stickEvents(_ bytes: [UInt8]) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    let leftChanged =
      bytes[ReportOffset.leftStickX] != prevLeftStickX
      || bytes[ReportOffset.leftStickY] != prevLeftStickY
    if leftChanged {
      events.append(
        .leftStickChanged(
          x: Self.axis(bytes[ReportOffset.leftStickX]),
          y: Self.axis(bytes[ReportOffset.leftStickY])
        )
      )
    }
    let rightChanged =
      bytes[ReportOffset.rightStickX] != prevRightStickX
      || bytes[ReportOffset.rightStickY] != prevRightStickY
    if rightChanged {
      events.append(
        .rightStickChanged(
          x: Self.axis(bytes[ReportOffset.rightStickX]),
          y: Self.axis(bytes[ReportOffset.rightStickY])
        )
      )
    }
    return events
  }

  /// Converts one signed axis byte to -1...1, where the hardware reports
  /// negative for up and left.
  static func axis(_ raw: UInt8) -> Float {
    let signed = Float(Int8(bitPattern: raw))
    let normalized = max(-1, min(1, signed / flydigiAxisMagnitude))
    return abs(normalized) < flydigiAxisDeadzone ? 0 : normalized
  }
}
