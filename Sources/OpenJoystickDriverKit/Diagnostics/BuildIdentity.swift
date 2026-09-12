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

  public static func current(bundle: Bundle = .main) -> Self {
    let info = bundle.infoDictionary ?? [:]
    return Self(
      semanticVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
      appBundleVersion: info["CFBundleVersion"] as? String ?? "unknown",
      sourceCommit: info["OJDSourceCommit"] as? String ?? "unknown",
      sourceState: (info["OJDSourceState"] as? String).flatMap(SourceState.init) ?? .unknown
    )
  }

  public var display: String {
    let shortCommit = sourceCommit.count == 40 ? String(sourceCommit.prefix(12)) : sourceCommit
    let dirtySuffix = sourceState == .dirty ? "-dirty" : ""
    return "\(semanticVersion) (build \(appBundleVersion), \(shortCommit)\(dirtySuffix))"
  }

  private enum CodingKeys: String, CodingKey {
    case semanticVersion = "semantic_version"
    case appBundleVersion = "app_bundle_version"
    case sourceCommit = "source_commit"
    case sourceState = "source_state"
  }
}
