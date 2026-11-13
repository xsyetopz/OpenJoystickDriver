import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

/// The read-only layer of profiles that installed mod packages serve.
extension ProfileLibraryTests {
  @Test
  func packageProfilesAreServedAndListed() async throws {
    try await withLibrary { library, directory in
      let shipped = makeProfile(name: "Arcade")
      try installPackage("arcade-pack", [shipped], in: directory)
      let own = makeProfile(name: "Mine")
      try await library.create(own)

      let listed = try await library.profiles()
      #expect(listed.map(\.name) == ["Arcade", "Mine"])
      #expect(try await library.profile(id: shipped.id) == shipped)
      #expect(try await library.snapshot().profiles.contains(shipped))
      #expect(try await library.packageProfileSources() == [shipped.id: "arcade-pack"])
    }
  }

  @Test
  func userProfileWinsOnIDAndOnName() async throws {
    try await withLibrary { library, directory in
      let sharedID = UUID()
      let byID = makeProfile(id: sharedID, name: "By ID")
      let byName = makeProfile(name: "By Name")
      try installPackage(
        "arcade-pack",
        [makeProfile(id: sharedID, name: "Packaged By ID"), makeProfile(name: "by name")],
        in: directory
      )
      try writeUserProfile(byID, in: directory)
      try writeUserProfile(byName, in: directory)

      let listed = try await library.profiles()
      #expect(Set(listed.map(\.id)) == [byID.id, byName.id])
      #expect(try await library.profile(id: sharedID) == byID)
      #expect(try await library.packageProfileSources().isEmpty)
    }
  }

  @Test
  func firstPackageByNameWins() async throws {
    try await withLibrary { library, directory in
      let id = UUID()
      let first = makeProfile(id: id, name: "Shared")
      try installPackage("a-pack", [first], in: directory)
      try installPackage(
        "b-pack",
        [makeProfile(id: id, name: "Other"), makeProfile(name: "SHARED")],
        in: directory
      )

      #expect(try await library.profiles() == [first])
      #expect(try await library.packageProfileSources() == [id: "a-pack"])
    }
  }

  @Test
  func changesToPackageProfilesAreRefusedAndChangeNothing() async throws {
    try await withLibrary { library, directory in
      let shipped = makeProfile(name: "Arcade")
      try installPackage("arcade-pack", [shipped], in: directory)
      try await library.create(makeProfile(name: "Mine"))
      let before = try libraryFiles(in: directory)
      let edited = makeProfile(id: shipped.id, name: "Edited")

      await expectReadOnly { try await library.update(edited, expectedCurrent: shipped) }
      await expectReadOnly { try await library.delete(id: shipped.id) }
      await expectReadOnly { try await library.importProfile(edited) }
      await expectReadOnly { try await library.create(edited) }
      #expect(try libraryFiles(in: directory) == before)
      #expect(try await library.profile(id: shipped.id) == shipped)
    }
  }

  @Test
  func userProfilesCannotTakePackageProfileName() async throws {
    try await withLibrary { library, directory in
      try installPackage("arcade-pack", [makeProfile(name: "Arcade")], in: directory)
      let own = makeProfile(name: "Mine")
      try await library.create(own)

      await #expect(throws: RemappingProfileLibraryError.duplicateName("arcade")) {
        try await library.create(makeProfile(name: "arcade"))
      }
      await #expect(throws: RemappingProfileLibraryError.duplicateName("ARCADE")) {
        try await library.update(makeProfile(id: own.id, name: "ARCADE"), expectedCurrent: own)
      }
      await #expect(throws: RemappingProfileLibraryError.duplicateName("Arcade")) {
        try await library.importProfile(makeProfile(name: "Arcade"))
      }
    }
  }

  @Test
  func activationPersistsAcrossLibraryInstances() async throws {
    try await withLibrary { library, directory in
      let shipped = makeProfile(name: "Arcade")
      try installPackage("arcade-pack", [shipped], in: directory)
      try await library.activate(profileID: shipped.id)

      #expect(try await library.activeProfile(vendorID: 1118, productID: 654) == shipped)
      let restored = RemappingProfileLibrary(directory: directory)
      #expect(try await restored.activeProfile(vendorID: 1118, productID: 654) == shipped)
      #expect(try await restored.snapshot().activeProfiles.map(\.profileID) == [shipped.id])

      try await restored.deactivate(profileID: shipped.id)
      #expect(try await restored.activeProfile(vendorID: 1118, productID: 654) == nil)
    }
  }

  @Test
  func removedPackageBehavesLikeMissingProfile() async throws {
    try await withLibrary { library, directory in
      let shipped = makeProfile(name: "Arcade")
      try installPackage("arcade-pack", [shipped], in: directory)
      try await library.activate(profileID: shipped.id)

      try FileManager.default.removeItem(
        at: directory.appendingPathComponent("Packages/arcade-pack")
      )
      let changed = try await library.reload()

      #expect(changed == [RemappingProfileModel(vendorID: 1118, productID: 654)])
      #expect(try await library.profiles().isEmpty)
      #expect(try await library.profile(id: shipped.id) == nil)
      #expect(try await library.activeProfile(vendorID: 1118, productID: 654) == nil)
      await #expect(throws: RemappingProfileLibraryError.profileNotFound(shipped.id)) {
        try await library.activate(profileID: shipped.id)
      }
    }
  }

  @Test
  func writesNeverTouchPackagesFolder() async throws {
    try await withLibrary { library, directory in
      let shipped = makeProfile(name: "Arcade")
      try installPackage("arcade-pack", [shipped], in: directory)
      let packages = directory.appendingPathComponent("Packages")
      let before = try libraryFiles(in: packages)

      let own = makeProfile(name: "Mine")
      try await library.create(own)
      try await library.activate(profileID: own.id)
      try await library.activate(profileID: shipped.id)
      try await library.delete(id: own.id)
      try await library.deactivateAll(vendorID: 1118, productID: 654)

      #expect(try libraryFiles(in: packages) == before)
      #expect(try await library.profiles() == [shipped])
    }
  }

  @Test
  func profileCountLimitIgnoresPackageProfiles() async throws {
    try await withLibrary { library, directory in
      try installPackage("arcade-pack", [makeProfile(name: "Arcade")], in: directory)
      let limit = RemappingProfileLibrary.maximumProfileCount
      for index in 0..<limit { try await library.create(makeProfile(name: "Own \(index)")) }

      #expect(try await library.profiles().count == limit + 1)
      await #expect(throws: RemappingProfileLibraryError.profileCountExceeded(limit + 1)) {
        try await library.create(makeProfile(name: "One too many"))
      }
    }
  }

  /// Writes `profiles` as the profile files of the package folder `Packages/<name>`.
  private func installPackage(
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

  private func writeUserProfile(_ profile: RemappingProfile, in directory: URL) throws {
    let folder = directory.appendingPathComponent("Profiles", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(try RemappingProfileFileStore.encodedPlist(profile).utf8).write(
      to: folder.appendingPathComponent(RemappingProfileLibrary.profileFileName(profile.id))
    )
  }

  private func expectReadOnly(
    _ operation: @Sendable () async throws -> some Any,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    await #expect(
      throws: RemappingProfileLibraryError.packageProfileReadOnly,
      sourceLocation: sourceLocation
    ) { _ = try await operation() }
  }
}
