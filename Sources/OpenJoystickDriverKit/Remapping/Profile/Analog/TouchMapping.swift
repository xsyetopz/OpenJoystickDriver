import Foundation

/// A stable touch-surface identity used by profile sources and mappings.
public enum RemappingTouchSurface: String, Codable, CaseIterable, Hashable, Sendable {
  /// The only or main touch surface of a controller.
  case primary = "Primary"
  /// The left touch surface of a controller that has two.
  case left = "Left"
  /// The right touch surface of a controller that has two.
  case right = "Right"

  /// Creates the profile identity of a controller touch surface.
  public init(_ surface: ControllerTouchSurface) {
    switch surface {
    case .primary: self = .primary
    case .left: self = .left
    case .right: self = .right
    }
  }
}

/// Direction of a swipe on a touch surface.
public enum RemappingTouchSwipeDirection: String, Codable, CaseIterable, Hashable, Sendable {
  /// Toward the top of the surface.
  case up = "Up"
  /// Toward the bottom of the surface.
  case down = "Down"
  /// Toward the left of the surface.
  case left = "Left"
  /// Toward the right of the surface.
  case right = "Right"
}

/// One cell of a touch-surface grid, usable as a binding source.
public struct RemappingTouchGridSource: Codable, Equatable, Hashable, Sendable {
  /// Allowed number of columns and rows.
  public static let dimensionRange = 1...16

  /// Touch surface that the grid divides.
  public let surface: RemappingTouchSurface
  /// Number of columns in the grid.
  public let columns: Int
  /// Number of rows in the grid.
  public let rows: Int
  /// Zero-based column of this cell, counted from the left.
  public let column: Int
  /// Zero-based row of this cell, counted from the top.
  public let row: Int

  /// Creates a grid cell source.
  public init(surface: RemappingTouchSurface, columns: Int, rows: Int, column: Int, row: Int) {
    self.surface = surface
    self.columns = columns
    self.rows = rows
    self.column = column
    self.row = row
  }
}

/// A swipe on a touch surface, usable as a binding source.
///
/// It fires when the primary contact lifts.
public struct RemappingTouchSwipeSource: Codable, Equatable, Hashable, Sendable {
  /// Allowed range of ``minimumDistance``.
  public static let minimumDistanceRange = 0.01...1.0
  /// ``minimumDistance`` used when none is given.
  public static let defaultMinimumDistance = 0.2

  /// Touch surface that the swipe happens on.
  public let surface: RemappingTouchSurface
  /// Direction that the swipe must go.
  public let direction: RemappingTouchSwipeDirection
  /// Minimum travel as a fraction of the surface width or height.
  public let minimumDistance: Double

  /// Creates a swipe source.
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

/// What a ``RemappingTouchMapping`` turns touch movement into.
public enum RemappingTouchMode: String, Codable, CaseIterable, Hashable, Sendable {
  /// Touch movement moves the pointer.
  case pointer = "Pointer"
  /// Touch position drives the left stick of the virtual gamepad.
  case leftStick = "LeftStick"
  /// Touch position drives the right stick of the virtual gamepad.
  case rightStick = "RightStick"
}

/// Continuous behavior for one physical touch surface.
public struct RemappingTouchMapping: Codable, Equatable, Hashable, Identifiable, Sendable {
  /// Allowed range of ``pointerSensitivity``.
  public static let pointerSensitivityRange = 1.0...5_000.0
  /// Allowed range of ``stickRadius``.
  public static let stickRadiusRange = 0.01...1.0
  /// Allowed range of ``deadzone``.
  public static let deadzoneRange = 0.0...0.95
  /// ``pointerSensitivity`` used when none is given.
  public static let defaultPointerSensitivity = 1_000.0
  /// ``stickRadius`` used when none is given.
  public static let defaultStickRadius = 0.25
  /// ``deadzone`` used when none is given.
  public static let defaultDeadzone = 0.1

  /// Stable identity of this mapping inside its profile.
  public let id: UUID
  /// Touch surface that this mapping reads.
  public let surface: RemappingTouchSurface
  /// Whether touch moves the pointer or drives a virtual stick.
  public let mode: RemappingTouchMode
  /// Logical screen points produced by one surface-width or surface-height of travel.
  public let pointerSensitivity: Double
  /// Finger travel from the touch start, as a fraction of the surface, that gives full
  /// virtual-stick displacement.
  public let stickRadius: Double
  /// Fraction of full displacement below which the virtual stick reads as centered.
  public let deadzone: Double

  /// Creates a touch mapping.
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

  /// Profile document keys of a touch mapping.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `id`.
    case id
    /// The JSON key of `surface`.
    case surface
    /// The JSON key of `mode`.
    case mode
    /// The JSON key of `pointerSensitivity`.
    case pointerSensitivity
    /// The JSON key of `stickRadius`.
    case stickRadius
    /// The JSON key of `deadzone`.
    case deadzone
  }

  /// Decodes a touch mapping from a profile document, which must give every field.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    surface = try values.decode(RemappingTouchSurface.self, forKey: .surface)
    mode = try values.decode(RemappingTouchMode.self, forKey: .mode)
    pointerSensitivity = try values.decode(Double.self, forKey: .pointerSensitivity)
    stickRadius = try values.decode(Double.self, forKey: .stickRadius)
    deadzone = try values.decode(Double.self, forKey: .deadzone)
  }
}
