import Testing

@testable import OpenJoystickDriverKit

struct RemappingTransformTests {
  @Test(arguments: [
    (RemappingResponseCurve.linear, 0.5), (RemappingResponseCurve.easeIn, 0.25),
    (RemappingResponseCurve.easeOut, 0.75), (RemappingResponseCurve.smoothStep, 0.5)
  ]) func responseCurvesAreAppliedAfterDeadzone(curve: RemappingResponseCurve, expected: Double) {
    let tuning = RemappingAxisTuning(deadzone: 0, gain: 1, responseCurve: curve)

    #expect(RemappingTransform.value(0.5, tuning: tuning) == expected)
  }

  @Test func deadzoneGainInversionAndBoundsComposeInOrder() {
    let tuning = RemappingAxisTuning(deadzone: 0.2, gain: 3, inverted: true, responseCurve: .linear)

    #expect(abs(RemappingTransform.value(0.2, tuning: tuning)) < 0.000_001)
    #expect(RemappingTransform.value(0.6, tuning: tuning) == -1)
    #expect(abs(RemappingTransform.value(-0.4, tuning: tuning) - 0.75) < 0.000_001)
  }
}
