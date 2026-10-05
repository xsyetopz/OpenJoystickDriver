import Foundation

public struct BuildIdentity: Codable, Equatable, Sendable {
  public enum SourceState: String, Codable, Sendable {
    case clean
    case dirty
    case unknown
  }

  public let semanticVersion: String
  public let appBundleVersion: String
  public let sourceCommit: String
  public let sourceState: SourceState

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
    return Self(
      semanticVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
      appBundleVersion: info["CFBundleVersion"] as? String ?? "unknown",
      sourceCommit: info["OJDSourceCommit"] as? String ?? "unknown",
      sourceState: (info["OJDSourceState"] as? String).flatMap(SourceState.init) ?? .unknown
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

  /// The release version with SemVer build metadata for provenance, such as
  /// `0.5.0+build.1.4.89.sha.0123456789ab.dirty`. Metadata never orders versions.
  public var display: String {
    let shortCommit = sourceCommit.count == 40 ? String(sourceCommit.prefix(12)) : sourceCommit
    var metadata = ["build", appBundleVersion, "sha", shortCommit]
    if sourceState == .dirty { metadata.append("dirty") }
    return "\(semanticVersion)+\(metadata.joined(separator: "."))"
  }

  private enum CodingKeys: String, CodingKey {
    case semanticVersion
    case appBundleVersion
    case sourceCommit
    case sourceState
  }
}
