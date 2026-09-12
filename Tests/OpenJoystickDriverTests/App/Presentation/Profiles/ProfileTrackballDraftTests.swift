import OpenJoystickDriverKit
import Testing
@testable import OpenJoystickDriver

struct ProfileTrackballDraftTests {
  @Test func gyroSheetPreservesTrackballAndAcceptsLocaleDecay() throws {
    let settings = RemappingGyroTrackball(
      source: .button(.west), axes: .pitch, decayHalvingsPerSecond: 2, consumesSource: false
    )
    let output = RemappingGyroOutput(mode: .mouse, trackball: settings)
    var draft = ProfileGyroDraft(output)
    #expect(try draft.validatedOutput() == output)
    draft.trackball.decay = "1,5"
    let edited = try draft.validatedOutput(decimalSeparator: ",")
    #expect(edited.trackball?.decayHalvingsPerSecond == 1.5)
    #expect(edited.trackball?.axes == .pitch)
    #expect(edited.trackball?.consumesSource == false)
    draft.trackball.decay = "invalid"
    #expect(throws: RemappingGyroOutputError.self) { try draft.validatedOutput() }
    draft.trackball.enabled = false
    #expect(try draft.validatedOutput().trackball == nil)
  }
}
