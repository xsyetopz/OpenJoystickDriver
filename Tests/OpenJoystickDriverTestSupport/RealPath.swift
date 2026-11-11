public import Foundation

extension URL {
  /// The path with every symbolic link resolved, as a directory listing reports it.
  ///
  /// Unlike `resolvingSymlinksInPath()`, it keeps `/private` in `/private/var`.
  public var realPath: String {
    guard let resolved = unsafe realpath(path, nil) else { return path }
    defer { unsafe free(resolved) }
    return unsafe String(cString: resolved)
  }
}
