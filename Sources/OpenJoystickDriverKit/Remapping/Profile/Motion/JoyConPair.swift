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

  private enum CodingKeys: String, CodingKey, CaseIterable { case gyroSelection }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    gyroSelection = try values.decode(RemappingJoyConGyroSelection.self, forKey: .gyroSelection)
  }
}

/// The side of a Joy-Con half that a paired session accepts, for every Joy-Con generation.
public enum JoyConHalf: Equatable, Sendable {
  case left
  case right

  private static let nintendoVendorID: UInt16 = 0x057E
  /// Left and right product IDs of the Switch Joy-Con and the Switch 2 Joy-Con.
  private static let generations: [(left: UInt16, right: UInt16)] = [
    (0x2006, 0x2007), (0x2067, 0x2066),
  ]

  public init?(vendorID: UInt16, productID: UInt16) {
    guard vendorID == Self.nintendoVendorID else { return nil }
    if Self.generations.contains(where: { $0.left == productID }) {
      self = .left
    } else if Self.generations.contains(where: { $0.right == productID }) {
      self = .right
    } else {
      return nil
    }
  }

  /// The left and right product IDs of the generation that owns a left-half product ID.
  public static func generationProductIDs(forLeft productID: UInt16) -> [UInt16] {
    generations.first { $0.left == productID }.map { [$0.left, $0.right] } ?? []
  }
}
