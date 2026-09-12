import Foundation
import Testing

@testable import OpenJoystickDriver
@testable import OpenJoystickDriverKit

@Suite(.serialized)
struct JoyConCommandTests {
  @Test
  func profileAndExactRuntimeSessionCommandsUseNativeContracts() async throws {
    let client = MockMappingClient(snapshotValue: snapshot([]))
    _ = try await MappingInvocation(arguments: [
      "create", "Pair", "--vid", "0x057e", "--pid", "0x2006", "--global", "--joy-con-pair-gyro",
      "right",
    ]).execute(client: client)
    let created = try #require(await client.submittedProfile)
    #expect(created.joyConPair?.gyroSelection == .right)

    let pairClient = MockMappingClient(snapshotValue: snapshot([created]))
    _ = try await MappingInvocation(arguments: [
      "joy-con", "pair", created.id.uuidString, "--left", "left-runtime", "--right",
      "right-runtime",
    ]).execute(client: pairClient)
    #expect(await pairClient.pairRequest?.left == "left-runtime")
    #expect(await pairClient.pairRequest?.right == "right-runtime")
    #expect(await pairClient.pairRequest?.profileID == created.id)

    let sessionID = UUID()
    _ = try await MappingInvocation(arguments: [
      "joy-con", "unpair", "--session", sessionID.uuidString,
    ]).execute(client: pairClient)
    #expect(await pairClient.unpairedSessionID == sessionID)
  }

  private func snapshot(
    _ profiles: [RemappingProfile]
  ) -> ApplicationServiceRemappingSnapshotPayload {
    ApplicationServiceRemappingSnapshotPayload(
      profiles: profiles,
      activeProfiles: [],
      routes: [],
      postEventAccess: .granted
    )
  }
}

extension MockMappingClient {
  func pairJoyCons(
    left: String,
    right: String,
    profileID: UUID
  ) -> ApplicationServiceRemappingSnapshotPayload {
    mutationCount += 1
    pairRequest = (left, right, profileID)
    return snapshotValue
  }

  func unpairJoyCons(sessionID: UUID) -> ApplicationServiceRemappingSnapshotPayload {
    mutationCount += 1
    unpairedSessionID = sessionID
    return snapshotValue
  }
}
