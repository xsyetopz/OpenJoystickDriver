import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

extension InputTestTests {
  @Test
  @MainActor
  func motionAndLightingAreHiddenWithoutTheirCapability() {
    let model = InputTestViewModel(gateway: InputTestGatewayStub())
    model.selectDevice(makeInputTestDevice())
    #expect(model.visibleSections == [.liveInput, .rumble])
  }

  @Test
  @MainActor
  func motionShowsWithGyroscopeAndLightingWithLightingFeature() {
    let model = InputTestViewModel(gateway: InputTestGatewayStub())
    model.selectDevice(
      makeInputTestDevice(
        capabilities: PhysicalControllerOutputCapabilities(
          rumbleMotors: [.lowFrequency],
          lightingFeatures: [.programmableColor]
        ),
        hasMotion: true
      )
    )
    #expect(model.visibleSections == [.liveInput, .motion, .rumble, .lighting])
  }
}

extension InputTestTests {
  @Test
  @MainActor
  func rumbleDurationReachesServiceMaximumAndNoFurther() {
    #expect(InputTestViewModel.rumbleDurationRange == 100...5_000)
    #expect(InputTestViewModel.clampedRumbleDuration(5_000) == 5_000)
    #expect(InputTestViewModel.clampedRumbleDuration(9_000) == 5_000)
    #expect(InputTestViewModel.clampedRumbleDuration(10) == 100)
  }
}
