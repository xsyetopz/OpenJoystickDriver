import Foundation
import OpenJoystickDriverKit

/// Applies the user's controller records and the installed packages' at start and again whenever
/// their directories change.
///
/// A change is a file added, removed, renamed, or rewritten in place, which covers
/// `ojd record install`, `ojd record remove`, editors that save by replacing the file, and
/// `echo ... > file`.
@MainActor
final class ControllerRecordWatcher {
  /// The directory of the user's controller records.
  private let directory: URL
  /// Runs with the models whose effective record changed.
  private let onChange: @MainActor (Set<ControllerModelID>) -> Void
  /// Makes a loaded record set current and returns the models whose record changed.
  private let activate: @MainActor (ControllerRecordSet) -> Set<ControllerModelID>
  /// The watcher of the record and package directories; nil while stopped.
  private var watcher: FileChangeWatcher?

  /// `onChange` runs with the models whose effective record a change to the directory
  /// changed, when there are any. `activate` makes a loaded set current and returns those
  /// models.
  init(
    directory: URL = ControllerRecordSet.userDirectory,
    activate: @escaping @MainActor (ControllerRecordSet) -> Set<ControllerModelID> = {
      $0.activate()
    },
    onChange: @escaping @MainActor (Set<ControllerModelID>) -> Void
  ) {
    self.directory = directory
    self.activate = activate
    self.onChange = onChange
  }

  /// Applies the current records and starts watching.
  ///
  /// A directory that cannot be created or opened is watched once it exists; until then the bundled
  /// catalog and any records already read apply.
  func start() {
    guard watcher == nil else { return }
    let packages = ModPackageStore.directory(besides: directory)
    for folder in [directory, packages] {
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      } catch {
        fputs("[Records] Cannot create \(folder.path): \(error.localizedDescription)\n", stderr)
      }
    }
    apply()
    // A package is installed, replaced, and removed as a folder of `Packages`, and each folder is
    // watched.
    let watcher = FileChangeWatcher(
      directories: [directory, packages],
      watchesFile: {
        $0.pathExtension == "json"
          || $0.deletingLastPathComponent().standardizedFileURL == packages.standardizedFileURL
      },
      onChange: { [weak self] in
        guard let self else { return }
        let changed = self.apply()
        if !changed.isEmpty { self.onChange(changed) }
      }
    )
    self.watcher = watcher
    watcher.start()
  }

  /// Stops watching.
  func stop() {
    watcher?.stop()
    watcher = nil
  }

  /// Loads and activates the records; returns the models whose effective record changed.
  @discardableResult
  private func apply() -> Set<ControllerModelID> {
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
