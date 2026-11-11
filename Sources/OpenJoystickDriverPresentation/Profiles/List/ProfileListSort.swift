import Foundation
import OpenJoystickDriverKit

/// The order of the profile list.
enum ProfileListSort: String, CaseIterable, Identifiable {
  /// By name.
  case name
  /// By controller model, then by name.
  case controller
  /// By the time of the last activation, the newest first; a profile never activated comes last.
  case lastUsed

  var id: String { rawValue }

  /// The localization key of the picker option.
  var titleKey: String {
    switch self {
    case .name: return "ui.profiles.sort.name"
    case .controller: return "ui.profiles.sort.controller"
    case .lastUsed: return "ui.profiles.sort.lastUsed"
    }
  }

  /// The last activation of each profile in `snapshot`.
  static func lastUsed(in snapshot: ApplicationServiceRemappingSnapshotPayload?) -> [UUID: Double] {
    Dictionary(
      (snapshot?.lastUsed ?? []).map { ($0.profileID, $0.usedAt) },
      uniquingKeysWith: max
    )
  }

  /// `profiles` in this order; `lastUsed` holds the seconds since 1970 of each activated profile.
  func sorted(_ profiles: [RemappingProfile], lastUsed: [UUID: Double]) -> [RemappingProfile] {
    profiles.sorted { lhs, rhs in
      switch self {
      case .name: break
      case .controller:
        let left = (lhs.device.vendorID, lhs.device.productID)
        let right = (rhs.device.vendorID, rhs.device.productID)
        if left != right { return left < right }
      case .lastUsed:
        let left = lastUsed[lhs.id]
        let right = lastUsed[rhs.id]
        if left != right {
          guard let left else { return false }
          guard let right else { return true }
          return left > right
        }
      }
      let order = lhs.name.localizedStandardCompare(rhs.name)
      return order == .orderedSame
        ? lhs.id.uuidString < rhs.id.uuidString : order == .orderedAscending
    }
  }
}
