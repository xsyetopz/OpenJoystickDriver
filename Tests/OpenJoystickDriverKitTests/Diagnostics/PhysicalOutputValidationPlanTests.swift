import Foundation
import OpenJoystickDriverKit
import Testing

struct PhysicalOutputValidationPlanTests {
  @Test
  func buildsCapabilityDrivenRedactedSteps() {
    let device = ApplicationServiceDeviceDescription(
      name: "Secret Controller Name",
      vendorID: 1234,
      productID: 5678,
      protocolBinding: ProtocolBindingID(.xboxGIP, variant: .usb),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: "SERIAL-SECRET",
      bindingResult: .hidDescriptorFixture,
      physicalOutputCapabilities: PhysicalControllerOutputCapabilities(
        rumbleMotors: [.leftMain, .rightMain, .leftTrigger, .rightTrigger],
        lightingFeatures: [.playerIndicator, .programmableColor, .programmableBrightness]
      )
    )
    let plan = PhysicalOutputValidationPlan(device: device)
    #expect(
      plan.steps.map(\.id) == [
        "left-main", "right-main", "left-trigger", "right-trigger", "player-indicators",
        "player-indicators-off", "color-red", "color-green", "color-blue", "brightness-low",
        "brightness-high",
      ]
    )
    #expect(
      plan.steps.first?.command == "ojd controller rumble 04D2:162E --left 160 --duration 0.3"
    )
    #expect(plan.steps.last?.command == "ojd controller light 04D2:162E --brightness 224")
    #expect(plan.notes.allSatisfy { !$0.contains("Secret Controller Name") })
    #expect(plan.notes.allSatisfy { !$0.contains("SERIAL-SECRET") })
  }

  @Test
  func usesHapticLabelsAndProducesNoUnsupportedSteps() {
    let haptics = PhysicalOutputValidationPlan(
      vendorID: 10,
      productID: 20,
      protocolBinding: ProtocolBindingID(.valveSteamController, variant: .wired),
      capabilities: PhysicalControllerOutputCapabilities(rumbleMotors: [.leftHaptic, .rightHaptic])
    )
    #expect(haptics.steps.map(\.id) == ["left-haptic", "right-haptic"])
    let unavailable = PhysicalOutputValidationPlan(
      vendorID: 10,
      productID: 21,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      capabilities: PhysicalControllerOutputCapabilities()
    )
    #expect(unavailable.steps.isEmpty)
  }
}
