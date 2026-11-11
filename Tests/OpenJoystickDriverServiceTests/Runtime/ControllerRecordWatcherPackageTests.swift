import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

@MainActor
struct ControllerRecordWatcherPackageTests {
  private static let record = PropertyListFixture.bytes(
    json: """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "Controller",
       "vendorID": 4660,
       "productID": 43981, "modes": [{"id": "default", "protocol": {"family": "XboxGIP"}}]}
      """
  )

  private static let manifest = PropertyListFixture.bytes(
    json: """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "\(ModPackageManifest.kind)",
      "name": "arcade-pack", "version": "1.0.0",
       "author": "Tester", "requires": {"minimum": "0.6.0"}, "controllers": ["1234-abcd.plist"]}
      """
  )

  @Test
  func appliesAgainWhenAPackageIsInstalledAndRemoved() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-watch-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let staged = root.appendingPathComponent("Staging/arcade-pack", isDirectory: true)
    try FileManager.default.createDirectory(
      at: staged.appendingPathComponent("Controllers"),
      withIntermediateDirectories: true
    )
    try Self.manifest.write(to: staged.appendingPathComponent("mod.plist"))
    try Self.record.write(to: staged.appendingPathComponent("Controllers/1234-abcd.plist"))

    var applied: [Int] = []
    var changes = 0
    let watcher = ControllerRecordWatcher(
      directory: root.appendingPathComponent("Controllers", isDirectory: true),
      activate: { records in
        applied.append(records.userFiles.count)
        return [ControllerModelID(vendorID: 0x1234, productID: 0xabcd)]
      },
      onChange: { _ in changes += 1 }
    )
    watcher.start()
    defer { watcher.stop() }
    #expect(applied == [0])

    let store = ModPackageStore(
      directory: root.appendingPathComponent("Packages", isDirectory: true),
      runningVersion: "0.6.0"
    )
    try store.install(staged)
    await waitUntil("the install is reported") { changes >= 1 }
    #expect(applied.last == 1)
    #expect(changes >= 1)

    let installedChanges = changes
    try store.remove("arcade-pack")
    await waitUntil("the removal is reported") { changes > installedChanges }
    #expect(applied.last == 0)
    #expect(changes > installedChanges)
  }
}
