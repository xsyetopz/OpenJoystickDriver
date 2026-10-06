import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerOutputCommandTests {
  @Test
  func protocolBytesRoundTripThroughUnipolarValues() {
    for byte in UInt8.min...UInt8.max {
      #expect(UnipolarValue(byte: byte).rawValue == UInt16(byte) * 257)
      #expect(UnipolarValue(byte: byte).byte == byte)
      // Ownership keeps the saved-profile intensity and arbitration converts it back.
      let value = UnipolarValue(byte: byte)
      #expect(UnipolarValue(unitInterval: value.unitInterval) == value)
    }
    #expect(UnipolarValue.max.byte == 255)
    #expect(UnipolarValue(128).byte == 0)
    #expect(UnipolarValue(129).byte == 1)
  }

  @Test
  func unitIntervalIntensitiesSpanTheFullRangeAndClamp() {
    #expect(UnipolarValue(unitInterval: 0) == .min)
    #expect(UnipolarValue(unitInterval: 1) == .max)
    #expect(UnipolarValue(unitInterval: 0.5).rawValue == 32_768)
    #expect(UnipolarValue(unitInterval: -0.25) == .min)
    #expect(UnipolarValue(unitInterval: 1.5) == .max)
    #expect(UnipolarValue.max.unitInterval == 1)
  }

  @Test
  func partialRumbleZeroesAndReportsTheChannelsTheControllerLacks() throws {
    let mains = PhysicalControllerOutputCapabilities.dualMainRumble
    let requested = RumbleIntensities(
      leftMain: UnipolarValue(byte: 0x40),
      rightMain: .min,
      leftTrigger: UnipolarValue(byte: 0x20),
      rightHaptic: .max
    )
    let admitted = try mains.admit(.setRumble(requested, duration: .held))
    #expect(
      admitted.command
        == .setRumble(RumbleIntensities(leftMain: UnipolarValue(byte: 0x40)), duration: .held)
    )
    #expect(admitted.droppedRumbleChannels == [.leftTrigger, .rightHaptic])

    let triggersOnly = RumbleIntensities(leftTrigger: .max, rightTrigger: .max)
    let dropped = try mains.admit(.setRumble(triggersOnly, duration: .milliseconds(0)))
    #expect(dropped.command == .setRumble(.off, duration: .milliseconds(0)))
    #expect(dropped.droppedRumbleChannels == [.leftTrigger, .rightTrigger])
    #expect(try mains.admit(.stopRumble) == (.stopRumble, []))
  }

  @Test
  func commandsWithoutTheirCapabilityAreUnsupported() {
    let none = PhysicalControllerOutputCapabilities.none
    let rumble = RumbleIntensities(rightTrigger: .max)
    let cases: [(ControllerOutputCommand, ControllerOutputCapability)] = [
      (.setRumble(rumble, duration: .held), .rumble(.rightTrigger)),
      (.setRumble(.off, duration: .held), .rumble(.leftMain)), (.stopRumble, .rumble(.leftMain)),
      (.setPlayerIndicator(.player1), .playerIndicator),
      (.setRGB(ControllerColor(red: 1, green: 2, blue: 3)), .rgb),
      (.setLightBrightness(.max), .lightBrightness),
      (.setAdaptiveTrigger(.right, .off), .adaptiveTrigger(.right)),
    ]
    for (command, capability) in cases {
      #expect(throws: ControllerOutputError.unsupportedCapability(capability)) {
        try none.admit(command)
      }
    }
    let leftTrigger = PhysicalControllerOutputCapabilities(adaptiveTriggers: [.left])
    #expect(throws: ControllerOutputError.unsupportedCapability(.adaptiveTrigger(.right))) {
      try leftTrigger.admit(.setAdaptiveTrigger(.right, .off))
    }
    #expect(throws: Never.self) { try leftTrigger.admit(.setAdaptiveTrigger(.left, .off)) }
  }

  @Test
  func driversWithoutAnOutputThrowUnsupportedCapability() {
    #expect(throws: ControllerOutputError.unsupportedCapability(.rgb)) {
      try XIDDriver().encode(.setRGB(ControllerColor(red: 1, green: 2, blue: 3)))
    }
    #expect(throws: ControllerOutputError.unsupportedCapability(.rumble(.leftMain))) {
      try FlydigiDriver().encode(.stopRumble)
    }
    #expect(throws: ControllerOutputError.unsupportedCapability(.lightBrightness)) {
      try DualSenseDriver().encode(.setLightBrightness(.max))
    }
  }

  @Test
  func manualTestRumblesBothMainMotorsOnlyWhenNoChannelIsGiven() {
    let fallback = UnipolarValue(byte: 180)
    #expect(
      RumbleIntensities.manualTest(
        leftMain: nil,
        rightMain: nil,
        leftTrigger: nil,
        rightTrigger: nil
      )
        == RumbleIntensities(leftMain: fallback, rightMain: fallback)
    )
    #expect(
      RumbleIntensities.manualTest(leftMain: nil, rightMain: nil, leftTrigger: 9, rightTrigger: nil)
        == RumbleIntensities(leftTrigger: UnipolarValue(byte: 9))
    )
    #expect(RumbleDuration.maximumSeconds == 5)
  }
}
