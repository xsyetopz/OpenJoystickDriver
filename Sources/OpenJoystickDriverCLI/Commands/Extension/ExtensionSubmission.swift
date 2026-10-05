import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService

/// Submits DriverKit system-extension activation and deactivation requests to macOS.
enum ExtensionSubmission {
  enum Action: Sendable {
    case activate
    case deactivate
  }

  /// Submits `action` and returns macOS's answer; tests replace it to avoid the system.
  ///
  /// The default first checks that this `ojd` runs from the signed, installed app, because
  /// macOS accepts requests only from that bundle.
  @TaskLocal
  static var submit: @Sendable (Action) async throws -> SystemExtensionSetupRequestResult = {
    action in
    try requireInstalledBundle()
    try requireValidSignature()
    let client = DefaultSystemExtensionSetupClient()
    switch action {
    case .activate:
      try requireEmbeddedExtension()
      return await client.requestActivation()
    case .deactivate: return await client.requestDeactivation()
    }
  }

  private static func requireInstalledBundle() throws {
    let bundle = ServiceStartCommand.applicationBundleURL() ?? Bundle.main.bundleURL
    guard bundle.path.hasPrefix("/Applications/") else {
      throw CLIFailure(
        .installationProblem,
        CLILocalized.format(
          "cli.extension.not_installed",
          bundle.path
        )
      )
    }
  }

  private static func requireEmbeddedExtension() throws {
    let bundle = ServiceStartCommand.applicationBundleURL() ?? Bundle.main.bundleURL
    let dext = bundle.appendingPathComponent(
      "Contents/Library/SystemExtensions/\(ExtensionProbe.bundleIdentifier).dext"
    )
    guard FileManager.default.fileExists(atPath: dext.path) else {
      throw CLIFailure(
        .installationProblem,
        CLILocalized.format(
          "cli.extension.bundle_missing",
          ExtensionProbe.bundleIdentifier
        )
      )
    }
  }

  /// A dext copied into the bundle after signing breaks the signature, and macOS then
  /// rejects the request with an unhelpful error.
  private static func requireValidSignature() throws {
    let bundle = ServiceStartCommand.applicationBundleURL() ?? Bundle.main.bundleURL
    let result: BoundedProcessResult
    do {
      result = try BoundedProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
        arguments: ["--verify", "--deep", "--strict", bundle.path],
        timeoutSeconds: 15,
        maximumOutputBytes: 262_144
      )
    } catch {
      throw CLIFailure(
        .installationProblem,
        CLILocalized.format(
          "cli.extension.codesign_failed_to_run",
          error.localizedDescription
        )
      )
    }
    guard result.terminationStatus == 0, !result.timedOut else {
      let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\n", with: " ")
      throw CLIFailure(
        .installationProblem,
        CLILocalized.format(
          "cli.extension.signature_invalid",
          result.timedOut ? "codesign timed out" : detail
        )
      )
    }
  }
}
