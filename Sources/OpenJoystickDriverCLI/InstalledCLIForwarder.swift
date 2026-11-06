import Darwin
import Foundation
import OpenJoystickDriverKit

/// Hands a command-line run over to the `ojd` in the installed app.
///
/// A repository build forwards to the installed app when that app is current, and fails when it is
/// older than the repository sources.
package enum InstalledCLIForwarder {
  /// Where a command-line run executes.
  enum Resolution: Equatable {
    /// This executable runs the command.
    case local
    /// The installed executable at the URL runs the command.
    case forward(URL)
    /// The installed executable at the URL is older than the repository sources, so the run fails.
    case staleInstallation(URL)
  }

  /// The `OpenJoystickDriver` executable inside the installed app bundle.
  static let installedExecutableURL = BuildIdentity.installedApplicationBundleURL
    .appendingPathComponent("Contents/MacOS/OpenJoystickDriver", isDirectory: false)

  /// Decides where a run executes.
  ///
  /// A run from an app bundle, or with `OJD_RUN_REPOSITORY_CLI` set to `1`, stays local. So does a
  /// run when the installed executable is missing or is this executable.
  ///
  /// - Parameters:
  ///   - currentExecutableURL: The executable that is running.
  ///   - mainBundleURL: The bundle of the running process.
  ///   - installedExecutableURL: The executable in the installed app.
  ///   - repositoryCLIOverride: Whether the environment forces the repository build to run.
  ///   - isExecutableFile: Tells whether a path is an executable file.
  ///   - installedCLIIsCurrent: Tells whether the installed executable is not older than the
  ///     sources.
  /// - Returns: ``Resolution/local`` to run here, ``Resolution/forward(_:)`` to run the installed
  ///   executable, or ``Resolution/staleInstallation(_:)`` when that executable is out of date.
  static func resolve(
    currentExecutableURL: URL,
    mainBundleURL: URL,
    installedExecutableURL: URL = installedExecutableURL,
    repositoryCLIOverride: Bool = ProcessInfo.processInfo.environment["OJD_RUN_REPOSITORY_CLI"]
      == "1",
    isExecutableFile: (String) -> Bool = FileManager.default.isExecutableFile(atPath:),
    installedCLIIsCurrent: (URL, URL) -> Bool = installedCLIIsCurrent(
      sourceExecutableURL:
      installedExecutableURL:
    )
  ) -> Resolution {
    guard mainBundleURL.pathExtension != "app", !repositoryCLIOverride else { return .local }
    let current = currentExecutableURL.resolvingSymlinksInPath().standardizedFileURL
    let installed = installedExecutableURL.resolvingSymlinksInPath().standardizedFileURL
    guard current != installed, isExecutableFile(installed.path) else { return .local }
    guard installedCLIIsCurrent(current, installed) else { return .staleInstallation(installed) }
    return .forward(installed)
  }

  /// Replaces this process with the installed `ojd` when `resolve` chooses to forward.
  ///
  /// It prints the failure and exits when the installed executable is older than the sources or
  /// `execv` fails.
  package static func forwardIfNeeded(
    arguments: [String],
    currentExecutableURL: URL = Bundle.main.executableURL
      ?? URL(fileURLWithPath: CommandLine.arguments[0]),
    mainBundleURL: URL = Bundle.main.bundleURL
  ) {
    let executable: URL
    switch resolve(currentExecutableURL: currentExecutableURL, mainBundleURL: mainBundleURL) {
    case .local: return
    case .forward(let target): executable = target
    case .staleInstallation: Self.exit(with: staleInstallationFailure)
    }

    let strings = ["ojd"] + arguments
    var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { string in
      string.withCString { strdup($0) }
    }
    guard pointers.allSatisfy({ $0 != nil }) else {
      release(pointers)
      Self.exit(with: allocationFailure)
    }
    pointers.append(nil)
    defer { release(pointers) }

    let result = executable.path.withCString { path in
      pointers.withUnsafeMutableBufferPointer { buffer in
        guard let baseAddress = buffer.baseAddress else { return Int32(-1) }
        return execv(path, baseAddress)
      }
    }
    guard result == -1 else { return }
    Self.exit(with: execFailure(String(cString: strerror(errno))))
  }

  /// The failure for an installed executable that is older than the repository sources.
  static var staleInstallationFailure: CLIFailure {
    CLIFailure(
      .staleInstallation,
      CLILocalized.text(
        "cli.shared.error.staleInstallation"
      )
    )
  }

  /// The failure for a memory allocation that failed while building the arguments.
  static var allocationFailure: CLIFailure {
    CLIFailure(
      .installedCLIFailed,
      CLILocalized.text(
        "cli.shared.error.forwarderAllocation"
      )
    )
  }

  /// `execv` failed with the error that `reason` describes.
  static func execFailure(_ reason: String) -> CLIFailure {
    CLIFailure(
      .installedCLIFailed,
      CLILocalized.format(
        "cli.shared.error.forwarderExec",
        reason
      )
    )
  }

  /// Prints `failure` on standard error and exits with its code.
  private static func exit(with failure: CLIFailure) -> Never {
    fputs(failure.line + "\n", stderr)
    Darwin.exit(failure.code.rawValue)
  }

  /// Frees the argument strings in `pointers`.
  private static func release(_ pointers: [UnsafeMutablePointer<CChar>?]) {
    for pointer in pointers { if let pointer { free(UnsafeMutableRawPointer(pointer)) } }
  }

  /// Tells whether the installed executable is no older than every repository file that built
  /// this executable.
  ///
  /// It is true when this executable is not in a repository.
  private static func installedCLIIsCurrent(
    sourceExecutableURL: URL,
    installedExecutableURL: URL
  ) -> Bool {
    guard let repositoryRoot = repositoryRoot(containing: sourceExecutableURL) else { return true }
    guard
      let installedDate = try? installedExecutableURL.resourceValues(forKeys: [
        .contentModificationDateKey
      ]).contentModificationDate
    else { return false }

    let packageManifest = repositoryRoot.appendingPathComponent("Package.swift")
    guard fileIsNotNewer(packageManifest, than: installedDate) else { return false }
    let sources = repositoryRoot.appendingPathComponent("Sources", isDirectory: true)
    guard
      let enumerator = FileManager.default.enumerator(
        at: sources,
        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
      )
    else { return false }
    for case let file as URL in enumerator {
      guard
        let values = try? file.resourceValues(forKeys: [
          .contentModificationDateKey, .isRegularFileKey,
        ])
      else { return false }
      if values.isRegularFile == true, let date = values.contentModificationDate,
        date > installedDate
      {
        return false
      }
    }
    return true
  }

  /// Tells whether `file` changed no later than `date`.
  private static func fileIsNotNewer(_ file: URL, than date: Date) -> Bool {
    guard
      let modificationDate = try? file.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
    else { return false }
    return modificationDate <= date
  }

  /// Returns the repository that contains `executableURL`, found by the `Package.swift` and
  /// `Sources/OpenJoystickDriver` it holds; nil when there is none.
  private static func repositoryRoot(containing executableURL: URL) -> URL? {
    var directory = executableURL.resolvingSymlinksInPath().deletingLastPathComponent()
    while directory.path != "/" {
      let packageManifest = directory.appendingPathComponent("Package.swift")
      let applicationSources = directory.appendingPathComponent("Sources/OpenJoystickDriver")
      if FileManager.default.fileExists(atPath: packageManifest.path),
        FileManager.default.fileExists(atPath: applicationSources.path)
      {
        return directory
      }
      directory.deleteLastPathComponent()
    }
    return nil
  }
}
