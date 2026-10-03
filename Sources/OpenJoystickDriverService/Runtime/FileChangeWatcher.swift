import Foundation

/// Calls `onChange` after files in the watched directories change.
///
/// Each directory is watched for entries being added, removed, or renamed, which covers editors
/// that save by replacing the file. Each file `watchesFile` accepts is watched as well, so a file
/// rewritten in place, such as by `echo ... > file`, also counts as a change.
@MainActor
final class FileChangeWatcher {
  private static let debounce: DispatchTimeInterval = .milliseconds(300)

  private let directories: [URL]
  private let watchesFile: (URL) -> Bool
  private let onChange: @MainActor () -> Void
  private var sources: [any DispatchSourceFileSystemObject] = []
  private var fileSources: [any DispatchSourceFileSystemObject] = []
  private var pendingChange: DispatchWorkItem?

  init(
    directories: [URL],
    watchesFile: @escaping (URL) -> Bool = { _ in true },
    onChange: @escaping @MainActor () -> Void
  ) {
    self.directories = directories
    self.watchesFile = watchesFile
    self.onChange = onChange
  }

  /// Starts watching the directories that exist and can be opened; logs the others.
  func start() {
    guard sources.isEmpty else { return }
    for directory in directories {
      let descriptor = open(directory.path, O_EVTONLY)
      guard descriptor >= 0 else {
        fputs("[Watch] Cannot watch \(directory.path): errno \(errno)\n", stderr)
        continue
      }
      sources.append(makeSource(descriptor: descriptor, events: [.write, .rename, .delete]))
    }
    watchFiles()
  }

  func stop() {
    pendingChange?.cancel()
    pendingChange = nil
    for source in sources + fileSources { source.cancel() }
    sources = []
    fileSources = []
  }

  private func makeSource(
    descriptor: Int32,
    events: DispatchSource.FileSystemEvent
  ) -> any DispatchSourceFileSystemObject {
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: events,
      queue: .main
    )
    source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scheduleChange() } }
    source.setCancelHandler { close(descriptor) }
    source.resume()
    return source
  }

  /// Watches the content of every accepted file now in the directories, replacing earlier file
  /// watches so a file replaced by rename is watched by its new inode.
  private func watchFiles() {
    for fileSource in fileSources { fileSource.cancel() }
    let urls = directories.flatMap { directory in
      (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )) ?? []
    }
    fileSources = urls.filter(watchesFile).compactMap { url in
      let descriptor = open(url.path, O_EVTONLY)
      guard descriptor >= 0 else { return nil }
      return makeSource(descriptor: descriptor, events: [.write, .extend, .delete, .rename])
    }
  }

  /// Waits for a burst of changes, such as a write followed by a rename, to settle.
  private func scheduleChange() {
    pendingChange?.cancel()
    let change = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        guard let self, !self.sources.isEmpty else { return }
        self.watchFiles()
        self.onChange()
      }
    }
    pendingChange = change
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: change)
  }
}
