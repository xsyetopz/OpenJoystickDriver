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

  @Test(arguments: [
    (ApplicationServiceRemappingRPCError.Code.profileUpdateConflict, "ui.error.profileChanged"),
    (.invalidArguments, "ui.error.reviewAssignments"),
    (.profileCountExceeded, "ui.error.profileLibrarySave"),
    (.routerShutDown, "ui.error.remappingUnavailable"),
    (.midiSourceRefused, "ui.error.generic"),
  ])
  func remappingFailureShowsItsMessageWithItsCode(
    _ code: ApplicationServiceRemappingRPCError.Code,
    _ key: String
  ) {
    let error = ApplicationServiceRemappingRPCError(code: code, message: "raw")

    let message = RuntimePresentation.userFacingError(error)

    #expect(
      message
        == OJDLocalized.formatted(
          "ui.error.withCode",
          OJDLocalized.string(key),
          code.errorCode.rawValue
        )
    )
  }

  @Test(arguments: [
    (RemappingKeyboardKey.escape, "escape"),
    (.returnKey, "return"),
    (.deleteBackward, "delete.left"),
    (.pageUp, "arrow.up.to.line"),
    (.end, "arrow.down.to.line.compact"),
  ])
  func specialKeyShowsItsSymbol(_ key: RemappingKeyboardKey, _ symbol: String) {
    #expect(RuntimePresentation.keyboardSystemSymbolName(key) == symbol)
  }

  @Test
  func symbolFallbackCoversOnlyKeysWhoseSymbolVaries() {
    #expect(
      RuntimePresentation.keyboardSystemSymbolFallbackName(.deleteBackward) == "delete.backward"
    )
    #expect(RuntimePresentation.keyboardSystemSymbolFallbackName(.capsLock) == "capslock.fill")
    #expect(RuntimePresentation.keyboardSystemSymbolFallbackName(.escape) == nil)
  }

  @Test
  func letterKeyHasNoSymbol() {
    #expect(RuntimePresentation.keyboardSystemSymbolName(.a) == nil)
    #expect(RuntimePresentation.keyboardSystemSymbolFallbackName(.a) == nil)
  }

  @Test(arguments: [
    RemappingStickMappingError.invalidField("inner_deadzone") as any Error,
    RemappingTriggerMappingError.invalidField("soft_threshold"),
    RemappingMotionTuningError.invalidField("pitch_sensitivity"),
    RemappingGyroOutputError.invalidField("pointer_points_per_degree"),
  ])
  func unreadableAnalogFieldAsksForReviewInsteadOfGenericFailure(_ error: any Error) {
    #expect(
      RuntimePresentation.userFacingError(error)
        == OJDLocalized.string("ui.error.reviewAssignments")
    )
  }
}
