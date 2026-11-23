import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

/// The recalibration controls offer only the steps that can apply to the controller.
struct RecalibrationStepsTests {
  @Test
  func controllerWithoutMotionHasNoGyroStep() {
    let actions = ControllerRecalibrationControls.actions(hasMotion: false)
    #expect(actions == [.rest, .circle, .triggers, .reset])
  }

  @Test
  func controllerWithMotionHasGyroStep() {
    let actions = ControllerRecalibrationControls.actions(hasMotion: true)
    #expect(actions == [.rest, .circle, .triggers, .gyro, .reset])
  }
}
