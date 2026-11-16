import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ApplicationServiceRemappingSnapshotPayloadTests {
  @Test
  func packageProfilesRoundTrip() throws {
    let payload = ApplicationServiceRemappingSnapshotPayload(
      profiles: [],
      activeProfiles: [],
      routes: [],
      packageProfiles: [
        ApplicationServiceRemappingPackageProfile(profileID: UUID(), package: "arcade-pack")
      ],
      postEventAccess: .granted
    )

    let decoded = try JSONDecoder().decode(
      ApplicationServiceRemappingSnapshotPayload.self,
      from: try JSONEncoder().encode(payload)
    )

    #expect(decoded == payload)
  }

  @Test
  func lastUsedRoundTrips() throws {
    let payload = ApplicationServiceRemappingSnapshotPayload(
      profiles: [],
      activeProfiles: [],
      routes: [],
      lastUsed: [ApplicationServiceRemappingProfileUse(profileID: UUID(), usedAt: 1_700_000_000.5)],
      postEventAccess: .granted
    )

    let decoded = try JSONDecoder().decode(
      ApplicationServiceRemappingSnapshotPayload.self,
      from: try JSONEncoder().encode(payload)
    )

    #expect(decoded == payload)
  }

  /// Every list is required, so a payload without one fails to decode instead of listing none.
  @Test(arguments: ["joyConPairs", "profileIssues", "packageProfiles", "lastUsed"])
  func missingListFailsToDecode(key: String) throws {
    let payload = ApplicationServiceRemappingSnapshotPayload(
      profiles: [],
      activeProfiles: [],
      routes: [],
      postEventAccess: .granted
    )
    var object = try #require(
      try JSONSerialization.jsonObject(with: try JSONEncoder().encode(payload)) as? [String: Any]
    )
    #expect(object.removeValue(forKey: key) != nil)
    let data = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(ApplicationServiceRemappingSnapshotPayload.self, from: data)
    }
  }
}
