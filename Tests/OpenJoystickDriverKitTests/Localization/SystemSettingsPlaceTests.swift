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
    (13, "systemSettingsMacOS13"),
    (15, "systemSettingsMacOS13"),
    (26, "systemSettingsMacOS26"),
    (27, "systemSettings"),
  ])
  func appKeyMatchesTheMacOSRelease(major: Int, name: String) {
    #expect(
      SystemSettingsPlace.appLocalizationKey(on: version(major))
        == "platform.macos.term.settingsApp.\(name)"
    )
  }

  @Test(arguments: [
    (SystemSettingsMessage.openSettings, 13, "openSystemSettingsMacOS13"),
    (.openSettings, 15, "openSystemSettingsMacOS13"),
    (.openSettings, 26, "openSystemSettingsMacOS26"),
    (.openSettings, 27, "openSystemSettings"),
    (.startAtLoginApproval, 13, "startAtLoginApprovalRequiredMacOS13"),
  ])
  func messageKeyMatchesTheMacOSRelease(
    message: SystemSettingsMessage,
    major: Int,
    name: String
  ) {
    #expect(message.localizationKey(on: version(major)).hasSuffix(".\(name)"))
  }

  @Test
  func everyKeyIsInTheCatalog() {
    let localization = Localization()
    for major in [13, 14, 15, 26, 27] {
      for place in SystemSettingsPlace.allCases {
        let key = place.localizationKey(on: version(major))
        #expect(localization.string(key) != key)
      }
      for message in SystemSettingsMessage.allCases {
        let key = message.localizationKey(on: version(major))
        #expect(localization.string(key) != key)
      }
      let key = SystemSettingsPlace.appLocalizationKey(on: version(major))
      #expect(localization.string(key) != key)
    }
  }

  @Test(arguments: [
    ("hi-IN", 15, "सिस्टम सेटिंग्ज़ खोलें"),
    ("hi-IN", 26, "सिस्टम सेटिंग खोलें"),
    ("pt-BR", 26, "Abrir Ajustes do Sistema"),
    ("pt-BR", 27, "Abrir Ajustes"),
  ])
  func appNameIsSpelledAsTheReleaseShows(language: String, major: Int, expected: String) {
    let localization = Localization(preferredLanguages: [language])
    #expect(
      localization.string(SystemSettingsMessage.openSettings.localizationKey(on: version(major)))
        == expected
    )
  }
}
