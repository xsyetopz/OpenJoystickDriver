import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Apple's GameController framework binds a virtual HID device only when its personality kext lists
/// the device's IDs with `GCIOMatchVirtual` true.
///
/// GameController reads no input from the GIP reports of `SDLCompatible`, so that persona must not
/// be bound, and `GameControllerCompatible` and `InControlCompatible` must be.
///
/// The kext declares `GCIOMatchVirtual` on macOS 27. The macOS 26 kext has no such key and lists
/// `045e:0b13` as an `IOHIDEventDummyService`, so these cases run only where the key exists.
struct GameControllerPersonalityMatchTests {
  private static let kext = URL(
    fileURLWithPath:
      "/System/Library/Extensions/AppleGameControllerPersonality.kext/Contents/Info.plist"
  )

  private static func personalities() throws -> [[String: Any]] {
    let data = try Data(contentsOf: kext)
    let plist = try #require(
      try unsafe PropertyListSerialization.propertyList(from: data, options: 0, format: nil)
        as? [String: Any]
    )
    return Array(try #require(plist["IOKitPersonalities"] as? [String: [String: Any]]).values)
  }

  private static var kextDeclaresVirtualMatching: Bool {
    (try? personalities())?.contains { $0["GCIOMatchVirtual"] != nil } ?? false
  }

  private static func matchesVirtual(_ profile: VirtualDeviceProfile) throws -> Bool {
    // A personality lists one `ProductID` or several in `ProductIDArray`, as macOS 27 does.
    try personalities().contains {
      let single = $0["ProductID"] as? Int
      let products = ($0["ProductIDArray"] as? [Int] ?? []) + [single].compactMap(\.self)
      return $0["VendorID"] as? Int == Int(profile.vendorID)
        && products.contains(Int(profile.productID))
        && $0["GCIOMatchVirtual"] as? Bool == true
    }
  }

  @Test(
    .enabled(
      if: kextDeclaresVirtualMatching,
      "AppleGameControllerPersonality.kext declares GCIOMatchVirtual"
    ),
    arguments: [
      (VirtualHIDProfileID.sdlCompatible, false),
      (VirtualHIDProfileID.gameControllerCompatible, true),
      (VirtualHIDProfileID.inControlCompatible, true),
    ]
  )
  func gameControllerBindsOnlyPersonaWhoseReportsItReads(
    _ profileID: VirtualHIDProfileID,
    _ bound: Bool
  ) throws {
    #expect(try Self.matchesVirtual(profileID.identity) == bound)
  }
}
