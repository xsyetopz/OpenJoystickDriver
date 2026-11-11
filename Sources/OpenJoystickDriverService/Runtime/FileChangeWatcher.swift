import Foundation

/// Calls `onChange` after files in the watched directories change.
///
/// Each directory is watched for entries being added, removed, or renamed, which covers editors
/// that save by replacing the file. Each file `watchesFile` accepts is watched as well, so a file
/// rewritten in place, such as by `echo ... > file`, also counts as a change. A directory that is
/// missing, deleted, or moved away is opened again once it exists, which also counts as a change.
@MainActor
final class FileChangeWatcher {
  /// The wait for a burst of changes to settle.
  private static let debounce: DispatchTimeInterval = .milliseconds(300)
  /// The wait before an unopened directory is opened again.
  private static let retryInterval: DispatchTimeInterval = .seconds(1)

  /// The directories to watch.
  private let directories: [URL]
  /// Accepts the files whose rewrite in place counts as a change.
  private let watchesFile: (URL) -> Bool
  /// Runs once after a change.
  private let onChange: @MainActor () -> Void
  /// Whether ``start()`` ran and ``stop()`` has not.
  private var isRunning = false
  /// The sources of the directories that are open.
  private var sources: [URL: any DispatchSourceFileSystemObject] = [:]
  /// The sources of the accepted files.
  private var fileSources: [any DispatchSourceFileSystemObject] = []
  /// The scheduled call of `onChange`.
  private var pendingChange: DispatchWorkItem?
  /// The scheduled attempt to open the directories that are not open.
  private var pendingRetry: DispatchWorkItem?

  /// Creates a watcher over `directories`.
  ///
  /// - Parameters:
  ///   - directories: The directories to watch.
  ///   - watchesFile: Accepts the files that are watched for rewrites in place.
  ///   - onChange: Runs after a change settles.
  init(
    directories: [URL],
    watchesFile: @escaping (URL) -> Bool = { _ in true },
    onChange: @escaping @MainActor () -> Void
  ) {
    self.directories = directories
    self.watchesFile = watchesFile
    self.onChange = onChange
  }

  /// Starts watching the directories that exist and can be opened; logs those that fail to open
  /// for a reason other than not existing, and tries every unopened one again until it opens.
  func start() {
    guard !isRunning else { return }
    isRunning = true
    openDirectories(logsFailures: true)
    watchFiles()
  }

  /// Cancels every watch and every scheduled call.
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
  ///
  /// Returns whether any directory opened.
  @discardableResult
  private func openDirectories(logsFailures: Bool) -> Bool {
    var opened = false
    for directory in directories where sources[directory] == nil {
      let descriptor = unsafe open(directory.path, O_EVTONLY)
      guard descriptor >= 0 else {
        if logsFailures, Self.isFailure(openErrno: errno) {
          unsafe fputs("[Watch] Cannot watch \(directory.path): errno \(errno)\n", unsafe stderr)
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

  /// A directory that does not exist yet is a normal state and is watched once it appears; any
  /// other error from opening it is a failure.
  static func isFailure(openErrno code: Int32) -> Bool { code != ENOENT }

  /// Stops watching `directory`, which went away.
  private func closeDirectory(_ directory: URL) {
    sources.removeValue(forKey: directory)?.cancel()
  }

  /// Schedules one attempt to open the directories that are not open.
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

  /// Creates and starts a dispatch source on `descriptor`; `onEvent` receives the events, and every
  /// event schedules a change.
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

  /// Watches the content of every accepted file in the directories, replacing earlier file
  /// watches so a file replaced by rename is watched by its replacement inode.
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
      let descriptor = unsafe open(url.path, O_EVTONLY)
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
