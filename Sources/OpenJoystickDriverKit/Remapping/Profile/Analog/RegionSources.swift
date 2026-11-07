import Foundation

/// A ring, and optionally a clockwise sector, of one stick, usable as a binding source.
///
/// Radii are fractions of the deflection after the stick dead zone. A sector runs clockwise from
/// up and may pass 0 degrees, as `from` 315 to `to` 45 does.
public struct RemappingStickRegionSource: Equatable, Hashable, Sendable {
  /// ``hysteresis`` used when none is given.
  public static let defaultHysteresis = 0.05
  /// Allowed range of ``hysteresis``.
  public static let hysteresisRange = 0.0...0.25

  /// Stick that the region reads.
  public let stick: RemappingStickSource
  /// Deflection at which the ring starts, from 0 up to ``outerRadius``.
  public let innerRadius: Double
  /// Deflection at which the ring ends, up to 1.
  public let outerRadius: Double
  /// Start of the sector in degrees clockwise from up, or `nil` for the whole circle.
  public let fromDegrees: Double?
  /// End of the sector in degrees clockwise from up, or `nil` for the whole circle.
  public let toDegrees: Double?
  /// Margin that keeps an active region active past its ring edges.
  public let hysteresis: Double

  /// Creates a stick region; call ``RemappingProfile/validate()`` for the ranges.
  public init(
    stick: RemappingStickSource,
    innerRadius: Double,
    outerRadius: Double,
    fromDegrees: Double? = nil,
    toDegrees: Double? = nil,
    hysteresis: Double = Self.defaultHysteresis
  ) {
    self.stick = stick
    self.innerRadius = innerRadius
    self.outerRadius = outerRadius
    self.fromDegrees = fromDegrees
    self.toDegrees = toDegrees
    self.hysteresis = hysteresis
  }

  /// Whether every field is finite and in range, and the sector has both ends or none.
  var isValid: Bool {
    let sector: Bool
    switch (fromDegrees, toDegrees) {
    case (nil, nil): sector = true
    case (let from?, let to?):
      sector = (0..<360).contains(from) && (0...360).contains(to) && from != to
    default: sector = false
    }
    return sector && (0..<1).contains(innerRadius) && innerRadius < outerRadius && outerRadius <= 1
      && Self.hysteresisRange.contains(hysteresis)
  }

  /// Start and length of the sector in degrees; the whole circle without one.
  private var arc: (start: Double, length: Double) {
    guard let fromDegrees, let toDegrees else { return (0, 360) }
    return (
      fromDegrees, toDegrees > fromDegrees ? toDegrees - fromDegrees : toDegrees + 360 - fromDegrees
    )
  }

  /// Whether another region of the same stick shares a deflection and an angle with this one.
  func overlaps(_ other: Self) -> Bool {
    guard stick == other.stick, innerRadius < other.outerRadius, other.innerRadius < outerRadius
    else { return false }
    let (a, b) = (arc, other.arc)
    func offset(_ from: Double, _ to: Double) -> Double {
      (to - from).truncatingRemainder(dividingBy: 360) + (to < from ? 360 : 0)
    }
    return offset(a.start, b.start) < a.length || offset(b.start, a.start) < b.length
  }

  /// Whether a calibrated stick position, with y positive down, lies in the region.
  ///
  /// An active region extends its ring by ``hysteresis`` on both edges. A ring that ends at 1
  /// includes full deflection.
  func contains(x: Double, y: Double, wasActive: Bool) -> Bool {
    let radius = hypot(x, y)
    let margin = wasActive ? hysteresis : 0
    guard radius >= innerRadius - margin,
      outerRadius >= 1 ? radius <= 1 : radius < outerRadius + margin
    else { return false }
    guard fromDegrees != nil else { return true }
    let degrees = atan2(x, -y) * 180 / .pi
    let angle = degrees < 0 ? degrees + 360 : degrees
    let (start, length) = arc
    return (angle - start + 360).truncatingRemainder(dividingBy: 360) < length
  }
}

/// A pressure band of one trigger, usable as a binding source.
public struct RemappingTriggerBandSource: Equatable, Hashable, Sendable {
  /// Trigger that the band reads.
  public let trigger: RemappingTriggerSource
  /// Pressure at which the band starts, from 0 up to ``to``.
  public let from: Double
  /// Pressure at which the band ends, up to 1.
  public let to: Double
  /// Margin that keeps an active band active past its edges.
  public let hysteresis: Double

  /// Creates a trigger band; call ``RemappingProfile/validate()`` for the ranges.
  public init(
    trigger: RemappingTriggerSource,
    from: Double,
    to: Double,
    hysteresis: Double = RemappingStickRegionSource.defaultHysteresis
  ) {
    self.trigger = trigger
    self.from = from
    self.to = to
    self.hysteresis = hysteresis
  }

  /// Whether every field is finite and in range.
  var isValid: Bool {
    (0..<1).contains(from) && from < to && to <= 1
      && RemappingStickRegionSource.hysteresisRange.contains(hysteresis)
  }

  /// Whether another band of the same trigger shares a pressure with this one.
  func overlaps(_ other: Self) -> Bool {
    trigger == other.trigger && from < other.to && other.from < to
  }

  /// Whether a trigger pressure lies in the band, with the trigger hysteresis rule on the start.
  func contains(_ value: Double, wasActive: Bool) -> Bool {
    RemappingDualStageTriggerRuntime.active(
      value: value,
      threshold: from,
      hysteresis: hysteresis,
      wasActive: wasActive
    ) && (to >= 1 || value < (wasActive ? to + hysteresis : to))
  }
}

/// A rectangle of a touch surface, usable as a binding source.
///
/// It is active while any contact lies in it.
public struct RemappingTouchAreaSource: Equatable, Hashable, Sendable {
  /// Touch surface that the rectangle is on.
  public let surface: RemappingTouchSurface
  /// Left edge as a fraction of the surface width.
  public let x: Double
  /// Top edge as a fraction of the surface height.
  public let y: Double
  /// Width as a fraction of the surface width.
  public let width: Double
  /// Height as a fraction of the surface height.
  public let height: Double

  /// Creates a touch area; call ``RemappingProfile/validate()`` for the ranges.
  public init(surface: RemappingTouchSurface, x: Double, y: Double, width: Double, height: Double) {
    self.surface = surface
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  /// Whether the rectangle is nonempty and inside the surface.
  var isValid: Bool {
    (0..<1).contains(x) && (0..<1).contains(y) && width > 0 && height > 0 && x + width <= 1
      && y + height <= 1
  }

  /// Whether a surface fraction lies in the rectangle.
  func contains(_ point: RemappingTouchPoint) -> Bool {
    point.x >= x && point.x <= x + width && point.y >= y && point.y <= y + height
  }
}
