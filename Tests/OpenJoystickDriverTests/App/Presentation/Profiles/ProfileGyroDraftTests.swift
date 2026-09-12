import OpenJoystickDriverKit
import Testing
@testable import OpenJoystickDriver

struct ProfileGyroDraftTests {
  @Test
  func preservesOutputAndActivation() throws {
    let output = RemappingGyroOutput(
      mode: .rightStick,
      pointerPointsPerDegree: 2.5,
      fullStickDegreesPerSecond: 180,
      activationMode: .toggle,
      activationSource: .button(.south),
      virtualMotion: true
    )
    let draft = ProfileGyroDraft(output)
    #expect(try draft.validatedOutput() == output)
  }

  @Test
  func acceptsLocaleNumbersAndClearsAlwaysActiveSource() throws {
    var draft = ProfileGyroDraft(.default)
    draft.mode = .mouse
    draft.pointerPointsPerDegree = "2,5"
    draft.fullStickDegreesPerSecond = "180,5"
    let output = try draft.validatedOutput(decimalSeparator: ",")
    #expect(output.pointerPointsPerDegree == 2.5)
    #expect(output.fullStickDegreesPerSecond == 180.5)
    #expect(output.activationSource == nil)
  }

  @Test
  func rejectsInvalidNumbersAndContinuousActivation() {
    var draft = ProfileGyroDraft(.default)
    draft.pointerPointsPerDegree = "invalid"
    #expect(throws: RemappingGyroOutputError.self) { try draft.validatedOutput() }
    draft.pointerPointsPerDegree = "-1"
    #expect(throws: RemappingGyroOutputError.self) { try draft.validatedOutput() }
    draft.pointerPointsPerDegree = "1"
    draft.activationMode = .whileHeld
    draft.activationSource = .axis(.leftStickX)
    #expect(throws: RemappingGyroOutputError.self) { try draft.validatedOutput() }
  }
}
