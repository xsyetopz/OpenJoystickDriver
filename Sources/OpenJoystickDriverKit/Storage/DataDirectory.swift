public import Foundation

/// The kinds of per-user location a store can ask the platform for.
public enum DataLocation: String, CaseIterable, Sendable {
  /// Durable user data: profiles, user controller records, mods, overrides, access grants.
  case applicationData
  /// Data that can be rebuilt at any time.
  case cache
  /// Application service log files.
  case logs
  /// The private runtime directory only the user can open, which holds the endpoint socket.
  case runtime
  /// The machine-wide shared temp directory, which holds the local RPC socket.
  case sharedTemporary
  /// Scratch files that are safe to lose.
  case temporary
  /// The user's home directory, which diagnostics redact from shared text.
  case home
}

/// The single port through which every store resolves where it persists files.
///
/// Stores receive a `DataDirectory` by injection and never build platform paths themselves.
public protocol DataDirectory: Sendable {
  /// Returns the directory for `location` without creating it.
  func url(for location: DataLocation) -> URL
}

extension DataDirectory {
  /// Returns the file named `name` inside `location`.
  public func fileURL(_ name: String, in location: DataLocation) -> URL {
    url(for: location).appendingPathComponent(name, isDirectory: false)
  }
}
