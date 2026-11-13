import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualHIDProfileOverrideArgumentsTests {
  @Test
  func setRequestWithoutUnitFailsToDecode() throws {
    let encoded = try JSONEncoder().encode(
      LocalServiceRPCVirtualHIDProfileOverrideArguments(
        controller: .model(ControllerModelID(vendorID: 1, productID: 2)),
        profile: "Generic",
        unit: true
      )
    )
    var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["unit"] as? Bool == true)
    object["unit"] = nil
    let withoutUnit = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        LocalServiceRPCVirtualHIDProfileOverrideArguments.self,
        from: withoutUnit
      )
    }
  }

  @Test
  func resetRequestWithoutUnitFailsToDecode() throws {
    let encoded = try JSONEncoder().encode(
      LocalServiceRPCVirtualHIDProfileOverrideResetArguments(
        controller: .model(ControllerModelID(vendorID: 1, productID: 2)),
        unit: true
      )
    )
    var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object["unit"] = nil
    let withoutUnit = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        LocalServiceRPCVirtualHIDProfileOverrideResetArguments.self,
        from: withoutUnit
      )
    }
  }
}
