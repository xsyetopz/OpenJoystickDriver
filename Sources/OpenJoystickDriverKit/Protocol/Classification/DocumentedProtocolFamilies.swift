import Foundation

/// The families that description documents name and OJD does not build in.
///
/// Each owner, such as the user's folder, holds the descriptions it loaded; registering again for
/// the same owner replaces them. A family is documented while any owner holds it.
enum DocumentedProtocolFamilies {
  /// The loaded descriptions by owner.
  private static let owners = Locked<[URL: [ProtocolDescription]]>([:])

  /// Makes `descriptions` the documented families of `owner`.
  static func register(_ descriptions: [ProtocolDescription], owner: URL) {
    owners.withLock { $0[owner] = descriptions }
  }

  /// The description of the documented family `name`, or nil.
  static func description(named name: String) -> ProtocolDescription? {
    owners.withLock { owners in
      owners.values.lazy.flatMap { $0 }.first { $0.family.rawValue == name }
    }
  }

  /// Every documented description in family-name order.
  static var all: [ProtocolDescription] {
    owners.withLock { $0.values.flatMap { $0 } }.sorted { $0.family.rawValue < $1.family.rawValue }
  }
}
