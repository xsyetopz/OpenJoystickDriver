import Foundation
import OpenJoystickDriverTestSupport
import Testing

struct EquivalenceSnapshotStoreTests {
  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ojd-snapshot-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test
  func reportsMismatchMissingFileAndAcceptsMatch() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let rendered = EquivalenceSnapshotStore.render([(title: "0001:0002", lines: ["a=1"])])

    let missing = try EquivalenceSnapshotStore.verify(
      rendered,
      named: "x.txt",
      in: directory,
      environment: [:]
    )
    #expect(missing?.contains("is missing") == true)

    try Data(rendered.utf8).write(to: directory.appendingPathComponent("x.txt"))
    let matching = try EquivalenceSnapshotStore.verify(
      rendered,
      named: "x.txt",
      in: directory,
      environment: [:]
    )
    #expect(matching == nil)

    let changed = EquivalenceSnapshotStore.render([(title: "0001:0002", lines: ["a=2"])])
    let mismatch = try EquivalenceSnapshotStore.verify(
      changed,
      named: "x.txt",
      in: directory,
      environment: [:]
    )
    #expect(mismatch?.contains("differs from the tree") == true)
  }

  @Test
  func writeModeRewritesSnapshot() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let rendered = EquivalenceSnapshotStore.render([(title: "0001:0002", lines: ["a=1"])])
    let result = try EquivalenceSnapshotStore.verify(
      rendered,
      named: "x.txt",
      in: directory,
      environment: ["OJD_SNAPSHOT_WRITE": "1"]
    )
    #expect(result == nil)
    let written = try String(
      contentsOf: directory.appendingPathComponent("x.txt"),
      encoding: .utf8
    )
    #expect(written == rendered)
  }
}
