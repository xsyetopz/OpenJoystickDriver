import Foundation

/// A stable touch-surface identity used by profile sources and mappings.
public enum RemappingTouchSurface: String, Codable, CaseIterable, Hashable, Sendable {
  case primary
  case left
  case right

  public init(_ surface: ControllerTouchSurface) {
    switch surface {
    case .primary: self = .primary
    case .left: self = .left
    case .right: self = .right
    }
  }
}

public enum RemappingTouchSwipeDirection: String, Codable, CaseIterable, Hashable, Sendable {
  case up
  case down
  case left
  case right
}

public struct RemappingTouchGridSource: Codable, Equatable, Hashable, Sendable {
  public static let dimensionRange = 1...16

  public let surface: RemappingTouchSurface
  public let columns: Int
  public let rows: Int
  public let column: Int
  public let row: Int

  public init(
    surface: RemappingTouchSurface,
    columns: Int,
    rows: Int,
    column: Int,
    row: Int
  ) {
    self.surface = surface
    self.columns = columns
    self.rows = rows
    self.column = column
    self.row = row
  }
}

public struct RemappingTouchSwipeSource: Codable, Equatable, Hashable, Sendable {
  public static let minimumDistanceRange = 0.01...1.0
  public static let defaultMinimumDistance = 0.2

  public let surface: RemappingTouchSurface
  public let direction: RemappingTouchSwipeDirection
  /// Minimum travel as a fraction of the surface width or height.
  public let minimumDistance: Double

  public init(
    surface: RemappingTouchSurface,
    direction: RemappingTouchSwipeDirection,
    minimumDistance: Double = Self.defaultMinimumDistance
  ) {
    self.surface = surface
    self.direction = direction
    self.minimumDistance = minimumDistance
  }
}

public enum RemappingTouchMode: String, Codable, CaseIterable, Hashable, Sendable {
  case pointer
  case leftStick = "left_stick"
  case rightStick = "right_stick"
}

/// Continuous behavior for one physical touch surface.
public struct RemappingTouchMapping: Codable, Equatable, Hashable, Identifiable, Sendable {
  public static let pointerSensitivityRange = 1.0...5_000.0
  public static let stickRadiusRange = 0.01...1.0
  public static let deadzoneRange = 0.0...0.95
  public static let defaultPointerSensitivity = 1_000.0
  public static let defaultStickRadius = 0.25
  public static let defaultDeadzone = 0.1

  public let id: UUID
  public let surface: RemappingTouchSurface
  public let mode: RemappingTouchMode
  /// Logical screen points produced by one surface-width or surface-height of travel.
  public let pointerSensitivity: Double
  /// Surface fraction corresponding to full virtual-stick displacement.
  public let stickRadius: Double
  public let deadzone: Double

  public init(
    id: UUID = UUID(),
    surface: RemappingTouchSurface,
    mode: RemappingTouchMode,
    pointerSensitivity: Double = Self.defaultPointerSensitivity,
    stickRadius: Double = Self.defaultStickRadius,
    deadzone: Double = Self.defaultDeadzone
  ) {
    self.id = id
    self.surface = surface
    self.mode = mode
    self.pointerSensitivity = pointerSensitivity
    self.stickRadius = stickRadius
    self.deadzone = deadzone
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case surface
    case mode
    case pointerSensitivity = "pointer_sensitivity"
    case stickRadius = "stick_radius"
    case deadzone
  }
}
