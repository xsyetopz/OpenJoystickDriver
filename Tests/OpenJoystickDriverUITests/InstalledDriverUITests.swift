// UI tests need XCUIApplication, which only XCTest has.
import AppKit
import XCTest

/// Drives the copy in /Applications, because only that copy activates the Xbox USB driver, and
/// the repair banner depends on what macOS lists for it.
final class InstalledDriverUITests: XCTestCase {
  private let appURL = URL(fileURLWithPath: "/Applications/OpenJoystickDriver.app")
  private let extensionID = "com.openjoystickdriver.XboxUSBDevice"

  @MainActor
  func testOffersNoRepairWhileTheEmbeddedDriverIsActive() throws {
    // Arrange
    if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.openjoystickdriver")
      .isEmpty
    {
      throw XCTSkip("Quit the running OpenJoystickDriver to run this test.")
    }
    let embedded = try XCTUnwrap(embeddedVersion(), "Install the app with just install-dev.")
    let listing = try extensionListing()
    let activeLine = "\(extensionID) (\(embedded))"
    guard
      listing.contains(where: { $0.contains(activeLine) && $0.contains("activated enabled") })
    else {
      throw XCTSkip(
        """
        macOS does not list \(activeLine) as activated enabled. Run just diagnose-driver-ui, which \
        passes the listing the test runner cannot read:
        \(listing)
        """
      )
    }
    let app = XCUIApplication(url: appURL)
    app.launchArguments += ["-AppleLanguages", "(en-US)", "-AppleLocale", "en_US"]

    // Act
    app.launch()
    defer { app.terminate() }
    // The app starts in the menu bar; a reopen, as a second launch from Finder sends, shows the
    // main window.
    let reopen = try Process.run(
      URL(fileURLWithPath: "/usr/bin/open"),
      arguments: ["-b", "com.openjoystickdriver"]
    )
    reopen.waitUntilExit()
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

    // Assert: the inspection runs at launch, so give it time to show a banner.
    let repair = app.buttons["Repair Xbox USB Driver"]
    XCTAssertFalse(
      repair.waitForExistence(timeout: 5),
      "The app offers a repair while macOS lists:\n\(listing.joined(separator: "\n"))"
    )
  }

  /// The "short/build" version of the driver inside the installed app.
  private func embeddedVersion() -> String? {
    let plist = appURL.appendingPathComponent(
      "Contents/Library/SystemExtensions/\(extensionID).dext/Info.plist"
    )
    guard let data = try? Data(contentsOf: plist),
      let info = try? PropertyListDecoder().decode(BundleVersion.self, from: data)
    else { return nil }
    return "\(info.short)/\(info.build)"
  }

  /// The two version keys of a bundle's Info.plist.
  private struct BundleVersion: Decodable {
    let short: String
    let build: String

    enum CodingKeys: String, CodingKey {
      case short = "CFBundleShortVersionString"
      case build = "CFBundleVersion"
    }
  }

  /// The lines of `systemextensionsctl list` that name the driver.
  ///
  /// In the XCTest runner the command fails with OSSystemExtensionErrorDomain error 1, so
  /// `just diagnose-driver-ui` passes the listing in `OJD_SYSEXT_LIST`.
  private func extensionListing() throws -> [String] {
    if let listing = ProcessInfo.processInfo.environment["OJD_SYSEXT_LIST"] {
      return listing.split(separator: "\n").map(String.init).filter { $0.contains(extensionID) }
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
    process.arguments = ["list"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(bytes: data, encoding: .utf8) ?? ""
    let lines = output.split(separator: "\n").map(String.init).filter { $0.contains(extensionID) }
    return lines.isEmpty ? ["exit \(process.terminationStatus): \(output)"] : lines
  }
}
