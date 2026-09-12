import Foundation
import Testing
@testable import OpenJoystickDriverKit

struct StickProfileTests {
  @Test func profilesPersistMappingsAndRequireSystemInput() throws {
    let profile = makeProfile([RemappingStickMapping(source: .right, mode: .flick)])
    try profile.validate()
    #expect(profile.requiresSystemInputAccess)
    let data = try JSONEncoder().encode(profile)
    #expect(try JSONDecoder().decode(RemappingProfile.self, from: data) == profile)
  }

  @Test func rejectsDuplicateSourcesInvalidMappingsAndOlderSchemas() {
    let mapping = RemappingStickMapping(source: .left)
    #expect(throws: RemappingValidationError.duplicateStickMapping(.left)) {
      try makeProfile([mapping, mapping]).validate()
    }
    #expect(throws: RemappingValidationError.unsupportedSchemaVersion(2)) {
      try makeProfile([mapping], version: 2).validate()
    }
    #expect(throws: RemappingValidationError.invalidStickMapping(.right)) {
      try makeProfile([RemappingStickMapping(source: .right, flickDurationMs: -1)]).validate()
    }
  }

  private func makeProfile(
    _ mappings: [RemappingStickMapping], version: Int = 3
  ) -> RemappingProfile {
    RemappingProfile(
      schemaVersion: version,
      name: "Sticks",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      stickMappings: mappings,
      bindings: []
    )
  }
}
