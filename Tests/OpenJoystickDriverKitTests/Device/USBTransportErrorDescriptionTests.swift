import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Issue #22: the record probe printed "OpenJoystickDriverKit.USBTransportError error 5" because
/// the error had no `LocalizedError` description, which hid the failure behind a bare case number.
struct USBTransportErrorDescriptionTests {
  @Test
  func everyCaseDescribesItselfInWordsRatherThanACaseNumber() {
    let cases: [USBTransportError] = [
      .timeout, .disconnected, .inputOutput, .accessDenied,
      .ownedByAnotherClient(owner: nil), .notFound, .notSupported,
      .platform(code: -536_870_160, message: "Unable to copy pipe."),
    ]
    for error in cases {
      let text = error.localizedDescription
      #expect(!text.contains("USBTransportError error"), "\(error): \(text)")
    }
  }

  @Test
  func aPlatformErrorNamesItsCodeAndMessage() {
    let text = USBTransportError.platform(code: -536_870_160, message: "Unable to copy pipe.")
      .localizedDescription
    #expect(text.contains("-536870160"))
    #expect(text.contains("Unable to copy pipe."))
  }

  @Test
  func theOwnerOfAHeldInterfaceIsNamed() {
    let text = USBTransportError.ownedByAnotherClient(owner: "com.apple.AppleUserHIDDrivers")
      .localizedDescription
    #expect(text.contains("com.apple.AppleUserHIDDrivers"))
  }
}
