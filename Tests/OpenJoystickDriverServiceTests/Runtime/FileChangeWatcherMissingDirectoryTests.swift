import Foundation
import Testing

@testable import OpenJoystickDriverService

@MainActor
struct FileChangeWatcherMissingDirectoryTests {
  /// A watched folder that does not exist yet is a normal state: the watcher reports a change
  /// once the folder appears.
  @Test
  func reportsChangeWhenMissingDirectoryAppears() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-watch-missing-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let missing = root.appendingPathComponent("Personas", isDirectory: true)
    var changes = 0
    let watcher = FileChangeWatcher(directories: [missing]) { changes += 1 }
    watcher.start()
    defer { watcher.stop() }

    try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
    for _ in 0..<50 where changes == 0 { try await Task.sleep(for: .milliseconds(100)) }

    #expect(changes >= 1)
  }

  /// A missing folder is not reported as a failure; other open errors are.
  @Test
  func missingDirectoryIsNotFailure() {
    #expect(FileChangeWatcher.isFailure(openErrno: ENOENT) == false)
    #expect(FileChangeWatcher.isFailure(openErrno: EACCES))
  }
}
