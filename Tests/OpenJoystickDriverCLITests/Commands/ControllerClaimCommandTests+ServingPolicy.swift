import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

extension ControllerClaimCommandTests {
  @Test(arguments: ServingFixture.all)
  func cliAcceptsServerChangeExactlyWhenPolicyOffersChoice(_ fixture: ServingFixture) {
    let accepted =
      (try? ControllerServerChange.checkSupported(
        fixture.device,
        server: fixture.server,
        accessRoute: fixture.accessRoute
      )) != nil
    #expect(accepted == fixture.offersServerChoice, "\(fixture.name)")
  }
}
