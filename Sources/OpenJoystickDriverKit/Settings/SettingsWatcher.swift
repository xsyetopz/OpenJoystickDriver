import Foundation

/// Calls a handler when something in the folder of the user settings file changes.
///
/// The store writes atomically by replacing the file, which a watch of the file itself would
/// miss, so this watches the folder. The handler can also run for a change to another file in the
/// folder, such as the lock file; it should reload the settings and compare.
public final class SettingsWatcher: @unchecked Sendable {
  /// The event source that watches the settings folder.
  private let source: any DispatchSourceFileSystemObject

  /// Starts watching, creating the folder when it is missing.
  ///
  /// Returns nil when the folder cannot be created or opened; the caller then has no live
  /// refresh.
  @preconcurrency
  public init?(
    store: SettingsStore,
    queue: DispatchQueue = .main,
    onChange: @escaping @Sendable () -> Void
  ) {
    let folder = store.folderURL
    try? FileManager.default.createDirectory(
      at: folder,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let descriptor = open(folder.path, O_EVTONLY | O_CLOEXEC)
    guard descriptor >= 0 else { return nil }
    source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .rename, .delete],
      queue: queue
    )
    source.setEventHandler(handler: onChange)
    source.setCancelHandler { close(descriptor) }
    source.resume()
  }

  deinit { source.cancel() }
}
