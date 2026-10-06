import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct ApplicationServiceDeviceDescriptionAppliedTests {
  @Test
  func theOutputOwnerAndTuningSurviveTheWire() throws {
    let tuning = ControllerTuning(stickDeadzone: 0.2, hidStartupRecoveryRounds: 3)
    let device = ApplicationServiceDeviceDescription.fixture(
      id: "pad-1",
      physicalOutputOwner: .macOS,
      tuning: tuning
    )

    let decoded = try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONEncoder().encode(device)
    )

    #expect(decoded.physicalOutputOwner == .macOS)
    #expect(decoded.tuning == tuning)
  }

  @Test
  func aPayloadWithoutTheAppliedFieldsDoesNotDecode() throws {
    let encoded = try JSONEncoder().encode(
      ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    )
    var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object["tuning"] = nil

    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        ApplicationServiceDeviceDescription.self,
        from: JSONSerialization.data(withJSONObject: object)
      )
    }
  }
}
