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

    let failure = ServiceConnection.failure(for: error) as? CLIFailure
    #expect(failure?.id == .duplicateName)
    #expect(failure?.message.contains("ojd profile list") == true)
  }

  @Test
  func aServiceMessageEndingInAPeriodIsNotDoubled() {
    let error = ApplicationServiceRemappingRPCError(
      code: .unwritableLibrary,
      message: "The remapping profile library could not be written."
    )

    let failure = ServiceConnection.failure(for: error) as? CLIFailure
    #expect(failure?.id == .unwritableLibrary)
    #expect(failure?.message.contains("ojd status") == true)
    #expect(failure?.message.contains("..") == false)
  }

  @Test(arguments: [(0.5, "0.5s"), (1, "1s"), (10, "10s")])
  func aDurationUsesAUnitSymbolSoNoPluralIsNeeded(seconds: Double, text: String) {
    #expect(seconds.durationText(locale: Locale(identifier: "en_US")) == text)
  }
}
