import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

/// The clash rules of package profiles, and the files that library writes leave alone.
extension ProfileLibraryTests {
  @Test
  func userProfileShadowsAPackageProfileByNameOnly() async throws {
    try await withLibrary { library, directory in
      let shipped = makeProfile(name: "Arcade")
      try writePackage("arcade-pack", profiles: [shipped], in: directory)
      let own = makeProfile(name: "ARCADE")
      try writeUserProfileFile(own, in: directory)

      #expect(try await library.profiles() == [own])
      #expect(try await library.profile(id: shipped.id) == nil)
      #expect(try await library.packageProfileSources().isEmpty)
    }
  }

  @Test
  func amongPackagesTheFirstByPackageNameWinsOnName() async throws {
    try await withLibrary { library, directory in
      let later = makeProfile(name: "shared")
      let first = makeProfile(name: "Shared")
      try writePackage("b-pack", profiles: [later], in: directory)
      try writePackage("a-pack", profiles: [first], in: directory)

      #expect(try await library.profiles() == [first])
      #expect(try await library.packageProfileSources() == [first.id: "a-pack"])
    }
  }

  @Test
  func deletingAShadowingUserProfileLeavesThePackageFile() async throws {
    try await withLibrary { library, directory in
      let shipped = makeProfile(name: "Arcade")
      try writePackage("arcade-pack", profiles: [shipped], in: directory)
      let own = makeProfile(name: "arcade")
      try writeUserProfileFile(own, in: directory)
      let packages = directory.appendingPathComponent("Packages")
      let before = try libraryFiles(in: packages)
      #expect(try await library.profiles() == [own])

      try await library.delete(id: own.id)

      #expect(try libraryFiles(in: packages) == before)
      #expect(try await library.profiles() == [shipped])
    }
  }

  @Test
  func replaceAndRestoreLeaveEveryPackageFile() async throws {
    try await withLibrary { library, directory in
      let shipped = makeProfile(name: "Arcade")
      try writePackage("arcade-pack", profiles: [shipped], in: directory)
      let packages = directory.appendingPathComponent("Packages")
      let before = try libraryFiles(in: packages)
      let checkpoint = try await library.checkpoint()

      let own = makeProfile(name: "Mine")
      try await library.replace(with: RemappingProfileLibraryState(profiles: [own]))
      #expect(try libraryFiles(in: packages) == before)
      try await library.replace(with: RemappingProfileLibraryState())
      #expect(try libraryFiles(in: packages) == before)
      try await library.create(makeProfile(name: "Other"))
      try await library.restore(checkpoint)

      #expect(try libraryFiles(in: packages) == before)
      #expect(try await library.profiles() == [shipped])
    }
  }

  @Test
  func anUnreadablePackageProfileDoesNotStopTheOthers() async throws {
    try await withLibrary { library, directory in
      let first = makeProfile(name: "First")
      let last = makeProfile(name: "Last")
      try writePackage(
        "arcade-pack",
        files: [
          ("a.plist", try profileData(first)), ("b.plist", Data("not json".utf8)),
          ("c.plist", try profileData(last)),
        ],
        listing: ["a.plist", "b.plist", "missing.plist", "c.plist"],
        in: directory
      )

      #expect(try await library.profiles() == [first, last])
      #expect(
        try await library.packageProfileSources() == [
          first.id: "arcade-pack", last.id: "arcade-pack",
        ]
      )
    }
  }

  @Test
  func defaultPackagesDirectoryIsThePackageStore() {
    #expect(RemappingProfileLibrary().packagesDirectory == ModPackageStore.rootDirectory)
  }

  @Test
  func anOutOfRangePackageServesNoProfile() async throws {
    let directory = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let shipped = makeProfile(name: "Arcade")
    try writePackage(
      "arcade-pack",
      profiles: [shipped],
      requires: ["minimum": "0.6.0", "below": "0.7.0"],
      in: directory
    )
    let library = RemappingProfileLibrary(directory: directory, runningVersion: "9.0.0")

    #expect(try await library.profiles().isEmpty)
    #expect(try await library.profile(id: shipped.id) == nil)
    await #expect(throws: RemappingProfileLibraryError.profileNotFound(shipped.id)) {
      try await library.activate(profileID: shipped.id)
    }
  }

  private func profileData(_ profile: RemappingProfile) throws -> Data {
    Data(try RemappingProfileFileStore.encodedPlist(profile).utf8)
  }

  /// Writes the package folder `Packages/<name>` with `profiles` as its profile files.
  private func writePackage(
    _ name: String,
    profiles: [RemappingProfile],
    requires: [String: Any] = ["minimum": "0.6.0"],
    in directory: URL
  ) throws {
    let files = try profiles.enumerated().map {
      ("profile-\($0.offset).plist", try profileData($0.element))
    }
    try writePackage(name, files: files, listing: files.map(\.0), requires: requires, in: directory)
  }

  /// Writes the package folder `Packages/<name>` with `files` in `Profiles/` and a manifest that
  /// lists `listing`.
  private func writePackage(
    _ name: String,
    files: [(String, Data)],
    listing: [String],
    requires: [String: Any] = ["minimum": "0.6.0"],
    in directory: URL
  ) throws {
    let folder = directory.appendingPathComponent("Packages/\(name)", isDirectory: true)
    let profileFolder = folder.appendingPathComponent("Profiles", isDirectory: true)
    try FileManager.default.createDirectory(at: profileFolder, withIntermediateDirectories: true)
    for (fileName, data) in files {
      try data.write(to: profileFolder.appendingPathComponent(fileName))
    }
    let manifest: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ModPackageManifest.kind, "name": name,
      "version": "1.0.0", "author": "Tester", "requires": requires, "profiles": listing,
    ]
    try PropertyListFixture.data(tree: manifest).write(
      to: folder.appendingPathComponent("mod.plist")
    )
  }

  private func writeUserProfileFile(_ profile: RemappingProfile, in directory: URL) throws {
    let folder = directory.appendingPathComponent("Profiles", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try profileData(profile).write(
      to: folder.appendingPathComponent(RemappingProfileLibrary.profileFileName(profile.id))
    )
  }
}
