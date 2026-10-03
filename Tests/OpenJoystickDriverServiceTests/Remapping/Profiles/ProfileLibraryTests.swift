import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

struct ProfileLibraryTests {
  @Test
  func missingLibraryStartsEmpty() async throws {
    try await withLibrary { library, directory in
      let profiles = try await library.profiles()
      #expect(profiles.isEmpty)
      #expect(try libraryFiles(in: directory).isEmpty)
    }
  }

  @Test
  func profilesPersistAcrossLibraryInstances() async throws {
    try await withLibrary { library, directory in
      let profile = makeProfile(name: "Primary")
      try await library.create(profile)
      #expect(
        try libraryFiles(in: directory) == [
          "Profiles/\(profile.id.uuidString).json": Data(
            try RemappingProfileFileStore.encodedJSON(profile).utf8
          )
        ]
      )

      let restored = RemappingProfileLibrary(directory: directory)
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
      #expect(!FileManager.default.fileExists(atPath: library.profileURL(original.id).path))
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
    try await withLibrary { library, directory in
      let original = makeProfile(name: "Primary")
      let firstUpdate = makeProfile(id: original.id, name: "First update")
      let staleUpdate = makeProfile(id: original.id, name: "Stale update")
      try await library.create(original)
      try await library.update(firstUpdate, expectedCurrent: original)
      let bytesAfterFirstUpdate = try libraryFiles(in: directory)

      await #expect(throws: RemappingProfileLibraryError.profileUpdateConflict(original.id)) {
        try await library.update(staleUpdate, expectedCurrent: original)
      }

      #expect(try libraryFiles(in: directory) == bytesAfterFirstUpdate)
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
    try await withLibrary { library, directory in
      let first = makeProfile(name: "First")
      let second = makeProfile(name: "Second")
      try await library.create(first)
      try await library.create(second)
      let model = RemappingProfileModel(first.device)
      try writeSelections(
        [
          RemappingPersistedActiveProfile(model: model, profileID: first.id),
          RemappingPersistedActiveProfile(model: model, profileID: second.id),
        ],
        in: directory
      )

      let restored = RemappingProfileLibrary(directory: directory)
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
  func corruptSelectionsArePreservedRatherThanOverwritten() async throws {
    try await withLibrary { library, directory in
      let corrupt = Data("not json".utf8)
      try corrupt.write(to: library.selectionsURL)

      await #expect(throws: RemappingProfileLibraryError.profileRecoveryRequired) {
        try await library.create(makeProfile(name: "Primary"))
      }
      #expect(try libraryFiles(in: directory) == ["ActiveProfiles.json": corrupt])
    }
  }

  @Test
  func validProfilesRemainAvailableWhenAnotherProfileFileIsDamaged() async throws {
    try await withLibrary { library, directory in
      let valid = makeProfile(name: "Valid")
      try await library.create(valid)
      let damagedURL = library.profileURL(UUID())
      let damaged = Data(#"{"name":"Damaged"}"#.utf8)
      try damaged.write(to: damagedURL)

      let restored = RemappingProfileLibrary(directory: directory)
      let snapshot = try await restored.snapshot()
      #expect(snapshot.profiles == [valid])
      let issue = try #require(snapshot.issues.first)
      #expect(snapshot.issues.count == 1)
      #expect(issue.kind == .damagedProfile)
      #expect(try Data(contentsOf: damagedURL) == damaged)
      await #expect(throws: RemappingProfileLibraryError.profileRecoveryRequired) {
        try await restored.create(makeProfile(name: "Other"))
      }

      try await restored.deleteDamagedProfile(issueID: issue.id)
      #expect(try await restored.profiles() == [valid])
      #expect(try await restored.snapshot().issues.isEmpty)
      #expect(!FileManager.default.fileExists(atPath: damagedURL.path))
      let backups = try libraryFiles(in: directory).filter {
        $0.key.hasPrefix("Profiles/\(damagedURL.lastPathComponent).backup-")
      }
      #expect(Array(backups.values) == [damaged])
      #expect(try await RemappingProfileLibrary(directory: directory).profiles() == [valid])
    }
  }

  @Test
  func profileFileNamedForAnotherIdentifierIsDamaged() async throws {
    try await withLibrary { library, _ in
      let profile = makeProfile(name: "Misnamed")
      try FileManager.default.createDirectory(
        at: library.profilesDirectory,
        withIntermediateDirectories: true
      )
      try RemappingProfileFileStore.write(profile, to: library.profileURL(UUID()))
      try RemappingProfileFileStore.write(
        profile,
        to: library.profilesDirectory.appendingPathComponent(
          profile.id.uuidString.lowercased() + ".json"
        )
      )

      let snapshot = try await library.snapshot()
      #expect(snapshot.profiles.isEmpty)
      #expect(snapshot.issues.map(\.kind) == [.damagedProfile, .damagedProfile])
    }
  }

  @Test
  func selectionsOfDamagedOrMissingProfilesAreDropped() async throws {
    try await withLibrary { library, directory in
      let valid = makeProfile(name: "Valid")
      let damaged = makeProfile(name: "Damaged", vendorID: 1356, productID: 2508)
      let missing = makeProfile(name: "Missing", vendorID: 1406, productID: 8201)
      try await library.create(valid)
      try Data("{}".utf8).write(to: library.profileURL(damaged.id))
      try writeSelections(
        [valid, damaged, missing].map {
          RemappingPersistedActiveProfile(model: RemappingProfileModel($0.device), profileID: $0.id)
        },
        in: directory
      )

      let restored = RemappingProfileLibrary(directory: directory)
      let issue = try #require(try await restored.snapshot().issues.first)
      try await restored.deleteDamagedProfile(issueID: issue.id)
      let repaired = try await restored.snapshot()

      #expect(repaired.profiles == [valid])
      #expect(repaired.activeProfiles.map(\.profileID) == [valid.id])
      #expect(repaired.issues.isEmpty)
    }
  }

  @Test
  func damagedProfileIssueIdentifiersAreRejectedAfterRepair() async throws {
    try await withLibrary { library, _ in
      try FileManager.default.createDirectory(
        at: library.profilesDirectory,
        withIntermediateDirectories: true
      )
      try Data("{}".utf8).write(to: library.profileURL(UUID()))
      let issue = try #require(try await library.snapshot().issues.first)
      try await library.deleteDamagedProfile(issueID: issue.id)
      await #expect(throws: RemappingProfileLibraryError.profileIssueNotFound(issue.id)) {
        try await library.deleteDamagedProfile(issueID: issue.id)
      }
    }
  }

