import AppKit
import Foundation
import OpenJoystickDriverKit

private let inputMonitoringSettingsURL = URL(
  string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
)
private let accessibilitySettingsURL = URL(
  string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
)

@MainActor extension AppModel {
  func requestRequiredAccess() async {
    inputMonitoringAssist = nil
    NSApp.activate(ignoringOtherApps: true)
    let snapshot = await permissionManager.requestRequiredAccess()
    inputMonitoring = snapshot.inputMonitoring.rawValue
    accessibility = snapshot.accessibility.rawValue
    if snapshot.inputMonitoring != .granted {
      openInputMonitoringSettings()
    } else if snapshot.accessibility != .granted {
      openAccessibilitySettings()
    }
  }

  func openInputMonitoringSettings() {
    openPermissionSettings(
      inputMonitoringSettingsURL,
      assist: "Open Input Monitoring and enable OpenJoystickDriver."
    )
  }

  func openAccessibilitySettings() {
    openPermissionSettings(
      accessibilitySettingsURL,
      assist: "Open Accessibility and enable OpenJoystickDriver for the "
        + "compatibility virtual gamepad."
    )
  }

  private func openPermissionSettings(_ url: URL?, assist: String) {
    inputMonitoringAssist = assist
    if let url, NSWorkspace.shared.open(url) { return }
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }
}
