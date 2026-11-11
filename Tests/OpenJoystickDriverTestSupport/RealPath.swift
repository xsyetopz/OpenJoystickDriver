import Foundation

extension URL {
  /// The path with every symbolic link resolved, as a directory listing reports it.
  ///
  /// Unlike `resolvingSymlinksInPath()`, it keeps `/private` in `/private/var`.
  public var realPath: String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
  }
}
