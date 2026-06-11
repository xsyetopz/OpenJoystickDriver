import Testing

@testable import OpenJoystickDriverKit

struct ButtonExtensionsTests {
  @Test
  func testInputTesterUsesTextFallbackForShoulderButtons() {
    #expect(Button.l1.inputTesterTextFallback == "L1")
    #expect(Button.r1.inputTesterTextFallback == "R1")
    #expect(Button.leftBumper.inputTesterTextFallback == "LB")
    #expect(Button.rightBumper.inputTesterTextFallback == "RB")
    #expect(Button.a.inputTesterTextFallback == nil)
  }
}
