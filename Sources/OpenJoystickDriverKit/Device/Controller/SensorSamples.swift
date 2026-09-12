/// Signed sensor readings before controller-specific factory calibration.
public struct ControllerRawSensorVector: Sendable, Equatable, Codable {
  public let x: Int16
  public let y: Int16
  public let z: Int16

  public init(x: Int16, y: Int16, z: Int16) {
    self.x = x
    self.y = y
    self.z = z
  }
}

public enum ControllerSampleTimeBasis: String, Sendable, Codable {
  case deviceCounter
  case hostEstimate
}

/// Time relative to the first sample in this parser session, never absolute host uptime.
/// Device counters carry rational tick units; host estimates leave those units absent.
public struct ControllerSampleTimestamp: Sendable, Equatable, Codable {
  public let basis: ControllerSampleTimeBasis
  public let rawCounter: UInt32
  public let elapsedNanoseconds: UInt64
  public let tickNanosecondsNumerator: UInt32?
  public let tickNanosecondsDenominator: UInt32?
  public let sequenceIndex: UInt64

  public init(
    rawCounter: UInt32,
    elapsedNanoseconds: UInt64,
    tickNanosecondsNumerator: UInt32?,
    tickNanosecondsDenominator: UInt32?,
    sequenceIndex: UInt64,
    basis: ControllerSampleTimeBasis = .deviceCounter
  ) {
    self.basis = basis
    self.rawCounter = rawCounter
    self.elapsedNanoseconds = elapsedNanoseconds
    self.tickNanosecondsNumerator = tickNanosecondsNumerator
    self.tickNanosecondsDenominator = tickNanosecondsDenominator
    self.sequenceIndex = sequenceIndex
  }
}

/// Retains raw ADC vectors together with any available physical-unit conversion.
public struct ControllerMotionSample: Sendable, Equatable, Codable {
  public let timestamp: ControllerSampleTimestamp
  public let rawGyroscope: ControllerRawSensorVector
  public let rawAccelerometer: ControllerRawSensorVector
  public let physicalReading: ControllerMotionReading?

  public init(
    timestamp: ControllerSampleTimestamp,
    rawGyroscope: ControllerRawSensorVector,
    rawAccelerometer: ControllerRawSensorVector,
    physicalReading: ControllerMotionReading? = nil
  ) {
    self.timestamp = timestamp
    self.rawGyroscope = rawGyroscope
    self.rawAccelerometer = rawAccelerometer
    self.physicalReading = physicalReading
  }
}

public struct ControllerTouchContact: Sendable, Equatable, Codable {
  public let id: UInt8
  public let isActive: Bool
  public let x: Int32
  public let y: Int32

  public init(id: UInt8, isActive: Bool, x: Int32, y: Int32) {
    self.id = id
    self.isActive = isActive
    self.x = x
    self.y = y
  }
}

public enum ControllerTouchSurface: String, Sendable, Codable {
  case primary
  case left
  case right
}

/// A complete contact frame. Historical frames retain their wire order and raw touch counter.
/// The report timestamp dates the containing report, not each historical contact frame.
public struct ControllerTouchSample: Sendable, Equatable, Codable {
  public let reportTimestamp: ControllerSampleTimestamp
  public let rawTouchCounter: UInt8?
  public let historyIndex: UInt8
  public let width: UInt32
  public let height: UInt32
  public let contacts: [ControllerTouchContact]
  public let surface: ControllerTouchSurface
  /// Lower coordinate bounds; width and height count representable coordinate positions.
  public let originX: Int32
  public let originY: Int32

  public init(
    reportTimestamp: ControllerSampleTimestamp,
    rawTouchCounter: UInt8?,
    historyIndex: UInt8,
    width: UInt32,
    height: UInt32,
    contacts: [ControllerTouchContact],
    surface: ControllerTouchSurface = .primary,
    originX: Int32 = 0,
    originY: Int32 = 0
  ) {
    self.reportTimestamp = reportTimestamp
    self.rawTouchCounter = rawTouchCounter
    self.historyIndex = historyIndex
    self.width = width
    self.height = height
    self.contacts = contacts
    self.surface = surface
    self.originX = originX
    self.originY = originY
  }
}
