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
    Resources/Schemas/controller.schema.json", "vendorID": 4660, "productID": 43981,
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
        return true
      },
      onChange: { changes += 1 }
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
}
