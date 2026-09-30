import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

struct ProfileLibraryTests {
  @Test
  func missingLibraryStartsEmpty() async throws {
    try await withLibrary { library, url in
      let profiles = try await library.profiles()
      #expect(profiles.isEmpty)
      #expect(!FileManager.default.fileExists(atPath: url.path))
    }
  }

  @Test
  func profilesPersistAcrossLibraryInstances() async throws {
    try await withLibrary { library, url in
      let profile = makeProfile(name: "Primary")
      try await library.create(profile)

      let restored = RemappingProfileLibrary(fileURL: url)
      let restoredProfiles = try await restored.profiles()
      #expect(restoredProfiles == [profile])
    }
  }

  @Test
  func createUpdateAndDeleteUseProfileIdentifiers() async throws {
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

  @Test
  func namesAreUniqueWithoutCaseSensitivity() async throws {
    try await withLibrary { library, _ in
      try await library.create(makeProfile(name: "Primary"))
      await #expect(throws: RemappingProfileLibraryError.duplicateName("primary")) {
        try await library.create(makeProfile(name: "primary"))
      }
    }
  }

  @Test
  func staleExpectedProfileIsRejectedWithoutChangingBytesOrCache() async throws {
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

  @Test
  func importPreservesActivationOnlyWhenModelIsUnchanged() async throws {
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

  @Test
  func invalidProfilesAreRejectedWithoutMutation() async throws {
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

  @Test
  func activationIsIsolatedByModelAndCanBeDeactivated() async throws {
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

  @Test
  func activatingReplacesActiveProfileWithSameModelAndScope() async throws {
    try await withLibrary { library, _ in
      let first = makeProfile(name: "First")
      let second = makeProfile(name: "Second")
      try await library.create(first)
      try await library.create(second)

      try await library.activate(profileID: first.id)
      try await library.activate(profileID: second.id)

      let snapshot = try await library.snapshot()
      #expect(snapshot.activeProfiles.map(\.profileID) == [second.id])
    }
  }

  @Test
  func loadingDuplicateActiveEntriesKeepsTheLastPerModelAndScope() async throws {
    try await withLibrary { library, url in
      let first = makeProfile(name: "First")
      let second = makeProfile(name: "Second")
      try await library.create(first)
      try await library.create(second)
      let model = RemappingProfileModel(first.device)
      let state = RemappingProfileLibraryState(
        profiles: [first, second],
        activeProfiles: [
          RemappingPersistedActiveProfile(model: model, profileID: first.id),
          RemappingPersistedActiveProfile(model: model, profileID: second.id),
        ]
      )
      try JSONEncoder().encode(state).write(to: url)

      let restored = RemappingProfileLibrary(fileURL: url)
      let snapshot = try await restored.snapshot()
      #expect(snapshot.activeProfiles.map(\.profileID) == [second.id])
      let active = try await restored.activeProfile(vendorID: 1118, productID: 654)
      #expect(active == second)
      #expect(snapshot.issues.isEmpty)
    }
  }

  @Test
  func deletingProfileClearsItsActiveSelection() async throws {
    try await withLibrary { library, _ in
      let profile = makeProfile(name: "Primary")
      try await library.create(profile)
      try await library.activate(profileID: profile.id)
      try await library.delete(id: profile.id)
      let active = try await library.activeProfile(vendorID: 1118, productID: 654)
      #expect(active == nil)
    }
  }

  @Test
  func corruptLibraryIsPreservedRatherThanOverwritten() async throws {
    try await withLibrary { library, url in
      let corrupt = Data("not json".utf8)
      try corrupt.write(to: url)

      await #expect(throws: RemappingProfileLibraryError.profileRecoveryRequired) {
        try await library.create(makeProfile(name: "Primary"))
      }
      let preserved = try Data(contentsOf: url)
      #expect(preserved == corrupt)
    }
  }

  @Test
  func validProfilesRemainAvailableWhenAnotherPersistedProfileIsDamaged() async throws {
    try await withLibrary { library, url in
      let valid = makeProfile(name: "Valid")
      let validObject = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any]
      )
      let damaged: [String: Any] = ["name": "Damaged"]
      let data = try JSONSerialization.data(withJSONObject: [
        "profiles": [validObject, damaged], "activeProfiles": [],
      ])
      try data.write(to: url)

      let snapshot = try await library.snapshot()
      #expect(snapshot.profiles == [valid])
      #expect(snapshot.issues.count == 1)
      #expect(try Data(contentsOf: url) == data)

      try await library.deleteDamagedProfile(issueID: try #require(snapshot.issues.first).id)
      #expect(try await library.profiles() == [valid])
      let files = try FileManager.default.contentsOfDirectory(
        atPath: url.deletingLastPathComponent().path
      )
      #expect(files.contains { $0.hasPrefix("profiles.json.backup-") })
    }
  }

  @Test
  func repairingDamageRetainsOnlyActiveReferencesToSalvagedProfiles() async throws {
    try await withLibrary { library, url in
      let valid = makeProfile(name: "Valid")
      let damaged = makeProfile(name: "Damaged")
      let validObject = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any]
      )
      var damagedObject = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(damaged)) as? [String: Any]
      )
      damagedObject.removeValue(forKey: "name")
      let activeObjects = try [valid, damaged].map {
        try JSONSerialization.jsonObject(
          with: JSONEncoder().encode(
            RemappingPersistedActiveProfile(
              model: RemappingProfileModel($0.device),
              profileID: $0.id,
              applicationScope: $0.applicationScope
            )
          )
        )
      }
      try JSONSerialization.data(withJSONObject: [
        "profiles": [validObject, damagedObject], "activeProfiles": activeObjects,
      ]).write(to: url)

