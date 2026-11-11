import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct ProfilePointerSpeedDraftTests {
  @Test
  func roundTripsAndAcceptsLocaleDecimals() throws {
    let speed = RemappingPointerSpeed(
      driver: RemappingPointerSpeedDriver(type: .stickDepth, side: .right),
      minScale: 0.5,
      maxScale: 2,
      curve: .easeIn
    )
    var draft = ProfilePointerSpeedDraft(speed: speed)
    #expect(try draft.validatedSpeed() == speed)
    draft.maxScale = "2,5"
    #expect(try draft.validatedSpeed(decimalSeparator: ",")?.maxScale == 2.5)
    draft.maxScale = "fast"
    #expect(throws: RemappingValidationError.invalidPointerSpeed) { try draft.validatedSpeed() }
    draft.enabled = false
    #expect(try draft.validatedSpeed() == nil)
    #expect(try ProfilePointerSpeedDraft(speed: nil).validatedSpeed() == nil)
  }

  @Test
  func profileEditSetsClearsAndRejects() throws {
    let profile = RemappingProfile(
      name: "Pointer",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: []
    )
    let speed = RemappingPointerSpeed(
      driver: RemappingPointerSpeedDriver(type: .trigger, side: .left),
      minScale: 1,
      maxScale: 0.25
    )
    let edited = try RuntimeProfileDraft(profile: profile).settingPointerSpeed(speed)
    #expect(edited.profile.pointerSpeed == speed)
    #expect(try edited.settingPointerSpeed(nil).profile.pointerSpeed == nil)
    let tooFast = RemappingPointerSpeed(driver: speed.driver, minScale: 1, maxScale: 11)
    #expect(throws: (any Error).self) { try edited.settingPointerSpeed(tooFast) }
  }

  @Test
  func liveScaleFollowsTheControllerState() {
    let speed = RemappingPointerSpeed(
      driver: RemappingPointerSpeedDriver(type: .trigger, side: .left),
      minScale: 1,
      maxScale: 0.25
    )
    #expect(speed.scale(for: ControllerState()) == 1)
    #expect(speed.scale(for: ControllerState(leftTrigger: .max)) == 0.25)
  }
}
