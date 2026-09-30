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

  @Test
  func switch2LeftJoyConIsAPairableProfileModel() throws {
    let profile = RemappingProfile(
      name: "Switch 2 pair",
      device: RemappingDeviceScope(vendorID: 0x057E, productID: 0x2067),
      applicationScope: .global,
      joyConPair: RemappingJoyConPairSettings(),
      bindings: []
    )

    try profile.validate()
  }

  @Test
  func joyConHalfClassifiesBothGenerationsAndRejectsOtherModels() {
    #expect(JoyConHalf(vendorID: 0x057E, productID: 0x2006) == .left)
    #expect(JoyConHalf(vendorID: 0x057E, productID: 0x2067) == .left)
    #expect(JoyConHalf(vendorID: 0x057E, productID: 0x2007) == .right)
    #expect(JoyConHalf(vendorID: 0x057E, productID: 0x2066) == .right)
    #expect(JoyConHalf(vendorID: 0x057E, productID: 0x2069) == nil)
    #expect(JoyConHalf(vendorID: 0x054C, productID: 0x2006) == nil)
    #expect(JoyConHalf.generationProductIDs(forLeft: 0x2067) == [0x2067, 0x2066])
    #expect(JoyConHalf.generationProductIDs(forLeft: 0x2066).isEmpty)
  }
}
