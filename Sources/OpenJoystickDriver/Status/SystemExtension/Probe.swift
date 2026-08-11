import Foundation
import OpenJoystickDriverKit

enum ExtensionBundleState: Sendable, Equatable {
  case present
  case missing
  case invalid(String)
}

enum ExtensionProbe {
  static let bundleIdentifier = "com.openjoystickdriver.VirtualHIDDevice"
  static let relativePath =
    "Contents/Library/SystemExtensions/com.openjoystickdriver.VirtualHIDDevice.dext"

  static func currentStatus(bundleURL: URL = Bundle.main.bundleURL) -> ExtensionStatus {
    let bundle = bundleState(in: bundleURL)
    do {
      let result = try BoundedProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/usr/bin/systemextensionsctl"),
        arguments: ["list"],
        timeoutSeconds: 5,
        maximumOutputBytes: 262_144
      )
      return ExtensionStatus(bundle: bundle, registration: registration(from: result))
    } catch {
      return ExtensionStatus(
        bundle: bundle,
        registration: .unavailable("systemextensionsctl failed: \(error.localizedDescription)")
      )
    }
  }

  static func bundleState(in bundleURL: URL) -> ExtensionBundleState {
    let extensionURL = bundleURL.appendingPathComponent(relativePath)
    guard FileManager.default.fileExists(atPath: extensionURL.path) else { return .missing }
    let actualIdentifier = Bundle(url: extensionURL)?.bundleIdentifier
    guard actualIdentifier == bundleIdentifier else {
      return .invalid(actualIdentifier ?? "missing bundle identifier")
    }
    return .present
  }

  static func registration(from result: BoundedProcessResult) -> ExtensionRegistrationState {
    if result.timedOut { return .unavailable("systemextensionsctl timed out after 5 seconds.") }
    guard result.terminationStatus == 0 else {
      let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
      return .unavailable(
        detail.isEmpty
          ? "systemextensionsctl exited with status \(result.terminationStatus)." : detail
      )
    }

    let matches = result.output.split(separator: "\n").filter { line in
      line.contains(bundleIdentifier)
    }
    if let active = matches.first(where: { line in
      line.localizedCaseInsensitiveContains("activated enabled")
    }) {
      return .active(String(active))
    }
    if !matches.isEmpty { return .inactive(matches.map(String.init).joined(separator: "\n")) }
    if result.outputWasTruncated {
      return .unavailable("systemextensionsctl output was truncated before a match was found.")
    }
    return .absent
  }
}

enum ExtensionRegistrationState: Sendable, Equatable {
  case active(String)
  case inactive(String)
  case absent
  case unavailable(String)
}

struct ExtensionStatus: Sendable, Equatable {
  let bundle: ExtensionBundleState
  let registration: ExtensionRegistrationState

  static let unavailable = Self(
    bundle: .missing,
    registration: .unavailable("System-extension status has not been checked.")
  )
}
