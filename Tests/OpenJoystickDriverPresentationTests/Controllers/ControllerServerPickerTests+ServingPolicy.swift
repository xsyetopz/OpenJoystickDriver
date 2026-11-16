import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

extension ControllerServerPickerTests {
  @Test(arguments: ServingFixture.all)
  func guiShowsPickerExactlyWhenPolicyOffersChoice(_ fixture: ServingFixture) {
    #expect(
      ControllerServerPicker.isShown(for: fixture.device) == fixture.offersServerChoice,
      "\(fixture.name)"
    )
  }
}
