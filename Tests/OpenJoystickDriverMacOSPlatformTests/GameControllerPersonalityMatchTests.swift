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
    return personalities.values.contains {
      $0["VendorID"] as? Int == Int(profile.vendorID)
        && $0["ProductID"] as? Int == Int(profile.productID)
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
