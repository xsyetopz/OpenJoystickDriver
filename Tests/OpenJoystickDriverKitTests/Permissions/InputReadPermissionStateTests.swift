import Foundation
import OpenJoystickDriverKit
import Testing

struct InputReadPermissionStateTests {
  @Test
  func accessStateDecodesOnlyItsListedSpellings() throws {
    for state in PermissionManager.AccessState.allCases {
      let data = Data("\"\(state.rawValue)\"".utf8)
      #expect(try JSONDecoder().decode(PermissionManager.AccessState.self, from: data) == state)
    }
  }

  @Test(arguments: ["granted", "GRANTED", "denied", "unknown", "", "Allowed"])
  func accessStateRefusesAnyOtherSpelling(raw: String) {
    #expect(PermissionManager.AccessState(rawValue: raw) == nil)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        PermissionManager.AccessState.self,
        from: Data("\"\(raw)\"".utf8)
      )
    }
  }

  @Test(arguments: ["granted", "Allowed", ""])
  func statusPayloadRefusesInvalidPermissionState(raw: String) throws {
    let valid = ApplicationServiceStatusPayload(
      inputRead: .granted,
      inputInject: .denied,
      connectedDevices: []
    )
    var object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any]
    )
    for field in ["inputRead", "inputInject"] {
      var copy = object
      copy[field] = raw
      let data = try JSONSerialization.data(withJSONObject: copy)
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ApplicationServiceStatusPayload.self, from: data)
      }
    }
    object["inputRead"] = "Granted"
    _ = try JSONDecoder().decode(
      ApplicationServiceStatusPayload.self,
      from: JSONSerialization.data(withJSONObject: object)
    )
  }

  @Test
  func permissionSnapshotRequiresBothStates() {
    #expect(PermissionManager.Snapshot(inputRead: .granted, inputInject: .granted).isReady)
    #expect(!PermissionManager.Snapshot(inputRead: .granted, inputInject: .denied).isReady)
  }

  @Test
  func accessStateHasStableTransportAndDisplayValues() throws {
    let encoded = try JSONEncoder().encode(PermissionManager.AccessState.denied)
    let decoded = try JSONDecoder().decode(PermissionManager.AccessState.self, from: encoded)

    #expect(decoded == .denied)
  }
}
