import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverMacOSPlatform

struct GameControllerListingTests {
  /// D16: macOS serves a pad only while GameController lists a controller for it.
  @Test(arguments: [
    (true, GameControllerListing.settling, true),
    (true, .listed, true),
    (true, .unlisted, false),
    (false, .settling, false),
    (false, .listed, false),
  ])
  func padWithNoStatedServerFollowsListing(
    supportsHIDDevice: Bool,
    listing: GameControllerListing,
    native: Bool
  ) {
    #expect(
      HIDDeviceStream.nativePassThrough(
        supportsHIDDevice: supportsHIDDevice,
        listing: listing,
        statedServer: nil
      ) == native
    )
  }

  @Test(arguments: [GameControllerListing.settling, .listed, .unlisted])
  func statedServerOverridesListing(listing: GameControllerListing) {
    #expect(
      !HIDDeviceStream.nativePassThrough(
        supportsHIDDevice: true,
        listing: listing,
        statedServer: .ojd
      )
    )
    #expect(
      HIDDeviceStream.nativePassThrough(
        supportsHIDDevice: true,
        listing: listing,
        statedServer: .system
      )
    )
  }

  @Test
  func controllerListedWhenItsVendorNameProductName() {
    let names = ["Xbox Wireless Controller"]
    let listing = { GameControllerListing(productName: $0, vendorNames: names) }
    #expect(listing("Xbox Wireless Controller") == .listed)
    #expect(listing("8BitDo Ultimate 2C Wireless") == .unlisted)
    #expect(listing(nil) == .unlisted)
  }
}
