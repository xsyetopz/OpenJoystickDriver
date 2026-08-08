import SwiftUSB

/// A physical rumble actuator that the active protocol implementation can address.
public enum PhysicalRumbleMotor: String, Codable, CaseIterable, Hashable, Sendable {
  case leftMain
  case rightMain
  case leftTrigger
  case rightTrigger
  case leftHaptic
  case rightHaptic
}

/// A physical lighting feature with a source-backed output implementation.
public enum PhysicalLightingFeature: String, Codable, CaseIterable, Hashable, Sendable {
  case playerIndicator
  case programmableColor
  case programmableBrightness
}

/// Strength of the evidence behind a physical output capability claim.
public enum PhysicalOutputEvidence: String, Codable, CaseIterable, Hashable, Sendable {
  case unavailable
  case sourceBacked
  case hardwareVerified
}

/// Generic player indicator selection for protocols with numbered controller LEDs.
public enum PhysicalPlayerIndicator: Int, Codable, CaseIterable, Hashable, Sendable {
  case off = 0
  case player1 = 1
  case player2 = 2
  case player3 = 3
  case player4 = 4
}

/// Source-backed physical output capabilities of the active controller protocol.
public struct PhysicalControllerOutputCapabilities: Codable, Equatable, Hashable, Sendable {
  public let rumbleMotors: [PhysicalRumbleMotor]
  public let lightingFeatures: [PhysicalLightingFeature]
  /// Motors whose hardware accepts only off/on rather than variable intensity.
  public let binaryRumbleMotors: [PhysicalRumbleMotor]
  public let evidence: PhysicalOutputEvidence

  public init(
    rumbleMotors: [PhysicalRumbleMotor] = [],
    lightingFeatures: [PhysicalLightingFeature] = [],
    binaryRumbleMotors: [PhysicalRumbleMotor] = [],
    evidence: PhysicalOutputEvidence? = nil
  ) {
    self.rumbleMotors = Array(Set(rumbleMotors)).sorted { $0.rawValue < $1.rawValue }
    self.lightingFeatures = Array(Set(lightingFeatures)).sorted { $0.rawValue < $1.rawValue }
    let supportedMotors = Set(self.rumbleMotors)
    self.binaryRumbleMotors = Array(Set(binaryRumbleMotors).intersection(supportedMotors)).sorted {
      $0.rawValue < $1.rawValue
    }
    let hasCapabilities = !self.rumbleMotors.isEmpty || !self.lightingFeatures.isEmpty
    self.evidence = hasCapabilities ? (evidence ?? .sourceBacked) : .unavailable
  }

  private enum CodingKeys: String, CodingKey {
    case rumbleMotors
    case lightingFeatures
    case binaryRumbleMotors
    case evidence
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let motors = try container.decode([PhysicalRumbleMotor].self, forKey: .rumbleMotors)
    let lighting = try container.decode([PhysicalLightingFeature].self, forKey: .lightingFeatures)
    let binaryMotors = try container.decode([PhysicalRumbleMotor].self, forKey: .binaryRumbleMotors)
    let decodedEvidence = try container.decode(PhysicalOutputEvidence.self, forKey: .evidence)
    self.init(
      rumbleMotors: motors,
      lightingFeatures: lighting,
      binaryRumbleMotors: binaryMotors,
      evidence: decodedEvidence
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(rumbleMotors, forKey: .rumbleMotors)
    try container.encode(lightingFeatures, forKey: .lightingFeatures)
    try container.encode(binaryRumbleMotors, forKey: .binaryRumbleMotors)
    try container.encode(evidence, forKey: .evidence)
  }

  public func withEvidence(_ evidence: PhysicalOutputEvidence) -> Self {
    Self(
      rumbleMotors: rumbleMotors,
      lightingFeatures: lightingFeatures,
      binaryRumbleMotors: binaryRumbleMotors,
      evidence: evidence
    )
  }

  public static let none = Self()
  public static let dualMainRumble = Self(rumbleMotors: [.leftMain, .rightMain])

  public var supportsRumble: Bool { !rumbleMotors.isEmpty }
  public var supportsTriggerRumble: Bool {
    rumbleMotors.contains(.leftTrigger) || rumbleMotors.contains(.rightTrigger)
  }
  public var supportsPlayerIndicator: Bool { lightingFeatures.contains(.playerIndicator) }
  public var supportsProgrammableBrightness: Bool {
    lightingFeatures.contains(.programmableBrightness)
  }
}

/// A raw HID feature-report read request sent through IOKit.
public struct PhysicalHIDFeatureReadRequest: Equatable, Sendable {
  public let reportID: UInt8
  public let length: Int

