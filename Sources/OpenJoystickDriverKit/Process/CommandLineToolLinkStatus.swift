public import Foundation

/// What is at the path of the `ojd` command-line tool link.
///
/// This is the only place the link is classified. The app installs and removes the link and
/// `ojd status` reports it, and both read it through this type, so they agree on what it is.
public struct CommandLineToolLinkStatus: Equatable, Sendable {
  /// What the path holds.
  public enum State: String, Codable, CaseIterable, Equatable, Sendable {
    /// A link that points to this app's executable.
    case installed = "Installed"
    /// A link whose target exists but is not this app's executable, such as another app copy.
    case linkedElsewhere = "LinkedElsewhere"
    /// A link whose target does not exist.
    case broken = "Broken"
    /// A file or folder that is not a link; the app never replaces it.
    case blockedByFile = "BlockedByFile"
    /// Nothing is at the path.
    case missing = "Missing"
  }

  /// Where the app puts the link.
  public static let defaultPath = "/usr/local/bin/ojd"

  /// What the path holds.
  public let state: State
  /// The path that was read.
  public let path: String
  /// What the link points at, as stored in the link; nil when the path is not a link.
  public let target: String?

  /// Creates a status from its values.
  public init(state: State, path: String, target: String? = nil) {
    self.state = state
    self.path = path
    self.target = target
  }

  /// The executable of the running app, which the link must point to.
  public static var currentExecutable: URL {
    Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
  }

  /// Reads the path without following the link, so a dangling link is `Broken`, not `Missing`.
  ///
  /// A relative target is read from the folder that holds the link.
  public static func probe(
    path: String = defaultPath,
    executable: URL = currentExecutable
  ) -> Self {
    let manager = FileManager.default
    guard let destination = try? manager.destinationOfSymbolicLink(atPath: path) else {
      let present = (try? manager.attributesOfItem(atPath: path)) != nil
      return Self(state: present ? .blockedByFile : .missing, path: path)
    }
    let linkURL = URL(
      fileURLWithPath: destination,
      relativeTo: URL(fileURLWithPath: path).deletingLastPathComponent()
    ).resolvingSymlinksInPath()
    guard manager.fileExists(atPath: linkURL.path) else {
      return Self(state: .broken, path: path, target: destination)
    }
    let ours = linkURL.path == executable.resolvingSymlinksInPath().path
    return Self(state: ours ? .installed : .linkedElsewhere, path: path, target: destination)
  }
}
