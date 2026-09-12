import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct RuntimeExtraButtonTests {
  @Test(arguments: [
    ("left_function", RemappingButton.leftFunction),
    ("right_function", RemappingButton.rightFunction),
    ("left_paddle", RemappingButton.leftPaddle),
    ("right_paddle", RemappingButton.rightPaddle),
    ("left_sl", RemappingButton.leftSL),
    ("left_sr", RemappingButton.leftSR),
    ("right_sl", RemappingButton.rightSL),
    ("right_sr", RemappingButton.rightSR),
    ("leftGrip", RemappingButton.leftGrip),
    ("rightGrip", RemappingButton.rightGrip),
    ("leftPadClick", RemappingButton.leftPadClick),
    ("rightPadClick", RemappingButton.rightPadClick)
  ]) func captureAndAuthoringExposeInputOnlyButtons(raw: String, button: RemappingButton) {
    var state = DeviceInputState(vendorID: 1, productID: 2)
    state.pressedButtons = [raw]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(button))
    #expect(SourceOption.options().contains { $0.source == .button(button) })
    let destinations = DestinationOption.options(
      for: .button(button), including: .gamepadButton(button)
    )
    #expect(!destinations.contains { $0.destination == .gamepadButton(button) })
    #expect(destinations.contains { $0.destination == .keyboard(key: .space, modifiers: []) })
  }
}
