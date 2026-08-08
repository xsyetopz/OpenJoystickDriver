import SwifterKit
import Testing

@testable import OpenJoystickDriverRelay

struct DriverTests {
  @Test func ordinaryOutputEchoesAsInput() throws {
    let output = HIDReport(bytes: [1, 2, 3], type: .output, options: 7, timestamp: 42)
    let input = try #require(OpenJoystickRelayDriver.forwardedInput(for: output))

    #expect(input == HIDReport(bytes: [1, 2, 3], type: .input, options: 7, timestamp: 42))
  }

  @Test func framedOutputMovesReportIDIntoOptions() throws {
    let output = HIDReport(bytes: [0x4F, 0x4A, 9, 1, 2], type: .output)
    let input = try #require(OpenJoystickRelayDriver.forwardedInput(for: output))

    #expect(input.bytes == [1, 2])
    #expect(input.options == 9)
    #expect(input.type == .input)
  }

  @Test func emptyFramedPayloadIsRejectedWithoutSubmission() {
    #expect(
      OpenJoystickRelayDriver.forwardedInput(for: HIDReport(bytes: [0x4F, 0x4A, 9], type: .output))
        == nil
    )
    #expect(OpenJoystickRelayDriver.forwardedInput(for: HIDReport(bytes: [], type: .output)) == nil)
  }

  @Test func featureAndInputReportsDoNotEmitInput() {
    #expect(
      OpenJoystickRelayDriver.forwardedInput(for: HIDReport(bytes: [1], type: .feature)) == nil
    )
    #expect(OpenJoystickRelayDriver.forwardedInput(for: HIDReport(bytes: [1], type: .input)) == nil)
  }
}
