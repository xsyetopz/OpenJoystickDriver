import Foundation
import OpenJoystickDriverKit

/// Applies the user's controller records at start and again whenever their directory changes.
///
/// A change is a file added, removed, renamed, or rewritten in place, which covers
/// `ojd record install`, `ojd record remove`, editors that save by replacing the file, and
/// `echo ... > file`.
@MainActor
final class ControllerRecordWatcher {
  private let directory: URL
  private let onChange: @MainActor (Set<ControllerIdentity>) -> Void
  private let activate: @MainActor (ControllerRecordSet) -> Set<ControllerIdentity>
  private var watcher: FileChangeWatcher?

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

  /// Applies the current records and starts watching. A directory that cannot be created or opened
  /// is watched once it exists; until then the bundled catalog and any records already read apply.
  func start() {
    guard watcher == nil else { return }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      fputs("[Records] Cannot create \(directory.path): \(error.localizedDescription)\n", stderr)
    }
    apply()
    // The parent folder holds `Defaults.json`, which sits under every record's tuning.
    let watcher = FileChangeWatcher(
      directories: [directory, directory.deletingLastPathComponent()],
      watchesFile: { $0.pathExtension == "json" },
      onChange: { [weak self] in
        guard let self else { return }
        let changed = self.apply()
        if !changed.isEmpty { self.onChange(changed) }
      }
    )
    self.watcher = watcher
    watcher.start()
  }

  func stop() {
    watcher?.stop()
    watcher = nil
  }

  /// Loads and activates the records; returns the identities whose effective record changed.
  @discardableResult
  private func apply() -> Set<ControllerIdentity> {
    let records = ControllerRecordSet.load(userDirectory: directory)
    for file in records.problems {
      fputs("[Records] Skipped \(file.url.path): \(file.problem ?? "")\n", stderr)
    }
    if let problem = records.defaults?.problem, let url = records.defaults?.url {
      fputs("[Records] Ignored \(url.path): \(problem)\n", stderr)
    }
    let applied = records.userFiles.count - records.problems.count
    print("[Records] Applied \(applied) user controller record(s)")
    return activate(records)
  }
}
