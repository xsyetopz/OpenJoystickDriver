/// Signed sensor readings before controller-specific factory calibration.
/// Only drivers see these; published samples carry SI values.
struct ControllerRawSensorVector: Equatable {
  let x: Int16
  let y: Int16
  let z: Int16
}

public enum ControllerSampleTimeBasis: String, Sendable, Codable {
  case deviceCounter
  case hostEstimate
}

/// Receipt-anchored sensor time: the `MonotonicTimestamp` receipt time of the parser session's
/// first sample plus the sensor time elapsed since it. Device counters carry rational tick units
/// and add ticks at that nominal rate with no rate correction; a report gap of a whole counter
/// period or more (about 350 ms for the DS4 16-bit counter) is not recovered. This time can
/// therefore drift from the receipt time in `ControllerEvent.timestamp`. Host estimates leave the
/// tick units absent. A new parser session re-anchors; within one session time never decreases.
public struct ControllerSampleTimestamp: Sendable, Equatable, Codable {
  public let basis: ControllerSampleTimeBasis
  public let rawCounter: UInt32
  public let monotonic: MonotonicTimestamp
  public let tickNanosecondsNumerator: UInt32?
  public let tickNanosecondsDenominator: UInt32?
  public let sequenceIndex: UInt64

  public init(
    rawCounter: UInt32,
    monotonic: MonotonicTimestamp,
    tickNanosecondsNumerator: UInt32?,
    tickNanosecondsDenominator: UInt32?,
    sequenceIndex: UInt64,
    basis: ControllerSampleTimeBasis = .deviceCounter
  ) {
    self.basis = basis
    self.rawCounter = rawCounter
    self.monotonic = monotonic
    self.tickNanosecondsNumerator = tickNanosecondsNumerator
    self.tickNanosecondsDenominator = tickNanosecondsDenominator
    self.sequenceIndex = sequenceIndex
  }
}

/// One IMU sample in SI units and the canonical controller frame: right-handed, +X to the
/// controller's right, +Y away from the player along the face, +Z upward through the face.
/// Each producer documents and tests its raw-to-canonical transform.
public struct ControllerMotionSample: Sendable, Equatable, Codable {
  public let timestamp: ControllerSampleTimestamp
  /// Metres per second squared. A controller lying face up at rest reads about +9.81 on Z.
  public let acceleration: ControllerMotionVector
  /// Radians per second about each canonical axis, positive by the right-hand rule.
  public let angularVelocity: ControllerMotionVector
  public let calibrationSource: ControllerMotionCalibrationSource
  /// Changes when installed calibration coefficients change within a controller session.
  public let calibrationRevision: UInt64

  public init?(
    timestamp: ControllerSampleTimestamp,
    acceleration: ControllerMotionVector,
    angularVelocity: ControllerMotionVector,
    calibrationSource: ControllerMotionCalibrationSource,
    calibrationRevision: UInt64 = 0
  ) {
    guard acceleration.isFinite, angularVelocity.isFinite else { return nil }
    self.timestamp = timestamp
    self.acceleration = acceleration
    self.angularVelocity = angularVelocity
    self.calibrationSource = calibrationSource
    self.calibrationRevision = calibrationRevision
  }

  /// Scales factory-calibrated degrees per second and standard gravities, already permuted into
  /// the canonical axes, to SI.
  init?(
    timestamp: ControllerSampleTimestamp,
    canonicalDegreesPerSecond gyro: ControllerMotionVector,
    canonicalG accel: ControllerMotionVector,
    calibrationSource: ControllerMotionCalibrationSource,
    calibrationRevision: UInt64 = 0
  ) {
    let radians = ControllerMotionUnits.radiansPerDegree
    let gravity = ControllerMotionUnits.standardGravity
    self.init(
      timestamp: timestamp,
      acceleration: ControllerMotionVector(
        x: accel.x * gravity,
        y: accel.y * gravity,
        z: accel.z * gravity
      ),
      angularVelocity: ControllerMotionVector(
        x: gyro.x * radians,
        y: gyro.y * radians,
        z: gyro.z * radians
      ),
      calibrationSource: calibrationSource,
      calibrationRevision: calibrationRevision
    )
  }

