import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

extension RemappingRequestCoordinatorTests {
  @Test
  func snapshotListsEachPackageProfileWithItsPackage() async throws {
    let harness = try makeRollbackHarness()
    defer { harness.removeFiles() }
    let shipped = [profile(name: "Arcade B"), profile(name: "Arcade A")]
    try writePackage("arcade-pack", shipped, in: harness.directory)
    let own = profile(name: "Mine")
    _ = try await harness.coordinator.create(own).get()

    let snapshot = try await harness.coordinator.snapshot().get()

    let expected = shipped.map {
      ApplicationServiceRemappingPackageProfile(profileID: $0.id, package: "arcade-pack")
    }.sorted { $0.profileID.uuidString < $1.profileID.uuidString }
    #expect(snapshot.packageProfiles == expected)
    #expect(Set(snapshot.profiles.map(\.id)) == Set((shipped + [own]).map(\.id)))
  }

  /// Writes `profiles` as the profile files of the package folder `Packages/<name>`.
  private func writePackage(
    _ name: String,
    _ profiles: [RemappingProfile],
    in directory: URL
  ) throws {
    let folder = directory.appendingPathComponent("Packages/\(name)", isDirectory: true)
    let profileFolder = folder.appendingPathComponent("Profiles", isDirectory: true)
    try FileManager.default.createDirectory(at: profileFolder, withIntermediateDirectories: true)
    var fileNames: [String] = []
    for (index, profile) in profiles.enumerated() {
      let fileName = "profile-\(index).plist"
      fileNames.append(fileName)
      try Data(try RemappingProfileFileStore.encodedPlist(profile).utf8).write(
        to: profileFolder.appendingPathComponent(fileName)
      )
    }
    let manifest: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ModPackageManifest.kind, "name": name,
      "version": "1.0.0", "author": "Tester", "requires": ["minimum": "0.6.0"],
      "profiles": fileNames,
    ]
    try PropertyListFixture.data(tree: manifest).write(
      to: folder.appendingPathComponent("mod.plist")
    )
  }
}
