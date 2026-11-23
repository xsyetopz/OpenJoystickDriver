public import Foundation

/// The key a launch setting is stored under.
///
/// A program inside an `.app` bundle is keyed by the bundle identifier of the nearest enclosing
/// `.app`, so choosing the `.app` and launching the executable inside it (what Steam's `%command%`
/// expands to) reach the same setting. Any other program is keyed by its absolute path with
/// symbolic links resolved.
public enum LaunchSettingKey {
  /// The key for `executable`.
  public static func key(forExecutable executable: URL) -> String {
    let resolved = executable.resolvingSymlinksInPath()
    if let bundle = enclosingBundle(of: resolved), let identifier = bundle.bundleIdentifier,
      !identifier.isEmpty
    {
      return identifier
    }
    return resolved.path
  }

  /// The key for the program `name`: an `.app` path, an executable path, or a name found in
  /// `searchPath`, a `PATH` value.
  ///
  /// - Throws: ``ProgramExecutable/Failure`` when `name` has no executable.
  public static func key(for name: String, searchPath: String?) throws -> String {
    key(forExecutable: try ProgramExecutable.url(for: name, searchPath: searchPath))
  }

  /// The bundle of the nearest `.app` directory above `url`.
  private static func enclosingBundle(of url: URL) -> Bundle? {
    var directory = url.deletingLastPathComponent()
    while directory.pathComponents.count > 1 {
      if directory.pathExtension == "app" { return Bundle(url: directory) }
      directory = directory.deletingLastPathComponent()
    }
    return nil
  }
}
