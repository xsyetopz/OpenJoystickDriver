import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct ControllerOutputRequestsTests {
  private let pad = ApplicationServiceDeviceDescription.fixture(id: "A", name: "Pad A", unit: "P")

  private func failure(_ body: () throws -> Void) -> CodedFailure? {
    do { try body() } catch { return error as? CodedFailure }
    return nil
  }

  @Test
  func theDurationIsAboveZeroAndWithinTheMaximum() {
    #expect(ControllerOutput.isValidRumbleDuration(0.45))
    #expect(ControllerOutput.isValidRumbleDuration(RumbleDuration.maximumSeconds))
    for seconds in [0, -1, RumbleDuration.maximumSeconds + 0.001, .nan, .infinity] {
      #expect(!ControllerOutput.isValidRumbleDuration(seconds), "\(seconds)")
    }
  }

  @Test
  func aRumbleRoundsTheDurationUpToOneMillisecondAndStopsWhenNoMotorIsNamed() {
    let short = ControllerOutput.rumble(
      RumbleIntensities(lowFrequency: UnipolarValue(byte: 1)),
      seconds: 0.0001
    )
    guard case .setRumble(_, let duration) = short.command else {
      Issue.record("not a rumble: \(short.command)")
      return
    }
    #expect(duration == .milliseconds(1))
    #expect(ControllerOutput.rumble(.off, seconds: 1).command == .stopRumble)
  }

  @Test
  func aLightNamesOnlyTheValuesGiven() {
    #expect(ControllerOutput.light(color: nil, brightness: nil).isEmpty)
    #expect(ControllerOutput.light(color: nil, brightness: 3).map(\.name) == ["brightness"])
    #expect(
      ControllerOutput.light(color: ControllerColor(red: 1, green: 2, blue: 3), brightness: 3)
        .map(\.name) == ["color", "brightness"]
    )
  }

  @Test
  func everyOutcomeButDeliveredFailsWithTheControllerRequestFailedCode() throws {
    let request = ControllerOutput.player(.player1)
    try ControllerOutput.check(ControllerOutputResult(.delivered), request, pad)
    for outcome in ControllerOutputResult.Outcome.allCases where outcome != .delivered {
      let thrown = failure { try ControllerOutput.check(ControllerOutputResult(outcome), request, pad) }
      #expect(thrown?.id == .controllerRequestFailed, "\(outcome)")
      #expect(thrown?.message.contains("Pad A") == true, "\(outcome)")
    }
  }

  @Test
  func aRumbleFailsWhenNoRequestedMotorRanAndReportsTheDroppedTriggers() throws {
    let all: [PhysicalRumbleMotor] = [.lowFrequency, .highFrequency, .leftHaptic, .rightHaptic]
    let none = ControllerOutputResult(.delivered, droppedRumbleChannels: all)
    let thrown = failure {
      _ = try ControllerOutput.rumbleOutcome(requested: [.lowFrequency], result: none, device: pad)
    }
    #expect(thrown?.id == .controllerRequestFailed)

    let triggers = ControllerOutputResult(.delivered, droppedRumbleChannels: [.leftTrigger])
    let outcome = try ControllerOutput.rumbleOutcome(
      requested: [.lowFrequency, .leftTrigger],
      result: triggers,
      device: pad
    )
    #expect(outcome.droppedTriggers == [.leftTrigger])
    #expect(outcome.ran == [.lowFrequency])

    let stop = try ControllerOutput.rumbleOutcome(
      requested: [],
      result: ControllerOutputResult(.delivered),
      device: pad
    )
    #expect(stop.ran.isEmpty)
  }

  @Test
  func aReferenceNamesTheOneConnectedControllerOrFailsWithNotFound() throws {
    let other = ApplicationServiceDeviceDescription.fixture(id: "B", name: "Pad B", unit: "Q")
    #expect(try ControllerReference.device(named: token("A"), in: [pad, other]).name == "Pad A")
    #expect(
      try ControllerReference.device(named: ControllerPortKey.fixture("Q").rawValue, in: [pad, other])
        .name == "Pad B"
    )
    #expect(try ControllerReference.device(named: "045E:028E", in: [pad]).name == "Pad A")
    for (text, devices) in [
      ("045E:028E", [pad, other]), ("FFFF:FFFF", [pad]), ("not a reference", [pad]),
      (token("A"), []),
    ] {
      let thrown = failure { _ = try ControllerReference.device(named: text, in: devices) }
      #expect(thrown?.id == .notFound, "\(text)")
    }
  }
}
