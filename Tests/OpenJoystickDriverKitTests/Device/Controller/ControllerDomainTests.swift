import Testing

@testable import OpenJoystickDriverKit

struct ControllerDomainTests {
  @Test
  func bipolarValueClampsAsymmetricMinimum() {
    #expect(BipolarValue(Int16.min).rawValue == -32767)
    #expect(BipolarValue(-32767).rawValue == -32767)
    #expect(BipolarValue(0) == .center)
    #expect(BipolarValue(Int16.max).rawValue == 32767)
    #expect(BipolarValue.min.rawValue == -BipolarValue.max.rawValue)
  }

  @Test
  func unipolarValueSpansFullUnsignedRange() {
    #expect(UnipolarValue.min.rawValue == 0)
    #expect(UnipolarValue.max.rawValue == 65535)
  }

  @Test
  func monotonicTimestampsOrderByNanoseconds() {
    let earlier = MonotonicTimestamp(nanoseconds: 1)
    let later = MonotonicTimestamp(nanoseconds: 2)
    #expect(earlier < later)
    #expect(!(later < earlier))
    #expect(later == MonotonicTimestamp(nanoseconds: 2))
  }

  @Test
  func controlIDsMatchStandardControlList() {
    let standardControls = [
      "South", "East", "West", "North", "LeftShoulder", "RightShoulder", "LeftTrigger",
      "RightTrigger", "Back", "Start", "LeftStickClick", "RightStickClick", "DpadUp", "DpadDown",
      "DpadLeft", "DpadRight", "Guide", "Capture", "Microphone", "TouchpadClick",
      "LeftPaddle1", "LeftPaddle2", "RightPaddle1", "RightPaddle2",
      "Auxiliary1", "Auxiliary2", "Auxiliary3", "Auxiliary4", "Auxiliary5", "Auxiliary6",
      "Auxiliary7", "Auxiliary8", "LeftStickX", "LeftStickY", "RightStickX", "RightStickY",
      "LeftStickTouch", "RightStickTouch", "LeftTrackpadClick", "RightTrackpadClick",
      "LeftTrackpadTouch", "RightTrackpadTouch", "PointerX", "PointerY", "PointerTracking",
      "LeftGripTouch", "RightGripTouch",
    ]

    #expect(Control.allCases.map(\.rawValue) == standardControls)
  }
}
