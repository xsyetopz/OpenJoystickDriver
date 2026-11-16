public import Foundation

/// The macOS `DataDirectory`: Application Support, Library/Logs, and the temp locations.
///
/// This type is the only place allowed to build platform paths.
public struct MacOSDataDirectory: DataDirectory {
  /// The name of the OJD folder inside each `~/Library` folder it uses.
  public static let directoryName = "OpenJoystickDriver"

  /// Creates the macOS data directory.
  public init() {}

  /// The folder of `location` on macOS.
  public func url(for location: DataLocation) -> URL {
    switch location {
    case .applicationData: return library("Application Support")
    case .cache: return library("Caches")
    case .logs: return library("Logs")
    case .runtime: return URL(fileURLWithPath: Self.userTemporaryPath(), isDirectory: true)
    case .sharedTemporary: return URL(fileURLWithPath: "/tmp", isDirectory: true)
    case .temporary: return FileManager.default.temporaryDirectory
    case .home: return FileManager.default.homeDirectoryForCurrentUser
    }
  }

  /// `~/Library/<folder>/OpenJoystickDriver`.
  private func library(_ folder: String) -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent(folder, isDirectory: true)
      .appendingPathComponent(Self.directoryName, isDirectory: true)
  }

  /// The per-user temporary folder, which only the user can open. `TMPDIR` does not move it, so
  /// every process of one user reaches the same folder.
  private static func userTemporaryPath() -> String {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    let length = unsafe confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
    guard length > 0,
      let directory = String(
        bytes: buffer.prefix(length - 1).map(UInt8.init(bitPattern:)),
        encoding: .utf8
      )
    else { preconditionFailure("confstr(_CS_DARWIN_USER_TEMP_DIR) gave no per-user folder") }
    return directory
  }
}