  @Test
  func recoveryIdentifierIsRejectedWhenTheFileChangesOnDisk() async throws {
    try await withLibrary { library, _ in
      try Data("not json".utf8).write(to: library.selectionsURL)
      let issue = try #require(try await library.snapshot().issues.first)
      let replacement = Data("[]".utf8)
      try replacement.write(to: library.selectionsURL, options: .atomic)

      await #expect(throws: RemappingProfileLibraryError.profileIssueNotFound(issue.id)) {
        try await library.resetDamagedLibrary(issueID: issue.id)
      }
      #expect(try Data(contentsOf: library.selectionsURL) == replacement)
    }
  }

  @Test
  func malformedSelectionsCanBeBackedUpAndResetKeepingProfiles() async throws {
    try await withLibrary { library, directory in
      let profile = makeProfile(name: "Primary")
      try await library.create(profile)
      let malformed = Data(#"{"profiles":[],"schemaVersion":2}"#.utf8)
      try malformed.write(to: library.selectionsURL)

      let restored = RemappingProfileLibrary(directory: directory)
      let issue = try #require(try await restored.snapshot().issues.first)
      #expect(issue.kind == .unusableLibrary)
      await #expect(throws: RemappingProfileLibraryError.corruptLibrary) {
        try await restored.activeProfile(vendorID: 1118, productID: 654)
      }
      try await restored.resetDamagedLibrary(issueID: issue.id)

      let reset = try await restored.snapshot()
      #expect(reset.profiles == [profile])
      #expect(reset.issues.isEmpty)
      #expect(try Data(contentsOf: library.selectionsURL) == Data("[]".utf8))
      let backups = try libraryFiles(in: directory).filter {
        $0.key.hasPrefix("ActiveProfiles.json.backup-")
      }
      #expect(Array(backups.values) == [malformed])
    }
  }

  @Test
  func legacyLibraryIsIgnoredAndDiscarded() async throws {
    try await withLibrary { library, directory in
      let legacyURL = directory.appendingPathComponent("RemappingProfiles.json")
      let profile = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(makeProfile(name: "Primary"))
      )
      try JSONSerialization.data(withJSONObject: ["profiles": [profile], "activeProfiles": []])
        .write(to: legacyURL)

      let snapshot = try await library.snapshot()
      #expect(snapshot.profiles.isEmpty)
      #expect(snapshot.issues.isEmpty)
      library.discardLegacyLibrary()
      #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
    }
  }

  @Test
  func reloadReportsModelsWhoseActiveProfilesChanged() async throws {
    try await withLibrary { library, _ in
      let active = makeProfile(name: "Active")
      let inactive = makeProfile(name: "Inactive", vendorID: 1356, productID: 2508)
      try await library.create(active)
      try await library.create(inactive)
      try await library.activate(profileID: active.id)
      #expect(try await library.reload().isEmpty)

      let editedInactive = makeProfile(
        id: inactive.id,
        name: "Edited",
        vendorID: 1356,
        productID: 2508
      )
      try RemappingProfileFileStore.write(editedInactive, to: library.profileURL(inactive.id))
      #expect(try await library.reload().isEmpty)
      #expect(try await library.profile(id: inactive.id) == editedInactive)

      let editedActive = makeProfile(id: active.id, name: "Changed")
      try RemappingProfileFileStore.write(editedActive, to: library.profileURL(active.id))
      #expect(try await library.reload() == [RemappingProfileModel(active.device)])
      #expect(try await library.activeProfile(vendorID: 1118, productID: 654) == editedActive)

      let added = makeProfile(name: "Added", vendorID: 1406, productID: 8201)
      try RemappingProfileFileStore.write(added, to: library.profileURL(added.id))
      #expect(try await library.reload().isEmpty)
      #expect(try await library.profile(id: added.id) == added)

      try FileManager.default.removeItem(at: library.profileURL(active.id))
      #expect(try await library.reload() == [RemappingProfileModel(active.device)])
      #expect(try await library.activeProfile(vendorID: 1118, productID: 654) == nil)
    }
  }

  @Test
  func reloadKeepsIssueIdentifiers() async throws {
    try await withLibrary { library, _ in
      try Data("not json".utf8).write(to: library.selectionsURL)
      let issue = try #require(try await library.snapshot().issues.first)
      _ = try await library.reload()
      #expect(try await library.snapshot().issues.map(\.id) == [issue.id])
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
  func savedFilesAndDirectoriesAreOwnerOnly() async throws {
    try await withLibrary { library, directory in
      let profile = makeProfile(name: "Primary")
      try await library.create(profile)
      try await library.activate(profileID: profile.id)
      for url in [
        directory, library.profilesDirectory, library.profileURL(profile.id),
        library.selectionsURL,
      ] {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try #require(attributes[.posixPermissions] as? Int)
        #expect(permissions & 0o077 == 0)
      }
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
    try await body(RemappingProfileLibrary(directory: directory), directory)
  }

  func writeSelections(_ selections: [RemappingPersistedActiveProfile], in directory: URL) throws {
    try JSONEncoder().encode(selections).write(
      to: directory.appendingPathComponent("ActiveProfiles.json")
    )
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
