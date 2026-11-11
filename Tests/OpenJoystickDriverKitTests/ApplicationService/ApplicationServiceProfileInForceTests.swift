import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// The status carries the profile in force for a controller and the app that selected it.
struct ApplicationServiceProfileInForceTests {
  private static func description(
    _ profileInForce: ApplicationServiceProfileInForce?
  ) -> ApplicationServiceDeviceDescription {
    var device = ApplicationServiceDeviceDescription(
      name: "Pad",
      vendorID: 1,
      productID: 2,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .ojd,
      recordAccessRoute: .rawAccess
    )
    device.profileInForce = profileInForce
    return device
  }

  @Test(arguments: [
    ApplicationServiceProfileInForce(name: "Racing", appID: "com.example.Racer"),
    ApplicationServiceProfileInForce(name: "Everywhere", appID: nil),
    nil,
  ])
  func aDeviceRoundTripsItsProfileInForce(
    profileInForce: ApplicationServiceProfileInForce?
  )
    throws
  {
    let device = Self.description(profileInForce)

    let decoded = try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONEncoder().encode(device)
    )

    #expect(decoded.profileInForce == profileInForce)
  }
}
