import Foundation
import OpenJoystickDriverKit
import Testing

struct PhysicalOutputValidationPlanTests {
  @Test
  func buildsCapabilityDrivenRedactedSteps() throws {
    let device = XPCDeviceDescription(
      name: "Secret Controller Name",
      vendorID: 1234,
      productID: 5678,
      parser: "GIP",
      connection: "USB",
      serialNumber: "SERIAL-SECRET",
      supportsPhysicalRumble: true,
      physicalOutputCapabilities: PhysicalControllerOutputCapabilities(
        rumbleMotors: [.leftMain, .rightMain, .leftTrigger, .rightTrigger],
        lightingFeatures: [.playerIndicator, .programmableColor, .programmableBrightness],
        evidence: .sourceBacked
      )
    )
    let plan = PhysicalOutputValidationPlan(device: device)
    #expect(plan.steps.map(\.id) == [
      "left-main", "right-main", "left-trigger", "right-trigger",
      "player-indicators", "player-indicators-off", "color-red", "color-green",
      "color-blue", "brightness-low", "brightness-high",
    ])
    let firstCommand = "OpenJoystickDriver --headless physical-output rumble 1234 5678"
      + " --left 160 --right 0 --duration-ms 300"
    #expect(plan.steps.first?.command == firstCommand)
    #expect(plan.evidence == .sourceBacked)
    let json = try #require(String(data: plan.encodedJSON(), encoding: .utf8))
    #expect(!json.contains("Secret Controller Name"))
    #expect(!json.contains("SERIAL-SECRET"))
    #expect(!json.contains("3735928559"))
    #expect(!json.contains("/Users/"))
  }

  @Test
  func usesHapticLabelsAndProducesNoUnsupportedSteps() {
    let haptics = PhysicalOutputValidationPlan(
      vendorID: 10,
      productID: 20,
      parser: "Steam",
      capabilities: PhysicalControllerOutputCapabilities(
        rumbleMotors: [.leftHaptic, .rightHaptic]
      )
    )
    #expect(haptics.steps.map(\.id) == ["left-haptic", "right-haptic"])
    #expect(haptics.steps[0].expectedObservation.contains("left trackpad"))
    let unavailable = PhysicalOutputValidationPlan(
      vendorID: 10,
      productID: 21,
      parser: "Unknown",
      capabilities: PhysicalControllerOutputCapabilities()
    )
    #expect(unavailable.steps.isEmpty)
    #expect(unavailable.evidence == .unavailable)
  }
}
