import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct HIDProfileDiscoveryTests {
  @Test func catalogIncludesSteamProfilesButExcludesRawUSBProfiles() {
    let identifiers = Set(
      ParserRegistry().hidProfileIdentifiers().map { "\($0.vendorID):\($0.productID)" }
    )

    #expect(identifiers.contains("10462:4354"))
    #expect(identifiers.contains("10462:4418"))
    #expect(identifiers.contains("1356:1476"))
    #expect(identifiers.contains("1406:8201"))
    #expect(!identifiers.contains("1133:49693"))
    #expect(!identifiers.contains("5426:2627"))
  }

}
