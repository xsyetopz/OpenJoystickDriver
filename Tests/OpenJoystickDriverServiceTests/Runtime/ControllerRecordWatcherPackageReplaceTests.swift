import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

@MainActor
struct ControllerRecordWatcherPackageReplaceTests {
  private static func record(_ productID: Int) -> Data {
    PropertyListFixture.bytes(
      json: """
        {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "Controller",
         "vendorID": 4660,
         "productID": \(productID), "modes": [{"id": "default", "protocol": {"family": "XboxGIP"}}]}
        """
    )
  }

  /// A package folder named `arcade-pack` that holds a record for each of `productIDs`.
  private static func package(in root: URL, _ productIDs: [Int]) throws -> URL {
    let folder = root.appendingPathComponent("Staging/\(UUID().uuidString)/arcade-pack")
    try FileManager.default.createDirectory(
      at: folder.appendingPathComponent("Controllers"),
      withIntermediateDirectories: true
    )
    let files = productIDs.map { String(format: "1234-%04x.plist", $0) }
    for (file, productID) in zip(files, productIDs) {
      try record(productID).write(to: folder.appendingPathComponent("Controllers/\(file)"))
    }
    let list = files.map { "\"\($0)\"" }.joined(separator: ", ")
    let manifest = """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "\(ModPackageManifest.kind)",
      "name": "arcade-pack", "version": "1.0.0",
       "author": "Tester", "requires": {"minimum": "0.6.0"}, "controllers": [\(list)]}
      """
    try PropertyListFixture.data(json: manifest).write(
      to: folder.appendingPathComponent("mod.plist")
    )
    return folder
  }

  @Test
  func appliesAgainWhenAnInstalledPackageIsReplaced() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-watch-replace-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
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

    let store = ModPackageStore(
      directory: root.appendingPathComponent("Packages", isDirectory: true),
      runningVersion: "0.6.0"
    )
    try store.install(Self.package(in: root, [0xabcd]))
    await waitUntil("the install is applied") { applied.last == 1 }
    #expect(applied.last == 1)

    let installedChanges = changes
    try store.install(Self.package(in: root, [0xabcd, 0xabce]), replace: true)
    await waitUntil("the replacement is applied") { applied.last == 2 }
    #expect(applied.last == 2)
    #expect(changes > installedChanges)
  }
}
