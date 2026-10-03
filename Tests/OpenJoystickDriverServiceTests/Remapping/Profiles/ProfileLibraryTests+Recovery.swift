import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension ProfileLibraryTests {
  @Test
  func profileWithRemovedGyroFieldIsRecoveredAsDamaged() async throws {
    try await withLibrary { library, _ in
      let valid = makeProfile(name: "Valid")
      let legacy = makeProfile(name: "Legacy")
      try await library.create(valid)
      var legacyObject = try #require(
        JSONSerialization.jsonObject(
          with: Data(RemappingProfileFileStore.encodedJSON(legacy).utf8)
        ) as? [String: Any]
      )
      legacyObject["gyroOutput"] = ["mode": "mouse", "virtualMotion": true]
      try JSONSerialization.data(withJSONObject: legacyObject)
        .write(to: library.profileURL(legacy.id))
      _ = try await library.reload()

      let snapshot = try await library.snapshot()

      #expect(snapshot.profiles == [valid])
      #expect(snapshot.issues.map(\.kind) == [.damagedProfile])
    }
  }
}
