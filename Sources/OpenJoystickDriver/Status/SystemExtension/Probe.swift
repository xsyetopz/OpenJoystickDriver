import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB

enum ExtensionBundleState: Sendable, Equatable {
  case present
  case missing
  case invalid(String)
}

enum ExtensionProbe {
  static let bundleIdentifier = USBDriverKitExtensionConfiguration.bundleIdentifier
  static let relativePath =
    "Contents/Library/SystemExtensions/com.openjoystickdriver.XboxUSBDevice.dext"

  static func currentStatus(bundleURL: URL = Bundle.main.bundleURL) -> ExtensionStatus {
    let bundle = bundleState(in: bundleURL)
    let embedded = embeddedFacts(in: bundleURL)
    do {
      let result = try BoundedProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/usr/bin/systemextensionsctl"),
        arguments: ["list"],
        timeoutSeconds: 5,
        maximumOutputBytes: 262_144
      )
      return ExtensionStatus(
        bundle: bundle,
        registration: registration(from: result),
        embedded: embedded,
        installed: installedFacts(from: result.output)
      )
    } catch {
      return ExtensionStatus(
        bundle: bundle,
        registration: .unavailable("systemextensionsctl failed: \(error.localizedDescription)"),
        embedded: embedded,
        installed: nil
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

  static func installedFacts(from output: String) -> ExtensionVersionFacts? {
    guard let line = output.components(separatedBy: .newlines).first(where: {
      $0.contains(bundleIdentifier)
    }) else { return nil }
    let versionToken = line.split { $0 == " " || $0 == "\t" }.first { token in
      token.contains("/") && token.first == "("
    }
    guard let versionToken else { return nil }
    let parts = String(versionToken)
      .trimmingCharacters(in: CharacterSet(charactersIn: "()[],"))
      .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    let short = String(parts[0])
    let build = String(parts[1])
    guard isVersionComponent(short), isVersionComponent(build) else { return nil }
    return ExtensionVersionFacts(
      bundleIdentifier: bundleIdentifier,
      shortVersion: short,
      buildVersion: build
    )
  }

  private static func isVersionComponent(_ value: String) -> Bool {
    if !value.isEmpty && value.allSatisfy({ $0.isNumber }) { return true }
    let pattern = value.contains("-")
      ? "[0-9]+\\.[0-9]+\\.[0-9]+-(?:alpha|beta|rc)\\.[1-9][0-9]*"
      : "[0-9]+\\.[0-9]+\\.[0-9]+(?:(?:d|a|b|fc)[1-9][0-9]*)?"
    guard let expression = try? NSRegularExpression(pattern: "^\(pattern)$") else {
      return false
    }
    let range = NSRange(location: 0, length: value.utf16.count)
    return expression.firstMatch(in: value, range: range)?.range == range
  }

  static func embeddedFacts(in bundleURL: URL) -> ExtensionVersionFacts? {
    let url = bundleURL.appendingPathComponent(relativePath)
    guard let info = Bundle(url: url)?.infoDictionary,
      let identifier = info["CFBundleIdentifier"] as? String,
      let short = info["CFBundleShortVersionString"] as? String,
      let build = info["CFBundleVersion"] as? String
    else { return nil }
    return ExtensionVersionFacts(
      bundleIdentifier: identifier,
      shortVersion: short,
      buildVersion: build
    )
  }
}

struct ExtensionVersionFacts: Sendable, Equatable {
  let bundleIdentifier: String
  let shortVersion: String
  let buildVersion: String
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
  let embedded: ExtensionVersionFacts?
  let installed: ExtensionVersionFacts?

  init(
    bundle: ExtensionBundleState,
    registration: ExtensionRegistrationState,
    embedded: ExtensionVersionFacts? = nil,
    installed: ExtensionVersionFacts? = nil
  ) {
    self.bundle = bundle
    self.registration = registration
    self.embedded = embedded
    self.installed = installed
  }

  static let unavailable = Self(
    bundle: .missing,
    registration: .unavailable("System-extension status has not been checked.")
  )
}
