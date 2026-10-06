import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

@MainActor
struct ControllerRecordWatcherTests {
  private static let addRecord = Data(
    """
    {"$schema": "\(ControllerRecordSet.overrideSchemaID)", "operation": "add",
     "record": {"$schema": "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/\
    Resources/Schemas/v1beta1/controller.schema.json", "vendorID": 4660, "productID": 43981,
     "protocol": {"family": "xbox.gip"}}}
    """.utf8
  )

  @Test
  func appliesAtStartAndAgainWhenAFileArrives() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-watch-\(UUID().uuidString)/Controllers",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
    var applied: [Int] = []
    var changes = 0
    let watcher = ControllerRecordWatcher(
      directory: directory,
      activate: { records in
        applied.append(records.userFiles.count)
        return [ControllerIdentity(vendorID: 0x1234, productID: 0xabcd)]
      },
      onChange: { _ in changes += 1 }
    )
    watcher.start()
    defer { watcher.stop() }
    #expect(FileManager.default.fileExists(atPath: directory.path))
    #expect(applied == [0])
    #expect(changes == 0)

    try Self.addRecord.write(
      to: directory.appendingPathComponent("1234-abcd.json"),
      options: .atomic
    )
    for _ in 0..<50 where changes == 0 { try await Task.sleep(nanoseconds: 100_000_000) }
    #expect(applied.last == 1)
    #expect(changes == 1)
  }

  @Test
  func appliesAgainWhenAFileIsRewrittenInPlace() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-watch-\(UUID().uuidString)/Controllers",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
    let file = directory.appendingPathComponent("1234-abcd.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Self.addRecord.write(to: file)
    var applied = 0
    var changes = 0
    let watcher = ControllerRecordWatcher(
      directory: directory,
      activate: { _ in
        applied += 1
        return [ControllerIdentity(vendorID: 0x1234, productID: 0xabcd)]
      },
      onChange: { _ in changes += 1 }
    )
    watcher.start()
    defer { watcher.stop() }
    #expect(applied == 1)

    // Same inode: truncate and write, as `echo ... > file` or an in-place editor save does.
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: 0)
    try handle.write(contentsOf: Data(Self.addRecord.dropLast()) + Data(" }".utf8))
    try handle.close()
    for _ in 0..<30 where changes == 0 { try await Task.sleep(nanoseconds: 100_000_000) }
    #expect(applied == 2)
    #expect(changes == 1)
  }

  @Test
  func appliesAgainWhenTheDirectoryIsDeletedAndRecreated() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-watch-\(UUID().uuidString)/Controllers",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
    var applied: [Int] = []
    let watcher = ControllerRecordWatcher(
      directory: directory,
      activate: { records in
        applied.append(records.userFiles.count)
        return [ControllerIdentity(vendorID: 0x1234, productID: 0xabcd)]
      },
      onChange: { _ in }
    )
    watcher.start()
    defer { watcher.stop() }
    #expect(applied == [0])

    try FileManager.default.removeItem(at: directory)
    // Let the deletion settle, so the watch on the old directory is gone before the new one exists.
    for _ in 0..<30 where applied.count < 2 { try await Task.sleep(nanoseconds: 100_000_000) }
    #expect(applied == [0, 0])
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Self.addRecord.write(
      to: directory.appendingPathComponent("1234-abcd.json"),
      options: .atomic
    )
    for _ in 0..<50 where applied.last != 1 { try await Task.sleep(nanoseconds: 100_000_000) }
    #expect(applied.last == 1)
  }

  @Test
  func appliesOnceADirectoryThatCouldNotBeCreatedExists() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-watch-\(UUID().uuidString)",
      isDirectory: true
    )
    let directory = root.appendingPathComponent("Controllers", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    // A regular file where the parent directory belongs makes the creation at start fail.
    try Data().write(to: root)
    var applied: [Int] = []
    var changes = 0
    let watcher = ControllerRecordWatcher(
      directory: directory,
      activate: { records in
        // The unreadable directory is a problem entry in `userFiles`; count only valid records.
        applied.append(records.userFiles.count - records.problems.count)
        return [ControllerIdentity(vendorID: 0x1234, productID: 0xabcd)]
      },
      onChange: { _ in changes += 1 }
    )
    watcher.start()
    defer { watcher.stop() }
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    #expect(applied == [0])

    try FileManager.default.removeItem(at: root)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Self.addRecord.write(
      to: directory.appendingPathComponent("1234-abcd.json"),
      options: .atomic
    )
    for _ in 0..<50 where applied.last != 1 { try await Task.sleep(nanoseconds: 100_000_000) }
    #expect(applied.last == 1)
    #expect(changes >= 1)
  }
}