  public init(reportID: UInt8, length: Int) {
    self.reportID = reportID
    self.length = length
  }
}

/// A raw HID output report that can be sent through IOKit.
public struct PhysicalHIDOutputReport: Equatable, Sendable {
  public let reportID: UInt8
  public let bytes: [UInt8]

  public init(reportID: UInt8, bytes: [UInt8]) {
    self.reportID = reportID
    self.bytes = bytes
  }
}

/// Optional physical output support exposed by USB-backed controller protocols.
public protocol PhysicalRumbleOutput: AnyObject, Sendable {
  /// Rumble motors the protocol implementation can address.
  var physicalRumbleMotors: [PhysicalRumbleMotor] { get }

  /// True when the protocol has source-backed physical rumble output.
  var supportsPhysicalRumble: Bool { get }

  /// Sends physical rumble to the source controller.
  ///
  /// Values are 0...255. Unsupported actuator values must be ignored.
  func sendPhysicalRumble(handle: USBDeviceHandle, left: UInt8, right: UInt8, lt: UInt8, rt: UInt8)
    throws
}

extension PhysicalRumbleOutput {
  public var physicalRumbleMotors: [PhysicalRumbleMotor] { [.leftMain, .rightMain] }

  public var supportsPhysicalRumble: Bool { !physicalRumbleMotors.isEmpty }
}

/// Optional physical output support exposed by HID-backed controller protocols.
public protocol PhysicalHIDRumbleOutput: AnyObject, Sendable {
  var physicalRumbleMotors: [PhysicalRumbleMotor] { get }
  var physicalBinaryRumbleMotors: [PhysicalRumbleMotor] { get }
  var minimumPhysicalOutputIntervalNanoseconds: UInt64 { get }
  var supportsPhysicalRumble: Bool { get }

  func physicalRumbleReport(left: UInt8, right: UInt8, lt: UInt8, rt: UInt8)
    -> PhysicalHIDOutputReport
}

extension PhysicalHIDRumbleOutput {
  public var physicalRumbleMotors: [PhysicalRumbleMotor] { [.leftMain, .rightMain] }

  public var physicalBinaryRumbleMotors: [PhysicalRumbleMotor] { [] }
  public var minimumPhysicalOutputIntervalNanoseconds: UInt64 { 0 }

  public var supportsPhysicalRumble: Bool { !physicalRumbleMotors.isEmpty }
}

/// Optional feature-report haptics used by controllers without conventional rumble motors.
public protocol PhysicalHIDFeatureHapticOutput: AnyObject, Sendable {
  var physicalRumbleMotors: [PhysicalRumbleMotor] { get }

  func physicalHapticReports(left: UInt8, right: UInt8, durationMs: Int)
    -> [PhysicalHIDOutputReport]
}

/// Optional RGB lightbar support delivered through a HID output report.
public protocol PhysicalHIDColorOutput: AnyObject, Sendable {
  var physicalLightingFeatures: [PhysicalLightingFeature] { get }
  func physicalColorReport(red: UInt8, green: UInt8, blue: UInt8) -> PhysicalHIDOutputReport
}

extension PhysicalHIDColorOutput {
  public var physicalLightingFeatures: [PhysicalLightingFeature] { [.programmableColor] }
}

/// Optional scalar LED-brightness support delivered through a HID feature report.
public protocol PhysicalHIDFeatureBrightnessOutput: AnyObject, Sendable {
  var physicalLightingFeatures: [PhysicalLightingFeature] { get }
  func physicalBrightnessReport(_ brightness: UInt8) -> PhysicalHIDOutputReport
}

extension PhysicalHIDFeatureBrightnessOutput {
  public var physicalLightingFeatures: [PhysicalLightingFeature] { [.programmableBrightness] }
}

/// Optional physical player-indicator support exposed by HID-backed protocols.
public protocol PhysicalHIDPlayerIndicatorOutput: AnyObject, Sendable {
  var physicalLightingFeatures: [PhysicalLightingFeature] { get }

  func physicalPlayerIndicatorReport(_ indicator: PhysicalPlayerIndicator)
    -> PhysicalHIDOutputReport
}

extension PhysicalHIDPlayerIndicatorOutput {
  public var physicalLightingFeatures: [PhysicalLightingFeature] { [.playerIndicator] }
}

/// Optional physical player-indicator support exposed by USB-backed protocols.
public protocol PhysicalPlayerIndicatorOutput: AnyObject, Sendable {
  var physicalLightingFeatures: [PhysicalLightingFeature] { get }

  func sendPhysicalPlayerIndicator(handle: USBDeviceHandle, indicator: PhysicalPlayerIndicator)
    throws
}

extension PhysicalPlayerIndicatorOutput {
  public var physicalLightingFeatures: [PhysicalLightingFeature] { [.playerIndicator] }
}
