import AppKit
import CoreServices
import Foundation
import OpenJoystickDriverKit

struct PermissionsCommand {
  func run(arguments: [String]) {
    guard arguments.first == "request-daemon" else {
      print("Usage: OpenJoystickDriver --headless permissions request-daemon")
      return
    }

    requireApplicationsBundleOrExit()
    requireValidBundleSignatureOrExit(action: "Request permissions")

    let mainBundleURL = Bundle.main.bundleURL
    let daemonAppURL = DaemonManager.bundledDaemonApplicationURL(in: mainBundleURL)
    let executableURL = DaemonManager.daemonExecutableURL(forMainBundleURL: mainBundleURL)
    guard FileManager.default.fileExists(atPath: executableURL.path) else {
      print("ERROR: could not find OpenJoystickDriverDaemon inside the app bundle.")
      exit(1)
    }

    let registrationStatus = LSRegisterURL(daemonAppURL as CFURL, true)
    if registrationStatus != noErr {
      print(
        "WARNING: LaunchServices registration failed for OpenJoystickDriverDaemon: "
          + "\(registrationStatus)"
      )
    }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["--request-input-monitoring"]
    process.environment = ProcessInfo.processInfo.environment.merging(
      ["OJD_PERMISSION_PROMPT_ONLY": "1"]
    ) { _, new in new }
    process.standardOutput = Pipe()
    process.standardError = Pipe()

    do {
      try process.run()
    } catch {
      print("ERROR: failed to start OpenJoystickDriverDaemon permission helper: \(error)")
      exit(1)
    }

    openPrivacyPane("Privacy_ListenEvent")
    openPrivacyPane("Privacy_Accessibility")
    print("Requested permissions for OpenJoystickDriverDaemon.")
    print("Enable OpenJoystickDriverDaemon in Input Monitoring and Accessibility.")
  }

  private func openPrivacyPane(_ pane: String) {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    if let url, NSWorkspace.shared.open(url) { return }
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }
}
