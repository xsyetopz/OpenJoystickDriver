import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct ProfileRegionDraftTests {
  @Test
  func stickDraftBuildsRingWithAndWithoutSector() throws {
    var draft = ProfileRegionDraft()
    #expect(
      try draft.source()
        == .stickRegion(
          RemappingStickRegionSource(stick: .left, innerRadius: 0.8, outerRadius: 1)
        )
    )
    draft.innerRadius = "0,5"
    draft.fromDegrees = "315"
    draft.toDegrees = "45"
    #expect(
      try draft.source(decimalSeparator: ",")
        == .stickRegion(
          RemappingStickRegionSource(
            stick: .left,
            innerRadius: 0.5,
            outerRadius: 1,
            fromDegrees: 315,
            toDegrees: 45
          )
        )
    )
  }

  @Test
  func triggerAndTouchDraftsBuildTheirSources() throws {
    var draft = ProfileRegionDraft()
    draft.kind = .trigger
    draft.trigger = .right
    #expect(
      try draft.source()
        == .triggerBand(RemappingTriggerBandSource(trigger: .right, from: 0.5, to: 1))
    )
    draft.kind = .touch
    draft.surface = .left
    #expect(
      try draft.source()
        == .touchArea(
          RemappingTouchAreaSource(surface: .left, x: 0, y: 0, width: 0.5, height: 0.5)
        )
    )
  }

  @Test
  func unreadableNumbersNameTheKind() {
    var draft = ProfileRegionDraft()
    draft.outerRadius = "abc"
    #expect(throws: RemappingValidationError.invalidStickRegion) { try draft.source() }
    draft.outerRadius = "1"
    draft.fromDegrees = "10"
    draft.toDegrees = "x"
    #expect(throws: RemappingValidationError.invalidStickRegion) { try draft.source() }
    draft.kind = .trigger
    draft.to = ""
    #expect(throws: RemappingValidationError.invalidTriggerBand) { try draft.source() }
    draft.kind = .touch
    draft.width = "wide"
    #expect(throws: RemappingValidationError.invalidTouchArea) { try draft.source() }
  }

  @Test
  func readingsFollowTheInputState() {
    var state = ControllerState(
      leftStick: StickPosition(x: .max, y: .center),
      rightTrigger: UnipolarValue(UInt16.max / 2)
    )
    var draft = ProfileRegionDraft()
    guard
      case .stick(let x, _, let deflection, let degrees) = draft.reading(
        of: state,
        tuning: .default
      )
    else {
      Issue.record("expected a stick reading")
      return
    }
    #expect(x > 0.99 && deflection > 0.99 && abs(degrees - 90) < 0.001)
    draft.kind = .trigger
    draft.trigger = .right
    guard case .trigger(let pull) = draft.reading(of: state, tuning: .default) else {
      Issue.record("expected a trigger reading")
      return
    }
    #expect(abs(pull - 0.5) < 0.001)
    draft.kind = .touch
    #expect(draft.reading(of: state, tuning: .default) == .noContact)
    state.touch = [
      ControllerTouchSample(
        timestamp: MonotonicTimestamp(nanoseconds: 0),
        contacts: [ControllerTouchContact(slot: 0, isActive: true, x: 0, y: .max)]
      )
    ]
    #expect(draft.reading(of: state, tuning: .default) == .touch(x: 0, y: 1))
  }
}
