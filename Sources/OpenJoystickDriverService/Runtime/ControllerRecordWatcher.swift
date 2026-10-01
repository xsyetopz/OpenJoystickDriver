import Foundation
import OpenJoystickDriverKit

/// Applies the user's controller records at start and again whenever their directory changes.
///
/// The directory is watched for entries being added, removed, or renamed, which covers `ojd record
/// install` and `ojd record remove` and editors that save by replacing the file. Each file in it is
/// watched as well, so a file rewritten in place, such as by `echo ... > file`, also reloads.
@MainActor
final class ControllerRecordWatcher {
  private static let debounce: DispatchTimeInterval = .milliseconds(300)

  private let directory: URL
  private let onChange: @MainActor (Set<ControllerIdentity>) -> Void
  private let activate: @MainActor (ControllerRecordSet) -> Set<ControllerIdentity>
  private var source: (any DispatchSourceFileSystemObject)?
  private var fileSources: [any DispatchSourceFileSystemObject] = []
  private var pendingReload: DispatchWorkItem?

  /// `onChange` runs with the identities whose effective record a change to the directory
  /// changed, when there are any. `activate` makes a loaded set current and returns those
  /// identities.
  init(
    directory: URL = ControllerRecordSet.userDirectory,
    activate: @escaping @MainActor (ControllerRecordSet) -> Set<ControllerIdentity> = {
      $0.activate()
    },
    onChange: @escaping @MainActor (Set<ControllerIdentity>) -> Void
  ) {
    self.directory = directory
    self.activate = activate
    self.onChange = onChange
  }

  /// Applies the current records and starts watching. Returns without watching when the directory
  /// cannot be created or opened; the bundled catalog and any records already read still apply.
  func start() {
    guard source == nil else { return }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      fputs("[Records] Cannot create \(directory.path): \(error.localizedDescription)\n", stderr)
    }
    apply()
    let descriptor = open(directory.path, O_EVTONLY)
    guard descriptor >= 0 else {
      fputs("[Records] Cannot watch \(directory.path): errno \(errno)\n", stderr)
      return
    }
    source = makeSource(descriptor: descriptor, events: [.write, .rename, .delete])
    watchFiles()
  }

  func stop() {
    pendingReload?.cancel()
    pendingReload = nil
    source?.cancel()
    source = nil
    for fileSource in fileSources { fileSource.cancel() }
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
    source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scheduleReload() } }
    source.setCancelHandler { close(descriptor) }
    source.resume()
    return source
  }

  /// Watches the content of every file now in the directory, replacing earlier file watches so a
  /// file replaced by rename is watched by its new inode.
  private func watchFiles() {
    for fileSource in fileSources { fileSource.cancel() }
    let urls =
      (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )) ?? []
    fileSources = urls.compactMap { url in
      let descriptor = open(url.path, O_EVTONLY)
      guard descriptor >= 0 else { return nil }
      return makeSource(descriptor: descriptor, events: [.write, .extend, .delete, .rename])
    }
  }

  /// Waits for a burst of changes, such as a write followed by a rename, to settle.
  private func scheduleReload() {
    pendingReload?.cancel()
    let reload = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.source != nil else { return }
        self.watchFiles()
        let changed = self.apply()
        if !changed.isEmpty { self.onChange(changed) }
      }
    }
    pendingReload = reload
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: reload)
  }

  /// Loads and activates the records; returns the identities whose effective record changed.
  @discardableResult
  private func apply() -> Set<ControllerIdentity> {
    let records = ControllerRecordSet.load(userDirectory: directory)
    for file in records.problems {
      fputs("[Records] Skipped \(file.url.path): \(file.problem ?? "")\n", stderr)
    }
    let applied = records.userFiles.count - records.problems.count
    print("[Records] Applied \(applied) user controller record(s)")
    return activate(records)
  }
}