      let damagedIssue = try #require((try await library.snapshot()).issues.first)
      try await library.deleteDamagedProfile(issueID: damagedIssue.id)
      let repaired = try await library.snapshot()

      #expect(repaired.profiles == [valid])
      #expect(repaired.activeProfiles.map(\.profileID) == [valid.id])
      #expect(repaired.issues.isEmpty)
    }
  }

  @Test
  func damagedProfileIssueIdentifiersAreRejectedAfterRepair() async throws {
    try await withLibrary { library, url in
      let data = Data("{\"profiles\":[{}],\"activeProfiles\":[]}".utf8)
      try data.write(to: url)
      let issue = try #require((try await library.snapshot()).issues.first)
      try await library.deleteDamagedProfile(issueID: issue.id)
      await #expect(throws: RemappingProfileLibraryError.profileIssueNotFound(issue.id)) {
        try await library.deleteDamagedProfile(issueID: issue.id)
      }
    }
  }

  @Test
  func recoveryIdentifierIsRejectedWhenTheLibraryChangesOnDisk() async throws {
    try await withLibrary { library, url in
      try Data("not json".utf8).write(to: url)
      let issue = try #require((try await library.snapshot()).issues.first)
      let replacement = try JSONEncoder().encode(RemappingProfileLibraryState())
      try replacement.write(to: url, options: .atomic)

      await #expect(throws: RemappingProfileLibraryError.profileIssueNotFound(issue.id)) {
        try await library.resetDamagedLibrary(issueID: issue.id)
      }
      #expect(try Data(contentsOf: url) == replacement)
    }
  }

  @Test
  func malformedLibraryCanBeBackedUpAndReset() async throws {
    try await withLibrary { library, url in
      let malformed = Data("not json".utf8)
      try malformed.write(to: url)

      let issue = try #require((try await library.snapshot()).issues.first)
      #expect(issue.kind == .unusableLibrary)
      try await library.resetDamagedLibrary(issueID: issue.id)
      #expect((try await library.snapshot()).profiles.isEmpty)
      let files = try FileManager.default.contentsOfDirectory(
        atPath: url.deletingLastPathComponent().path
      )
      #expect(files.contains { $0.hasPrefix("profiles.json.backup-") })
    }
  }

  @Test(arguments: ["schemaVersion", "schema_version"])
  func versionTaggedLibraryIsRejectedWithoutChangingBytes(key: String) async throws {
    try await withLibrary { library, url in
      let original = Data(
        """
        {"profiles":[],"\(key)":2,"activeProfiles":[]}
        """.utf8
      )
      try original.write(to: url)

      let issue = try #require((try await library.snapshot()).issues.first)
      #expect(issue.kind == .unusableLibrary)
      #expect(try Data(contentsOf: url) == original)
      await #expect(throws: RemappingProfileLibraryError.profileRecoveryRequired) {
        try await library.create(makeProfile(name: "Primary"))
      }
      #expect(try Data(contentsOf: url) == original)
    }
  }

  @Test
  func legacyLibraryIsRejectedWithoutRewriting() async throws {
    try await withLibrary { library, url in
      let profile = makeProfile(name: "Primary")
      let encodedProfile = try JSONEncoder().encode(profile)
      let profileObject = try #require(
        JSONSerialization.jsonObject(with: encodedProfile) as? [String: Any]
      )
      let legacyObject: [String: Any] = [
        "schema_version": 1, "profiles": [profileObject], "active_profiles": [],
      ]
      let original = try JSONSerialization.data(withJSONObject: legacyObject)
      try original.write(to: url)

      let issue = try #require((try await library.snapshot()).issues.first)
      #expect(issue.kind == .unusableLibrary)
      #expect(try Data(contentsOf: url) == original)
    }
  }

  @Test
  func listingUsesDeterministicNameThenIdentifierOrder() async throws {
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

  @Test
  func savedLibraryAndParentAreOwnerOnly() async throws {
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

  func withLibrary(
    _ body: @Sendable (RemappingProfileLibrary, URL) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("profiles.json")
    try await body(RemappingProfileLibrary(fileURL: url), url)
  }

  func makeProfile(
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
