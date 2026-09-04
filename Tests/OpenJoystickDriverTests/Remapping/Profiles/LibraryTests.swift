import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct ProfileLibraryTests {
  @Test func missingLibraryStartsEmpty() async throws {
    try await withLibrary { library, url in
      let profiles = try await library.profiles()
      #expect(profiles.isEmpty)
      #expect(!FileManager.default.fileExists(atPath: url.path))
    }
  }

  @Test func profilesPersistAcrossLibraryInstances() async throws {
    try await withLibrary { library, url in
      let profile = makeProfile(name: "Primary")
      try await library.create(profile)

      let restored = RemappingProfileLibrary(fileURL: url)
      let restoredProfiles = try await restored.profiles()
      #expect(restoredProfiles == [profile])
    }
  }

  @Test func createUpdateAndDeleteUseProfileIdentifiers() async throws {
    try await withLibrary { library, _ in
      let original = makeProfile(name: "Primary")
      try await library.create(original)
      let updated = makeProfile(id: original.id, name: "Renamed")
      try await library.update(updated, expectedCurrent: original)

      let saved = try await library.profile(id: original.id)
      #expect(saved == updated)
      try await library.activate(profileID: updated.id)
      let edited = makeProfile(id: updated.id, name: "Edited")
      try await library.update(edited, expectedCurrent: updated)
      let activeEdited = try await library.activeProfile(vendorID: 1118, productID: 654)
      #expect(activeEdited == edited)
      let moved = makeProfile(id: edited.id, name: "Moved", vendorID: 1356, productID: 2508)
      try await library.update(moved, expectedCurrent: edited)
      let activePreviousModel = try await library.activeProfile(vendorID: 1118, productID: 654)
      #expect(activePreviousModel == nil)
      try await library.delete(id: original.id)
      let deleted = try await library.profile(id: original.id)
      #expect(deleted == nil)
      await #expect(throws: RemappingProfileLibraryError.profileNotFound(original.id)) {
        try await library.delete(id: original.id)
      }
    }
  }

  @Test func namesAreUniqueWithoutCaseSensitivity() async throws {
    try await withLibrary { library, _ in
      try await library.create(makeProfile(name: "Primary"))
      await #expect(throws: RemappingProfileLibraryError.duplicateName("primary")) {
        try await library.create(makeProfile(name: "primary"))
      }
    }
  }

  @Test func staleExpectedProfileIsRejectedWithoutChangingBytesOrCache() async throws {
    try await withLibrary { library, url in
      let original = makeProfile(name: "Primary")
      let firstUpdate = makeProfile(id: original.id, name: "First update")
      let staleUpdate = makeProfile(id: original.id, name: "Stale update")
      try await library.create(original)
      try await library.update(firstUpdate, expectedCurrent: original)
      let bytesAfterFirstUpdate = try Data(contentsOf: url)

      await #expect(throws: RemappingProfileLibraryError.profileUpdateConflict(original.id)) {
        try await library.update(staleUpdate, expectedCurrent: original)
      }

      #expect(try Data(contentsOf: url) == bytesAfterFirstUpdate)
      #expect(try await library.profile(id: original.id) == firstUpdate)
    }
  }

  @Test func importPreservesActivationOnlyWhenModelIsUnchanged() async throws {
    try await withLibrary { library, _ in
      let original = makeProfile(name: "Primary")
      try await library.create(original)
      try await library.activate(profileID: original.id)

      let edited = makeProfile(id: original.id, name: "Edited")
      try await library.importProfile(edited)
      let activeEdited = try await library.activeProfile(vendorID: 1118, productID: 654)
      #expect(activeEdited == edited)

      let moved = makeProfile(id: original.id, name: "Moved", vendorID: 1356, productID: 2508)
      try await library.importProfile(moved)
      let activePreviousModel = try await library.activeProfile(vendorID: 1118, productID: 654)
      #expect(activePreviousModel == nil)
    }
  }

  @Test func invalidProfilesAreRejectedWithoutMutation() async throws {
    try await withLibrary { library, _ in
      let invalid = RemappingProfile(
        name: " ",
        device: RemappingDeviceScope(vendorID: 1118, productID: 654),
        applicationScope: .global,
        bindings: []
      )
      await #expect(throws: RemappingProfileLibraryError.invalidProfile(.invalidProfileName)) {
        try await library.create(invalid)
      }
      let profiles = try await library.profiles()
      #expect(profiles.isEmpty)
    }
  }

  @Test func activationIsIsolatedByModelAndCanBeDeactivated() async throws {
    try await withLibrary { library, _ in
      let first = makeProfile(name: "First", vendorID: 1118, productID: 654)
      let replacement = makeProfile(name: "Replacement", vendorID: 1118, productID: 654)
      let other = makeProfile(name: "Other", vendorID: 1356, productID: 2508)
      try await library.create(first)
      try await library.create(replacement)
      try await library.create(other)

      try await library.activate(profileID: first.id)
      try await library.activate(profileID: other.id)
      try await library.activate(profileID: replacement.id)

      let activeFirstModel = try await library.activeProfile(vendorID: 1118, productID: 654)
      let activeOtherModel = try await library.activeProfile(vendorID: 1356, productID: 2508)
      #expect(activeFirstModel == replacement)
      #expect(activeOtherModel == other)
      try await library.deactivateAll(vendorID: 1118, productID: 654)
      let deactivated = try await library.activeProfile(vendorID: 1118, productID: 654)
      let stillActive = try await library.activeProfile(vendorID: 1356, productID: 2508)
      #expect(deactivated == nil)
      #expect(stillActive == other)
    }
  }

  @Test func deletingProfileClearsItsActiveSelection() async throws {
    try await withLibrary { library, _ in
      let profile = makeProfile(name: "Primary")
      try await library.create(profile)
      try await library.activate(profileID: profile.id)
      try await library.delete(id: profile.id)
      let active = try await library.activeProfile(vendorID: 1118, productID: 654)
      #expect(active == nil)
    }
  }

  @Test func corruptLibraryIsPreservedRatherThanOverwritten() async throws {
    try await withLibrary { library, url in
      let corrupt = Data("not json".utf8)
      try corrupt.write(to: url)

      await #expect(throws: RemappingProfileLibraryError.corruptLibrary) {
        try await library.create(makeProfile(name: "Primary"))
      }
      let preserved = try Data(contentsOf: url)
      #expect(preserved == corrupt)
    }
  }

  @Test func emptyLegacyLibraryIsPromotedToCurrentSchemaVersion() async throws {
    try await withLibrary { library, url in
      let legacy = Data(#"{"profiles":[],"schema_version":1,"active_profiles":[]}"#.utf8)
      try legacy.write(to: url)

      let profiles = try await library.profiles()
      #expect(profiles.isEmpty)

      let persisted = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
      #expect(persisted?["schema_version"] as? Int == RemappingProfileLibraryState.currentSchemaVersion)
      #expect((persisted?["profiles"] as? [Any])?.isEmpty == true)
      #expect((persisted?["active_profiles"] as? [Any])?.isEmpty == true)
    }
  }

  @Test func nonEmptyLegacyLibraryStillRejectsUnsupportedVersion() async throws {
    try await withLibrary { library, url in
      let profile = makeProfile(name: "Primary")
      let encodedProfile = try JSONEncoder().encode(profile)
      let profileObject = try #require(
        JSONSerialization.jsonObject(with: encodedProfile) as? [String: Any]
      )
      let legacyObject: [String: Any] = [
        "schema_version": 1,
        "profiles": [profileObject],
        "active_profiles": [],
      ]
      try JSONSerialization.data(withJSONObject: legacyObject).write(to: url)

      await #expect(throws: RemappingProfileLibraryError.unsupportedLibraryVersion(1)) {
        _ = try await library.profiles()
      }
    }
  }

  @Test func listingUsesDeterministicNameThenIdentifierOrder() async throws {
    try await withLibrary { library, _ in
      let alphaLast = makeProfile(id: identifier(last: 255), name: "alpha")
      let beta = makeProfile(id: identifier(last: 1), name: "Beta")
      let alphaFirst = makeProfile(id: identifier(last: 0), name: "Alpine")
      try await library.create(alphaLast)
      try await library.create(beta)
      try await library.create(alphaFirst)

      let profiles = try await library.profiles()
      #expect(profiles.map(\.id) == [alphaLast.id, alphaFirst.id, beta.id])
    }
  }

  @Test func savedLibraryAndParentAreOwnerOnly() async throws {
    try await withLibrary { library, url in
      try await library.create(makeProfile(name: "Primary"))
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      let permissions = try #require(attributes[.posixPermissions] as? Int)
      #expect(permissions & 0o077 == 0)
      let parentAttributes = try FileManager.default.attributesOfItem(
        atPath: url.deletingLastPathComponent().path
      )
      let parentPermissions = try #require(parentAttributes[.posixPermissions] as? Int)
      #expect(parentPermissions & 0o077 == 0)
    }
  }

  private func withLibrary(_ body: @Sendable (RemappingProfileLibrary, URL) async throws -> Void)
    async throws
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("profiles.json")
    try await body(RemappingProfileLibrary(fileURL: url), url)
  }

  private func makeProfile(
    id: UUID = UUID(),
    name: String,
    vendorID: UInt16 = 1118,
    productID: UInt16 = 654
  ) -> RemappingProfile {
    RemappingProfile(
      id: id,
      name: name,
      device: RemappingDeviceScope(vendorID: vendorID, productID: productID),
      applicationScope: .global,
      bindings: []
    )
  }

  private func identifier(last: UInt8) -> UUID {
    UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, last))
  }
}
