import Foundation
import OpenJoystickDriverKit

/// Applies the user's controller records at start and again whenever their directory changes.
///
/// The directory is watched for entries being added, removed, or renamed, which covers `ojd record
/// install` and `ojd record remove` and editors that save by replacing the file. A file rewritten
/// in place is picked up at the next change or service start.
@MainActor
final class ControllerRecordWatcher {
  private static let debounce: DispatchTimeInterval = .milliseconds(300)

  private let directory: URL
  private let onChange: @MainActor () -> Void
  private let activate: @MainActor (ControllerRecordSet) -> Bool
  private var source: (any DispatchSourceFileSystemObject)?
  private var pendingReload: DispatchWorkItem?

  /// `onChange` runs after a change to the directory changed an effective record. `activate`
  /// makes a loaded set current and returns whether that changed an effective record.
  init(
    directory: URL = ControllerRecordSet.userDirectory,
    activate: @escaping @MainActor (ControllerRecordSet) -> Bool = { $0.activate() },
    onChange: @escaping @MainActor () -> Void
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
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .rename, .delete],
      queue: .main
    )
    source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scheduleReload() } }
    source.setCancelHandler { close(descriptor) }
    self.source = source
    source.resume()
  }

  func stop() {
    pendingReload?.cancel()
    pendingReload = nil
    source?.cancel()
    source = nil
  }

  /// Waits for a burst of changes, such as a write followed by a rename, to settle.
  private func scheduleReload() {
    pendingReload?.cancel()
    let reload = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.source != nil else { return }
        if self.apply() { self.onChange() }
      }
    }
    pendingReload = reload
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: reload)
  }

  /// Loads and activates the records; returns whether an effective record changed.
  @discardableResult
  private func apply() -> Bool {
    let records = ControllerRecordSet.load(userDirectory: directory)
    for file in records.problems {
      fputs("[Records] Skipped \(file.url.path): \(file.problem ?? "")\n", stderr)
    }
    let applied = records.userFiles.count - records.problems.count
    print("[Records] Applied \(applied) user controller record(s)")
    return activate(records)
  }
}
