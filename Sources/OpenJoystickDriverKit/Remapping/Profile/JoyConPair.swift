import Foundation

/// Selects the motion source for an explicitly paired left/right Joy-Con session.
public enum RemappingJoyConGyroSelection: String, Codable, CaseIterable, Sendable {
  case disabled
  case left
  case right
}

/// Profile behavior used only after two exact runtime Joy-Con identities are paired.
public struct RemappingJoyConPairSettings: Codable, Equatable, Sendable {
  public let gyroSelection: RemappingJoyConGyroSelection

  public init(gyroSelection: RemappingJoyConGyroSelection = .right) {
    self.gyroSelection = gyroSelection
  }

  private enum CodingKeys: String, CodingKey { case gyroSelection = "gyro_selection" }
}
