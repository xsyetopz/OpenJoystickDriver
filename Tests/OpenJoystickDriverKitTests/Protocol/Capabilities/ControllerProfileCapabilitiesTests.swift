import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerProfileCapabilitiesTests {
  @Test
  func exactCatalogLookupDistinguishesKnownAndUnknownControllers() {
    let registry = ProtocolDriverRegistry()
    let dualShock4 = registry.profileCapabilities(
      for: ControllerModelID(vendorID: 0x054C, productID: 0x05C4)
    )

    #expect(dualShock4?.physicalInput.motion == true)
    #expect(dualShock4?.physicalInput.touchContactCount == 2)
    #expect(
      registry.profileCapabilities(for: ControllerModelID(vendorID: 0xFFFF, productID: 0xFFFF))
        == nil
    )
  }

  @Test
  func speakerCapabilityRoundTripsThroughCodableAndIsKeptOnlyWhenShared() throws {
    let wii = PhysicalControllerOutputCapabilities(
      rumbleMotors: [.lowFrequency],
      binaryRumbleMotors: [.lowFrequency],
      speaker: .yamahaADPCM4Bit
    )
    let encoded = try JSONEncoder().encode(wii)
    let decoded = try JSONDecoder().decode(PhysicalControllerOutputCapabilities.self, from: encoded)
    #expect(decoded == wii)
    #expect(
      String(bytes: encoded, encoding: .utf8)?.contains("\"speaker\":\"YamahaADPCM4Bit\"") == true
    )
    #expect(wii.supportsSpeaker)
    #expect(!PhysicalControllerOutputCapabilities.none.supportsSpeaker)
    let none = try JSONDecoder().decode(
      PhysicalControllerOutputCapabilities.self,
      from: Data("{}".utf8)
    )
    #expect(none.speaker == nil)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        PhysicalControllerOutputCapabilities.self,
        from: Data(#"{"speaker":"PCM"}"#.utf8)
      )
    }
    let input = ControllerCapabilities(controls: [])
    let shared = ControllerProfileCapabilities(physicalInput: input, physicalOutput: wii)
    #expect(shared.intersecting(shared).physicalOutput.speaker == .yamahaADPCM4Bit)
    let silent = ControllerProfileCapabilities(physicalInput: input, physicalOutput: .none)
    #expect(shared.intersecting(silent).physicalOutput.speaker == nil)
  }

  @Test
  func intersectionKeepsOnlyCapabilitiesSharedByEveryController() {
    let first = ControllerProfileCapabilities(
      physicalInput: ControllerCapabilities(
        controls: Control.xboxLayout.union([.touchpadClick, .microphone]),
        touchContactCount: 2,
        motion: true
      ),
      physicalOutput: PhysicalControllerOutputCapabilities(
        rumbleMotors: [.lowFrequency, .highFrequency],
        lightingFeatures: [.programmableColor, .programmableBrightness],
        adaptiveTriggers: [.left, .right]
      )
    )
    let second = ControllerProfileCapabilities(
      physicalInput: ControllerCapabilities(
        controls: [.south, .leftTrigger, .touchpadClick],
        touchContactCount: 1
      ),
      physicalOutput: PhysicalControllerOutputCapabilities(
        rumbleMotors: [.highFrequency],
        lightingFeatures: [.programmableColor],
        adaptiveTriggers: [.right]
      )
    )

    let result = first.intersecting(second)
    #expect(!result.physicalInput.motion)
    #expect(result.physicalInput.touchContactCount == 1)
    #expect(result.physicalInput.controls == [.south, .leftTrigger, .touchpadClick])
    #expect(result.physicalInput.touchSurfaces == [.primary])
    #expect(result.physicalOutput.rumbleMotors == [.highFrequency])
    #expect(result.physicalOutput.lightingFeatures == [.programmableColor])
    #expect(result.physicalOutput.adaptiveTriggers == [.right])
    #expect(!result.supportsStickAxes)
    #expect(result.supportsAnalogTriggers)
  }
}
