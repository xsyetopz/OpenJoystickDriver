import Foundation

/// A `DataDirectory` that places every location under one caller-chosen root.
///
/// Tests and embedders use it to keep stores inside a directory they own.
public struct RootedDataDirectory: DataDirectory {
  /// The folder that holds every location.
  public let root: URL

  /// Creates a data directory under `root`.
  public init(root: URL) { self.root = root }

  /// The folder of `location` under the root.
  public func url(for location: DataLocation) -> URL {
    root.appendingPathComponent(location.rawValue, isDirectory: true)
  }
}
