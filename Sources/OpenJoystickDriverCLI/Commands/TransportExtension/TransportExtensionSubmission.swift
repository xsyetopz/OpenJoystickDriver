import Foundation
import OpenJoystickDriverKit

/// Submits DriverKit system-extension activation and deactivation requests to macOS.
enum TransportExtensionSubmission {
  /// The request to submit.
  enum Action: Sendable {
    /// Activate the extension.
    case activate
    /// Deactivate the extension.
    case deactivate
  }

  /// Submits `action` and returns macOS's answer; tests replace it to avoid the system.
  ///
  /// The default first checks that this `ojd` runs from the signed, installed app, because macOS
  /// accepts requests only from that bundle.
  @TaskLocal
  static var submit: @Sendable (Action) async throws -> SystemExtensionSetupRequestResult = {
    action in
    try requireInstalledBundle()
    try requireValidSignature()
    let client = PlatformHosts.current
    switch action {
    case .activate:
      try requireEmbeddedExtension()
      return await client.requestExtensionActivation()
    case .deactivate: return await client.requestExtensionDeactivation()
    }
  }

  /// Checks that the app bundle that contains this executable is the installed app.
  ///
  /// - Throws: ``CLIFailure`` with `installationProblem` when it is not.
  private static func requireInstalledBundle() throws {
    let bundle = ServiceStartCommand.applicationBundleURL() ?? Bundle.main.bundleURL
    guard BuildIdentity.isInstalled(bundle) else {
      throw CLIFailure(
        .installationProblem,
        CLILocalized.format(
          "cli.transportExtension.group.notInstalled",
          bundle.path
        )
      )
    }
  }

  /// Checks that the app bundle contains the extension.
  ///
  /// - Throws: ``CLIFailure`` with `installationProblem` when the extension is missing.
  private static func requireEmbeddedExtension() throws {
    let bundle = ServiceStartCommand.applicationBundleURL() ?? Bundle.main.bundleURL
    let dext = bundle.appendingPathComponent(
      "Contents/Library/SystemExtensions/\(PlatformHosts.current.extensionID).dext"
    )
    guard FileManager.default.fileExists(atPath: dext.path) else {
      throw CLIFailure(
        .installationProblem,
        CLILocalized.format(
          "cli.transportExtension.group.bundleMissing",
          PlatformHosts.current.extensionID
        )
      )
    }
  }

  /// Checks that the code signature of the app bundle is valid.
  ///
  /// A dext copied into the bundle after signing breaks the signature, and macOS then rejects the
  /// request with an unhelpful error.
  ///
  /// - Throws: ``CLIFailure`` with `installationProblem` when the signature is invalid or
  ///   `codesign` cannot run.
  private static func requireValidSignature() throws {
    let bundle = ServiceStartCommand.applicationBundleURL() ?? Bundle.main.bundleURL
    let problem: String?
    do {
      problem = try BuildIdentity.signatureProblem(of: bundle)
    } catch {
      throw CLIFailure(
        .installationProblem,
        CLILocalized.format(
          "platform.macos.cli.transportExtension.group.codesignFailedToRun",
          error.localizedDescription
        )
      )
    }
    if let problem {
      throw CLIFailure(
        .installationProblem,
        CLILocalized.format("cli.transportExtension.group.signatureInvalid", problem)
      )
    }
  }
}