  private enum CodingKeys: String, CodingKey {
    case timestamp, acceleration, angularVelocity, calibrationSource, calibrationRevision
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard
      let sample = try Self(
        timestamp: container.decode(ControllerSampleTimestamp.self, forKey: .timestamp),
        acceleration: container.decode(ControllerMotionVector.self, forKey: .acceleration),
        angularVelocity: container.decode(ControllerMotionVector.self, forKey: .angularVelocity),
        calibrationSource: container.decode(
          ControllerMotionCalibrationSource.self,
          forKey: .calibrationSource
        ),
        calibrationRevision: container.decode(UInt64.self, forKey: .calibrationRevision)
      )
    else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Motion samples must be finite")
      )
    }
    self = sample
  }
}

/// One contact of a touch frame.
/// `x` and `y` span the whole surface: 0 is the left or top edge and 65535 the right or bottom
/// edge, so Y grows toward the player on every surface.
public struct ControllerTouchContact: Sendable, Equatable, Codable {
  /// The contact's position in the frame's hardware contact array. The same finger keeps its slot
  /// until it lifts; a new finger may reuse a freed slot.
  public let slot: UInt8
  public let isActive: Bool
  public let x: UInt16
  public let y: UInt16
  /// Contact pressure where the hardware reports it; only the Steam Triton does.
  public let pressure: UnipolarValue?

  public init(slot: UInt8, isActive: Bool, x: UInt16, y: UInt16, pressure: UnipolarValue? = nil) {
    self.slot = slot
    self.isActive = isActive
    self.x = x
    self.y = y
    self.pressure = pressure
  }
}

public enum ControllerTouchSurface: String, Sendable, Codable {
  case primary
  case left
  case right
}

/// A complete contact frame of one surface, dated with the report's receipt-anchored sensor time
/// (see `ControllerSampleTimestamp`), which can drift from `ControllerEvent.timestamp`. Frames of
/// one report keep their wire order.
public struct ControllerTouchSample: Sendable, Equatable, Codable {
  public let surface: ControllerTouchSurface
  public let timestamp: MonotonicTimestamp
  public let contacts: [ControllerTouchContact]

  public init(
    surface: ControllerTouchSurface = .primary,
    timestamp: MonotonicTimestamp,
    contacts: [ControllerTouchContact]
  ) {
    self.surface = surface
    self.timestamp = timestamp
    self.contacts = contacts
  }
}

/// A producer's raw coordinate range, declared once per surface type. `width` and `height` count
/// representable raw positions from the origin, so the far edge is `origin + span - 1`.
struct ControllerTouchGeometry {
  let originX: Int32
  let originY: Int32
  let width: UInt32
  let height: UInt32
  /// True when raw Y grows toward the top edge; normalization then flips it so top is 0.
  let rawYIncreasesUpward: Bool

  func contact(slot: UInt8, isActive: Bool, rawX: Int32, rawY: Int32) -> ControllerTouchContact {
    let y = Self.normalized(rawY, origin: originY, span: height)
    return ControllerTouchContact(
      slot: slot,
      isActive: isActive,
      x: Self.normalized(rawX, origin: originX, span: width),
      y: rawYIncreasesUpward ? UInt16.max - y : y
    )
  }

  /// Clamps the raw offset to `0...span-1`, then scales it to `0...65535`, rounding half up:
  /// `(offset * 65535 + (span - 1) / 2) / (span - 1)` in integer arithmetic.
  static func normalized(_ raw: Int32, origin: Int32, span: UInt32) -> UInt16 {
    let last = Int64(span) - 1
    guard last > 0 else { return 0 }
    let offset = min(max(Int64(raw) - Int64(origin), 0), last)
    return UInt16((offset * Int64(UInt16.max) + last / 2) / last)
  }
}
