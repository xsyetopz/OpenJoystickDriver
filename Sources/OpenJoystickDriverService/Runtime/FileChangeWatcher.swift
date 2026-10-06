import Foundation

/// Calls `onChange` after files in the watched directories change.
///
/// Each directory is watched for entries being added, removed, or renamed, which covers editors
/// that save by replacing the file. Each file `watchesFile` accepts is watched as well, so a file
/// rewritten in place, such as by `echo ... > file`, also counts as a change. A directory that is
/// missing, deleted, or moved away is opened again once it exists, which also counts as a change.
@MainActor
final class FileChangeWatcher {
  private static let debounce: DispatchTimeInterval = .milliseconds(300)
  private static let retryInterval: DispatchTimeInterval = .seconds(1)

  private let directories: [URL]
  private let watchesFile: (URL) -> Bool
  private let onChange: @MainActor () -> Void
  private var isRunning = false
  private var sources: [URL: any DispatchSourceFileSystemObject] = [:]
  private var fileSources: [any DispatchSourceFileSystemObject] = []
  private var pendingChange: DispatchWorkItem?
  private var pendingRetry: DispatchWorkItem?

  init(
    directories: [URL],
    watchesFile: @escaping (URL) -> Bool = { _ in true },
    onChange: @escaping @MainActor () -> Void
  ) {
    self.directories = directories
    self.watchesFile = watchesFile
    self.onChange = onChange
  }

  /// Starts watching the directories that exist and can be opened; logs the others and tries
  /// them again until they open.
  func start() {
    guard !isRunning else { return }
    isRunning = true
    openDirectories(logsFailures: true)
    watchFiles()
  }

  func stop() {
    isRunning = false
    pendingChange?.cancel()
    pendingChange = nil
    pendingRetry?.cancel()
    pendingRetry = nil
    for source in Array(sources.values) + fileSources { source.cancel() }
    sources = [:]
    fileSources = []
  }

  /// Opens each directory not watched yet and schedules a retry for those that do not open.
  /// Returns whether any directory opened.
  @discardableResult
  private func openDirectories(logsFailures: Bool) -> Bool {
    var opened = false
    for directory in directories where sources[directory] == nil {
      let descriptor = open(directory.path, O_EVTONLY)
      guard descriptor >= 0 else {
        if logsFailures {
          fputs("[Watch] Cannot watch \(directory.path): errno \(errno)\n", stderr)
        }
        continue
      }
      sources[directory] = makeSource(descriptor: descriptor, events: [.write, .rename, .delete]) {
        [weak self] events in
        // The directory itself went away; its descriptor reports nothing more.
        if !events.isDisjoint(with: [.rename, .delete]) { self?.closeDirectory(directory) }
      }
      opened = true
    }
    if sources.count < directories.count { scheduleRetry() }
    return opened
  }

  private func closeDirectory(_ directory: URL) {
    sources.removeValue(forKey: directory)?.cancel()
  }

  private func scheduleRetry() {
    guard pendingRetry == nil else { return }
    let retry = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.isRunning else { return }
        self.pendingRetry = nil
        if self.openDirectories(logsFailures: false) { self.scheduleChange() }
      }
    }
    pendingRetry = retry
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryInterval, execute: retry)
  }

  private func makeSource(
    descriptor: Int32,
    events: DispatchSource.FileSystemEvent,
    onEvent: @escaping @MainActor (DispatchSource.FileSystemEvent) -> Void = { _ in }
  ) -> any DispatchSourceFileSystemObject {
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: events,
      queue: .main
    )
    source.setEventHandler { [weak self, weak source] in
      MainActor.assumeIsolated {
        if let source { onEvent(source.data) }
        self?.scheduleChange()
      }
    }
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
        guard let self, self.isRunning else { return }
        self.openDirectories(logsFailures: false)
        self.watchFiles()
        self.onChange()
      }
    }
    pendingChange = change
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: change)
  }
}
