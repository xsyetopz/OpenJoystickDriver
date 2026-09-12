import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct JoyConPairProfileTests {
  @Test(arguments: RemappingJoyConGyroSelection.allCases)
  func pairSettingsRoundTripInTheCurrentProfileContract(
    _ selection: RemappingJoyConGyroSelection
  ) throws {
    let profile = RemappingProfile(
      name: "Pair",
      device: RemappingDeviceScope(vendorID: 0x057E, productID: 0x2006),
      applicationScope: .global,
      joyConPair: RemappingJoyConPairSettings(gyroSelection: selection),
      bindings: []
    )

    try profile.validate()
    let data = try JSONEncoder().encode(profile)
    #expect(try JSONDecoder().decode(RemappingProfile.self, from: data) == profile)
  }

  @Test
  func pairSettingsRejectAnyNonLeftJoyConProfileModel() {
    let profile = RemappingProfile(
      name: "Wrong model",
      device: RemappingDeviceScope(vendorID: 0x057E, productID: 0x2007),
      applicationScope: .global,
      joyConPair: RemappingJoyConPairSettings(),
      bindings: []
    )

    #expect(throws: RemappingValidationError.invalidJoyConPairDevice) { try profile.validate() }
  }
}
