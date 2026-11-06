import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Apple's GameController framework binds a virtual HID device only when its personality kext lists
/// the device's IDs with `GCIOMatchVirtual` true.
///
/// GameController reads no input from the GIP reports of `SDLCompatible`, so that persona must not
/// be bound, and `GameControllerCompatible` must be.
struct GameControllerPersonalityMatchTests {
  private static let kext = URL(
    fileURLWithPath:
      "/System/Library/Extensions/AppleGameControllerPersonality.kext/Contents/Info.plist"
  )

  private static func matchesVirtual(_ profile: VirtualDeviceProfile) throws -> Bool {
    let data = try Data(contentsOf: kext)
    let plist = try #require(
      try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
    let personalities = try #require(plist["IOKitPersonalities"] as? [String: [String: Any]])
    // A personality lists one `ProductID` or several in `ProductIDArray`, as macOS 27 does.
    return personalities.values.contains {
      let single = $0["ProductID"] as? Int
      let products = ($0["ProductIDArray"] as? [Int] ?? []) + [single].compactMap(\.self)
      return $0["VendorID"] as? Int == Int(profile.vendorID)
        && products.contains(Int(profile.productID))
        && $0["GCIOMatchVirtual"] as? Bool == true
    }
  }

  @Test(arguments: [
    (VirtualHIDProfileID.sdlCompatible, false),
    (VirtualHIDProfileID.gameControllerCompatible, true),
  ])
  func gameControllerBindsOnlyThePersonaWhoseReportsItReads(
    _ profileID: VirtualHIDProfileID,
    _ bound: Bool
  ) throws {
    #expect(try Self.matchesVirtual(profileID.identity) == bound)
  }
}
