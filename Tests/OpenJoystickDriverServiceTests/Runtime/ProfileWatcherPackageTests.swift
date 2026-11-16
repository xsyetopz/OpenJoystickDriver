import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

@MainActor
struct ProfileWatcherPackageTests {
  private static let manifest = PropertyListFixture.bytes(
    json: """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "\(ModPackageManifest.kind)",
      "name": "arcade-pack", "version": "1.0.0",
        "author": "Tester", "requires": {"minimum": "0.6.0"}, "profiles": ["arcade.plist"]}
      """
  )

  /// The service's profile watcher reloads when a package is installed into, and removed from,
  /// the library's `Packages/` folder.
  @Test
  func changesWhenPackageIsInstalledAndRemoved() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-profile-watch-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let library = RemappingProfileLibrary(directory: root.appendingPathComponent("Library"))
    let staged = root.appendingPathComponent("Staging/arcade-pack", isDirectory: true)
    try FileManager.default.createDirectory(
      at: staged.appendingPathComponent("Profiles"),
      withIntermediateDirectories: true
    )
    try Self.manifest.write(to: staged.appendingPathComponent("mod.plist"))
    let profile = RemappingProfile(
      name: "Arcade",
      device: RemappingDeviceScope(vendorID: 1118, productID: 654),
      applicationScope: .global,
      bindings: []
    )
    try Data(try RemappingProfileFileStore.encodedPlist(profile).utf8).write(
      to: staged.appendingPathComponent("Profiles/arcade.plist")
    )

    let targets = ApplicationServiceRuntime.profileWatchTargets(for: library)
    for directory in targets.directories {
      try RemappingProfileLibrary.createPrivateDirectory(directory)
    }
    var changes = 0
    let watcher = FileChangeWatcher(
      directories: targets.directories,
      watchesFile: targets.watchesFile
    ) { changes += 1 }
    watcher.start()
    defer { watcher.stop() }

    let store = ModPackageStore(directory: library.packagesDirectory, runningVersion: "0.6.0")
    try store.install(staged)
    await waitUntil("the install is reported") { changes >= 1 }
    #expect(changes >= 1)
    #expect(try await library.packageProfileSources() == [profile.id: "arcade-pack"])

    let installedChanges = changes
    try store.remove("arcade-pack")
    await waitUntil("the removal is reported") { changes > installedChanges }
    #expect(changes > installedChanges)
  }
}
