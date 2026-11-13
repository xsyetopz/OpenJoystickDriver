import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct RuntimePresentationErrorsTests {
  @Test
  func readOnlyPackageProfileShowsLocalizedExplanationWithItsCode() {
    let error = ApplicationServiceRemappingRPCError(
      code: .packageProfileReadOnly,
      message: "A package profile cannot be changed."
    )

    let message = RuntimePresentation.userFacingError(error)

    #expect(
      message
        == OJDLocalized.formatted(
          "ui.error.withCode",
          OJDLocalized.string("error.E3029.message"),
          "E3029"
        )
    )
    #expect(message.contains(OJDLocalized.string("error.E3029.message")))
    #expect(!message.contains(OJDLocalized.string("ui.error.generic")))
    #expect(!message.contains(error.message))
    #expect(message.contains("E3029"))
  }

  @Test
  func upperCamelValueBecomesWordsAndKeyboardKeyLabelIsUnchanged() {
    #expect(
      RuntimePresentation.upperCamelWords(PhysicalRumbleMotor.lowFrequency.rawValue)
        == "Low Frequency"
    )
    #expect(
      RuntimePresentation.upperCamelWords(PhysicalRumbleMotor.leftTrigger.rawValue)
        == "Left Trigger"
    )
    #expect(RuntimePresentation.keyboardKeyLabel(.a) == "KeyA")
    #expect(RuntimePresentation.keyboardKeyLabel(.digit1) == "Digit1")
  }
}
