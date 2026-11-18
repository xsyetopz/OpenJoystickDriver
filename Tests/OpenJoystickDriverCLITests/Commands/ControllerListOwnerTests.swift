import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

/// `controller list --plain` puts the exclusive owner state, process ID and name after the unit.
@Suite(.serialized)
struct ControllerListOwnerTests {
  @Test
  func plainListPrintsOwnerColumnsAfterUnit() async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(
        id: "pad-1",
        hidInputOwnership: .ownedByAnotherClient,
        inputOwner: USBExclusiveOwner(processID: 11070, name: "steam_osx")
      ),
      ApplicationServiceDeviceDescription.fixture(
        id: "pad-2",
        hidInputOwnership: .ownedByAnotherClient,
        inputOwner: USBExclusiveOwner(processID: nil, name: "AppleUSB20Hub")
      ),
      ApplicationServiceDeviceDescription.fixture(id: "pad-3"),
    ])

    let plain = await service.run(["controller", "list", "--plain"])

    #expect(plain.code == 0, "\(plain.standardError)")
    let rows = plain.standardOutput.split(separator: "\n").map {
      $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    }
    #expect(
      rows.map { Array($0[6...8]) } == [
        ["owned-by-another-client", "11070", "steam_osx"],
        ["owned-by-another-client", "", "AppleUSB20Hub"],
        ["", "", ""],
      ]
    )
  }
}
