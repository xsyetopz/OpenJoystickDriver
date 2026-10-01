import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

struct ServiceConnectionFailureTests {
  @Test
  func aDuplicateNameSaysWhereToSeeTheNamesInUse() {
    let error = ApplicationServiceRemappingRPCError(
      code: .duplicateName,
      message: "A remapping profile named Pad already exists."
    )

    #expect(
      ServiceConnection.failure(for: error) as? CLIFailure
        == CLIFailure(
          .failure,
          "A profile with that name already exists. 'ojd profile list' shows every profile."
        )
    )
  }

  @Test
  func aServiceMessageEndingInAPeriodIsNotDoubled() {
    let error = ApplicationServiceRemappingRPCError(
      code: .unwritableLibrary,
      message: "The remapping profile library could not be written."
    )

    #expect(
      ServiceConnection.failure(for: error) as? CLIFailure
        == CLIFailure(
          .failure,
          "The service did not complete the request: "
            + "The remapping profile library could not be written. Check it with 'ojd status'."
        )
    )
  }

  @Test(arguments: [(0.5, "0.5s"), (1, "1s"), (10, "10s")])
  func aDurationUsesAUnitSymbolSoNoPluralIsNeeded(seconds: Double, text: String) {
    #expect(seconds.durationText(locale: Locale(identifier: "en_US")) == text)
  }
}
