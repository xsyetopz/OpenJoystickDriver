import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct SystemSettingsPlaceTests {
  private func version(_ major: Int) -> OperatingSystemVersion {
    OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0)
  }

  @Test(arguments: [
    (SystemSettingsPlace.loginItems, 14, "loginItems"),
    (.loginItems, 15, "loginItemsAndExtensions"),
    (.accessibility, 26, "accessibility"),
    (.accessibility, 27, "deviceControl"),
    (.driverApproval, 14, "securityApproval"),
    (.driverApproval, 15, "driverExtensions"),
    (.inputMonitoring, 13, "inputMonitoring"),
    (.inputMonitoring, 27, "inputMonitoring"),
  ])
  func keyMatchesTheMacOSRelease(place: SystemSettingsPlace, major: Int, name: String) {
    #expect(
      place.localizationKey(on: version(major)) == "platform.macos.term.settingsPlace.\(name)"
    )
  }

  @Test
  func everyKeyIsInTheCatalog() {
    let localization = Localization()
    for place in SystemSettingsPlace.allCases {
      for major in [13, 14, 15, 26, 27] {
        let key = place.localizationKey(on: version(major))
        #expect(localization.string(key) != key)
      }
    }
  }
}
