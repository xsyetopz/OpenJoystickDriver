import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct SystemSettingsPlaceTests {
  private func version(_ major: Int) -> OperatingSystemVersion {
    OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0)
  }

  @Test(arguments: [
    (SystemSettingsPlace.inputMonitoring, 12, "preferencesInputMonitoring"),
    (.accessibility, 12, "preferencesAccessibility"),
    (.driverApproval, 12, "preferencesGeneral"),
    (.loginItems, 14, "loginItems"),
    (.loginItems, 15, "loginItemsAndExtensions"),
    (.accessibility, 26, "accessibility"),
    (.accessibility, 27, "deviceControl"),
    (.driverApproval, 14, "securityApproval"),
    (.driverApproval, 15, "driverExtensions"),
    (.inputMonitoring, 13, "inputMonitoringMacOS13"),
    (.inputMonitoring, 14, "inputMonitoringMacOS14"),
    (.inputMonitoring, 15, "inputMonitoringMacOS15"),
    (.inputMonitoring, 26, "inputMonitoringMacOS15"),
    (.inputMonitoring, 27, "inputMonitoring"),
  ])
  func keyMatchesTheMacOSRelease(place: SystemSettingsPlace, major: Int, name: String) {
    #expect(
      place.localizationKey(on: version(major)) == "platform.macos.term.settingsPlace.\(name)"
    )
  }

  @Test(arguments: [
    (12, "systemPreferences"),
    (13, "systemSettings"),
    (27, "systemSettings"),
  ])
  func appKeyMatchesTheMacOSRelease(major: Int, name: String) {
    #expect(
      SystemSettingsPlace.appLocalizationKey(on: version(major))
        == "platform.macos.term.settingsApp.\(name)"
    )
  }

  @Test(arguments: [(12, "preferences"), (13, "settings"), (27, "settings")])
  func messageKeyMatchesTheSettingsApp(major: Int, expected: String) {
    #expect(
      SystemSettingsPlace.appKey(
        settings: "settings",
        preferences: "preferences",
        on: version(major)
      )
        == expected
    )
  }

  @Test
  func everyKeyIsInTheCatalog() {
    let localization = Localization()
    for place in SystemSettingsPlace.allCases {
      for major in [12, 13, 14, 15, 26, 27] {
        let key = place.localizationKey(on: version(major))
        #expect(localization.string(key) != key)
      }
    }
    for major in [12, 13] {
      let key = SystemSettingsPlace.appLocalizationKey(on: version(major))
      #expect(localization.string(key) != key)
    }
  }
}
