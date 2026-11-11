import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct VirtualDeviceMessageTests {
  private static let header =
    #""apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"VirtualDevice""#

  private static func message(_ members: String, requiresMatch: Bool = false) -> String? {
    do {
      _ = try VirtualDevice.decode(
        PropertyListFixture.bytes(json: "{\(header),\(members)}"),
        source: .unnamed,
        requiresMatch: requiresMatch
      )
      return nil
    } catch {
      return ControllerRecordSet.problemDescription(
        error,
        document: "virtualDevice",
        localization: Localization(preferredLanguages: ["en-US"]),
        file: "personas.plist"
      )
    }
  }

  @Test
  func anUnknownPersonaNamesTheKnownOnes() {
    #expect(
      Self.message(#""persona":"Nope""#)
        == "personas.plist, persona: The persona must be one of SDLCompatible, Generic, "
        + "GameControllerCompatible. Fix: Set persona to one of them."
    )
  }

  @Test
  func aUserFileWithoutMatchNamesTheKeyToAdd() {
    #expect(
      Self.message(#""persona":"Generic""#, requiresMatch: true)
        == "personas.plist, match: A file in the user folder must hold match. Fix: Add match "
        + "with the vendorID and productID of the model."
    )
  }

  @Test
  func aSelectionWithALayoutNamesTheKeysToRemove() {
    #expect(
      Self.message(
        #""persona":"Generic","match":{"vendorID":1,"productID":2},"transport":"USB""#
      )
        == "personas.plist, match: A file with match selects a persona, so it cannot hold "
        + "layout, transport or worksWithDefaultSDLHints. Fix: Remove layout, transport and "
        + "worksWithDefaultSDLHints, or remove match."
    )
  }

  @Test
  func aVendorIDOutsideItsRangeNamesTheKeyAndTheLowestValue() {
    #expect(
      Self.message(#""persona":"Generic","match":{"vendorID":0,"productID":2}"#)
        == "personas.plist, match.vendorID: An ID must be 1...65535. Fix: Set match.vendorID "
        + "to 1...65535."
    )
  }

  @Test
  func anEmptyIdentityNameNamesTheKey() {
    #expect(
      Self.message(
        #""persona":"Generic","match":{"vendorID":1,"productID":2},"#
          + #""identity":{"vendorID":1,"productID":2,"version":1,"productName":"","#
          + #""manufacturer":"X"}"#
      )
        == "personas.plist, identity.productName: A persona identity needs a nonempty "
        + "productName. Fix: Give productName a nonempty string."
    )
  }
}
