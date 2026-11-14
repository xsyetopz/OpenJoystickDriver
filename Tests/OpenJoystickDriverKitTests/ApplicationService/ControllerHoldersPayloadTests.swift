import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct ControllerHoldersPayloadTests {
  @Test(arguments: [ControllerOwnershipObservation.exclusiveHID, .exclusiveRawUSB])
  func activeExclusiveOpenHoldsExclusively(ownership: ControllerOwnershipObservation) {
    #expect(
      ApplicationServiceDeviceDescription.fixture(id: "pad-1", physicalOwnership: ownership)
        .holdsExclusively
    )
  }

  @Test
  func suspendedSessionDoesNotHoldExclusively() {
    #expect(
      !ApplicationServiceDeviceDescription.fixture(
        id: "pad-1",
        physicalOwnership: .exclusiveHID,
        sessionState: .suspended
      ).holdsExclusively
    )
  }

  @Test(arguments: [
    ControllerOwnershipObservation.extensionOwnedUSB, .systemHIDVisible, .systemGamepad, .unknown,
  ])
  func sharedOrForeignOpenDoesNotHoldExclusively(ownership: ControllerOwnershipObservation) {
    #expect(
      !ApplicationServiceDeviceDescription.fixture(id: "pad-1", physicalOwnership: ownership)
        .holdsExclusively
    )
  }

  @Test
  func holdersAndExclusiveStateSurviveWire() throws {
    var device = ApplicationServiceDeviceDescription.fixture(
      id: "pad-1",
      physicalOwnership: .exclusiveHID
    )
    device.holders = [USBExclusiveOwner(processID: 812, name: "Google Chrome He")]

    let decoded = try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONEncoder().encode(device)
    )

    #expect(decoded.holders == device.holders)
    #expect(decoded.holdsExclusively)
  }
}
