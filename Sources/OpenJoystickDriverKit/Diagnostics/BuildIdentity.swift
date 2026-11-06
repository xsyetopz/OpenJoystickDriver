import Foundation

/// A build identity that the bundle's Info.plist cannot describe.
public enum BuildIdentityError: Error, Equatable {
  /// The bundle's `OJDSourceState` is not a ``BuildIdentity/SourceState``; the value is the text
  /// found.
  case invalidSourceState(String)
}

/// Which release and source tree a build comes from, as the app bundle's Info.plist records it.
public struct BuildIdentity: Codable, Equatable, Sendable {
  /// Whether the source tree of the build had uncommitted changes.
  public enum SourceState: String, Codable, Sendable {
    /// The tree matched the commit.
    case clean = "Clean"
    /// The tree had uncommitted changes.
    case dirty = "Dirty"
    /// The Info.plist records no source state, as for an executable outside an app bundle.
    case unknown = "Unknown"
  }

  /// The release version, from `CFBundleShortVersionString`; `unknown` when absent.
  public let semanticVersion: String
  /// The build number, from `CFBundleVersion`; `unknown` when absent.
  public let appBundleVersion: String
  /// The Git commit of the source tree, from `OJDSourceCommit`; `unknown` when absent.
  public let sourceCommit: String
  /// Whether the source tree matched `sourceCommit`.
  public let sourceState: SourceState

  /// Creates an identity from its values.
  public init(
    semanticVersion: String,
    appBundleVersion: String,
    sourceCommit: String,
    sourceState: SourceState
  ) {
    self.semanticVersion = semanticVersion
    self.appBundleVersion = appBundleVersion
    self.sourceCommit = sourceCommit
    self.sourceState = sourceState
  }

  /// Reads the app bundle that contains the executable. `Bundle.main` follows the path that the
  /// process ran under, so through the installed `/usr/local/bin/ojd` link it has no Info.plist.
  public static func current(executableURL: URL? = Bundle.main.executableURL) -> Self {
    let bundle = applicationBundleURL(executableURL: executableURL).flatMap(Bundle.init(url:))
    let info = (bundle ?? .main).infoDictionary ?? [:]
    do { return try Self(info: info) } catch { preconditionFailure("\(error)") }
  }

  /// The identity an Info.plist dictionary describes.
  ///
  /// A missing `OJDSourceState` is `Unknown`, as for an executable outside an app bundle; a
  /// present value must be a `SourceState`.
  package init(info: [String: Any]) throws {
    let state: SourceState
    switch info["OJDSourceState"] {
    case nil: state = .unknown
    case let name as String:
      guard let parsed = SourceState(rawValue: name) else {
        throw BuildIdentityError.invalidSourceState(name)
      }
      state = parsed
    case let other?: throw BuildIdentityError.invalidSourceState("\(other)")
    }
    self.init(
      semanticVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
      appBundleVersion: info["CFBundleVersion"] as? String ?? "unknown",
      sourceCommit: info["OJDSourceCommit"] as? String ?? "unknown",
      sourceState: state
    )
  }

  /// The app bundle that contains this executable, following an installed `ojd` link.
  package static func applicationBundleURL(executableURL: URL?) -> URL? {
    guard let executableURL else { return nil }
    let bundle = executableURL.resolvingSymlinksInPath().deletingLastPathComponent()  // MacOS
      .deletingLastPathComponent()  // Contents
      .deletingLastPathComponent()
    return bundle.pathExtension == "app" ? bundle : nil
  }

  /// Where the installer puts the app.
  package static let installedApplicationBundleURL = URL(
    fileURLWithPath: "/Applications/OpenJoystickDriver.app",
    isDirectory: true
  )

  /// Whether `bundle` runs from `/Applications`, the only place macOS accepts system-extension
  /// requests from.
  package static func isInstalled(_ bundle: URL) -> Bool {
    bundle.path.hasPrefix("/Applications/")
  }

  /// Why `codesign --verify --deep --strict` rejects `bundle`, or nil when it accepts it.
  ///
  /// Throws when `codesign` does not run.
  package static func signatureProblem(of bundle: URL) throws -> String? {
    let result = try BoundedProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
      arguments: ["--verify", "--deep", "--strict", bundle.path],
      timeoutSeconds: 15,
      maximumOutputBytes: 262_144
    )
    if result.timedOut { return "codesign timed out" }
    guard result.terminationStatus != 0 else { return nil }
    return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\n", with: " ")
  }

  /// Launches `bundle` in the background with `open -g`; returns whether `open` succeeded.
  package static func openInBackground(_ bundle: URL) throws -> Bool {
    let result = try BoundedProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/usr/bin/open"),
      arguments: ["-g", bundle.path],
      timeoutSeconds: 10,
      maximumOutputBytes: 16_384
    )
    return result.terminationStatus == 0 && !result.timedOut
  }

  /// The release version with SemVer build metadata for provenance, such as
  /// `0.5.0+build.1.4.89.sha.0123456789ab.dirty`.
  ///
  /// Metadata never orders versions.
  public var display: String {
    let shortCommit = sourceCommit.count == 40 ? String(sourceCommit.prefix(12)) : sourceCommit
    var metadata = ["build", appBundleVersion, "sha", shortCommit]
    if sourceState == .dirty { metadata.append("dirty") }
    return "\(semanticVersion)+\(metadata.joined(separator: "."))"
  }

  /// The version line of the About panel without its localized label, as `ojd --version` prints
  /// it: `display`, then the bundle version in parentheses.
  public var aboutLine: String { "\(display) (\(appBundleVersion))" }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `semanticVersion` key.
    case semanticVersion
    /// The `appBundleVersion` key.
    case appBundleVersion
    /// The `sourceCommit` key.
    case sourceCommit
    /// The `sourceState` key.
    case sourceState
  }
}
