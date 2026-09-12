import Foundation

public enum RemappingGyroOutputMode: String, Codable, CaseIterable, Sendable {
  case disabled
  case mouse
  case leftStick = "left_stick"
  case rightStick = "right_stick"
}

public enum RemappingGyroActivationMode: String, Codable, CaseIterable, Sendable {
  case always
  case whileHeld = "while_held"
  case whileReleased = "while_released"
  case toggle
}

/// Converts tuned angular motion to a native output with explicit physical units.
public struct RemappingGyroOutput: Codable, Equatable, Sendable {
  public let mode: RemappingGyroOutputMode
  public let pointerPointsPerDegree: Double
  public let fullStickDegreesPerSecond: Double
  public let activationMode: RemappingGyroActivationMode
  public let activationSource: RemappingSource?
  public let consumesActivationSource: Bool
  public let trackball: RemappingGyroTrackball?
  public let virtualMotion: Bool

  public static let `default` = Self()

  public init(
    mode: RemappingGyroOutputMode = .disabled,
    pointerPointsPerDegree: Double = 1,
    fullStickDegreesPerSecond: Double = 360,
    activationMode: RemappingGyroActivationMode = .always,
    activationSource: RemappingSource? = nil,
    consumesActivationSource: Bool = true,
    trackball: RemappingGyroTrackball? = nil,
    virtualMotion: Bool = false
  ) {
    self.mode = mode
    self.pointerPointsPerDegree = pointerPointsPerDegree
    self.fullStickDegreesPerSecond = fullStickDegreesPerSecond
    self.activationMode = activationMode
    self.activationSource = activationSource
    self.consumesActivationSource = consumesActivationSource
    self.trackball = trackball
    self.virtualMotion = virtualMotion
  }

  public func validate() throws {
    try trackball?.validate()
    guard (activationMode == .always) == (activationSource == nil) else {
      throw RemappingGyroOutputError.invalidField("activation_source")
    }
    if case .axis = activationSource {
      throw RemappingGyroOutputError.invalidField("activation_source")
    }
    guard pointerPointsPerDegree.isFinite, (0...1000).contains(pointerPointsPerDegree) else {
      throw RemappingGyroOutputError.invalidField("pointer_points_per_degree")
    }
    guard fullStickDegreesPerSecond.isFinite, (1...10000).contains(fullStickDegreesPerSecond) else {
      throw RemappingGyroOutputError.invalidField("full_stick_degrees_per_second")
    }
  }

  private enum CodingKeys: String, CodingKey {
    case mode, trackball
    case virtualMotion = "virtual_motion"
    case pointerPointsPerDegree = "pointer_points_per_degree"
    case fullStickDegreesPerSecond = "full_stick_degrees_per_second"
    case activationMode = "activation_mode"
    case activationSource = "activation_source"
    case consumesActivationSource = "consumes_activation_source"
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      mode: try values.decodeIfPresent(RemappingGyroOutputMode.self, forKey: .mode) ?? .disabled,
      pointerPointsPerDegree: try values.decodeIfPresent(
        Double.self,
        forKey: .pointerPointsPerDegree
      ) ?? 1,
      fullStickDegreesPerSecond: try values.decodeIfPresent(
        Double.self,
        forKey: .fullStickDegreesPerSecond
      ) ?? 360,
      activationMode: try values.decodeIfPresent(
        RemappingGyroActivationMode.self,
        forKey: .activationMode
      ) ?? .always,
      activationSource: try values.decodeIfPresent(RemappingSource.self, forKey: .activationSource),
      consumesActivationSource: try values.decodeIfPresent(
        Bool.self,
        forKey: .consumesActivationSource
      ) ?? true,
      trackball: try values.decodeIfPresent(RemappingGyroTrackball.self, forKey: .trackball),
      virtualMotion: try values.decodeIfPresent(Bool.self, forKey: .virtualMotion) ?? false
    )
    try validate()
  }
}

public enum RemappingGyroOutputError: Error, Equatable, LocalizedError, Sendable {
  case invalidField(String)

  public var errorDescription: String? {
    switch self {
    case .invalidField(let field): "Gyro output field '\(field)' is outside its valid range."
    }
  }
}
