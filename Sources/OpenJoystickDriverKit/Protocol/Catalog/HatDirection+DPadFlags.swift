extension HatDirection {
  /// The direction four D-pad flags hold; opposing directions cancel to rest.
  init(up: Bool, right: Bool, down: Bool, left: Bool) {
    self =
      switch (up && !down, right && !left, down && !up, left && !right) {
      case (true, false, false, false): .north
      case (true, true, false, false): .northEast
      case (false, true, false, false): .east
      case (false, true, true, false): .southEast
      case (false, false, true, false): .south
      case (false, false, true, true): .southWest
      case (false, false, false, true): .west
      case (true, false, false, true): .northWest
      default: .neutral
      }
  }

  /// The four D-pad flags the direction presses.
  var components: (up: Bool, right: Bool, down: Bool, left: Bool) {
    switch self {
    case .neutral: (false, false, false, false)
    case .north: (true, false, false, false)
    case .northEast: (true, true, false, false)
    case .east: (false, true, false, false)
    case .southEast: (false, true, true, false)
    case .south: (false, false, true, false)
    case .southWest: (false, false, true, true)
    case .west: (false, false, false, true)
    case .northWest: (true, false, false, true)
    }
  }

  /// The eight directions from north clockwise, indexed by an 8-way hat value.
  static let clockwiseFromNorth: [HatDirection] = [
    .north, .northEast, .east, .southEast, .south, .southWest, .west, .northWest,
  ]
}
