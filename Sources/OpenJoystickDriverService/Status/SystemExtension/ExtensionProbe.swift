package import Foundation
package import OpenJoystickDriverKit
import OpenJoystickDriverUSB

/// Reads the state of the transport extension from the app bundle and from `systemextensionsctl`.
package enum ExtensionProbe {
  /// The bundle identifier of the transport extension.
  package static let extensionID = USBDriverKitExtensionConfiguration.extensionID
  /// The path of the extension inside an app bundle.
  static let relativePath = "Contents/Library/SystemExtensions/\(extensionID).dext"

  /// Returns the bundle state, the registration, and the embedded and installed versions of the
  /// extension.
  ///
  /// A failure of `systemextensionsctl` makes the registration unavailable.
  package static func currentStatus(bundleURL: URL = Bundle.main.bundleURL) -> ExtensionStatus {
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
        installed: installedFacts(from: result.output),
        replacedVersionPending: replacedVersionPending(in: result.output)
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

  /// Returns whether the extension is missing from `bundleURL`, present, or has another identifier.
  static func bundleState(in bundleURL: URL) -> ExtensionBundleState {
    let extensionURL = bundleURL.appendingPathComponent(relativePath)
    guard FileManager.default.fileExists(atPath: extensionURL.path) else { return .missing }
    let actualIdentifier = Bundle(url: extensionURL)?.bundleIdentifier
    guard actualIdentifier == extensionID else {
      return .invalid(actualIdentifier ?? "missing bundle identifier")
    }
    return .present
  }

  /// Returns the registration that the output of `systemextensionsctl list` shows.
  ///
  /// A matching line with "activated enabled" is active, any other matching line is inactive, and
  /// no match is absent. A timeout, a failed exit or a truncated output without a match is
  /// unavailable.
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
      line.contains(extensionID)
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

  /// Returns the version that the extension's "activated enabled" line of `output` shows, else its
  /// first line, or nil when the line has none.
  ///
  /// After an upgrade macOS keeps listing the replaced version as "terminated waiting to uninstall
  /// on reboot", often above the active one, so the first line alone can name a stale version.
  static func installedFacts(from output: String) -> ExtensionVersionFacts? {
    let lines = output.components(separatedBy: .newlines).filter { $0.contains(extensionID) }
    let active = lines.first { $0.localizedCaseInsensitiveContains("activated enabled") }
    guard let line = active ?? lines.first else { return nil }
    let versionToken = line.split { $0 == " " || $0 == "\t" }.first { token in
      token.contains("/") && token.first == "("
    }
    guard let versionToken else { return nil }
    let parts = String(versionToken).trimmingCharacters(in: CharacterSet(charactersIn: "()[],"))
      .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    let short = String(parts[0])
    let build = String(parts[1])
    guard isVersionComponent(short), isVersionComponent(build) else { return nil }
    return ExtensionVersionFacts(
      extensionID: extensionID,
      shortVersion: short,
      buildVersion: build
    )
  }

  /// Returns whether `output` lists a version of the extension that waits to uninstall on reboot.
  ///
  /// macOS keeps a replaced driver for a connected device until the device reconnects or the Mac
  /// restarts, and the SIP-protected store cannot be cleared sooner.
  static func replacedVersionPending(in output: String) -> Bool {
    output.components(separatedBy: .newlines).contains { line in
      line.contains(extensionID) && line.localizedCaseInsensitiveContains("waiting to uninstall")
    }
  }

  /// Accepts a SemVer short version or a kext-grammar build version.
  private static func isVersionComponent(_ value: String) -> Bool {
    if value.first?.isNumber == true, SemanticVersion(value) != nil { return true }
    let pattern = "[0-9]+(?:\\.[0-9]+){0,2}(?:(?:d|a|b|fc)[1-9][0-9]*)?"
    guard let expression = try? NSRegularExpression(pattern: "^\(pattern)$") else { return false }
    let range = NSRange(location: 0, length: value.utf16.count)
    return expression.firstMatch(in: value, range: range)?.range == range
  }

  /// Returns the identifier and versions in the embedded extension's `Info.plist`, or nil when one
  /// is missing.
  static func embeddedFacts(in bundleURL: URL) -> ExtensionVersionFacts? {
    let url = bundleURL.appendingPathComponent(relativePath)
    guard let info = Bundle(url: url)?.infoDictionary,
      let identifier = info["CFBundleIdentifier"] as? String,
      let short = info["CFBundleShortVersionString"] as? String,
      let build = info["CFBundleVersion"] as? String
    else { return nil }
    return ExtensionVersionFacts(
      extensionID: identifier,
      shortVersion: short,
      buildVersion: build
    )
  }
}
