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
  /// The set last activated: a file that applied in it and fails now leaves it in force.
  private var current: ControllerRecordSet?

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
        unsafe fputs(
          "[Records] Cannot create \(folder.path): \(error.localizedDescription)\n",
          unsafe stderr
        )
      }
    }
    apply()
    // A package is installed, replaced, and removed as a folder of `Packages`, and each folder is
    // watched.
    let started = FileChangeWatcher(
      directories: [directory, packages],
      watchesFile: {
        ["plist", "json"].contains($0.pathExtension)
          || $0.deletingLastPathComponent().standardizedFileURL == packages.standardizedFileURL
      },
      onChange: { [weak self] in
        guard let self else { return }
        let changed = apply()
        if !changed.isEmpty { onChange(changed) }
      }
    )
    self.watcher = started
    started.start()
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
      unsafe fputs("[Records] Skipped \(file.url.path): \(file.problem ?? "")\n", unsafe stderr)
    }
    if let problem = records.defaults?.problem, let url = records.defaults?.url {
      unsafe fputs("[Records] Ignored \(url.path): \(problem)\n", unsafe stderr)
    }
    let failing = Set(records.problems.map(\.url))
    if let current,
      current.userFiles.contains(where: { $0.problem == nil && failing.contains($0.url) })
    {
      return []
    }
    current = records
    let applied = records.userFiles.count - records.problems.count
    print("[Records] Applied \(applied) user controller record(s)")
    return activate(records)
  }
}
