import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingOutputPolicyTests {
  @Test func alternateAndLayerDestinationsRequireSystemInputAccess() {
    let policy = RemappingOutputPolicy(virtualGamepad: .mapped)
    let system = RemappingDestination.keyboard(key: .space, modifiers: [])
    let virtual = RemappingDestination.gamepadButton(.south)
    let alternatives = [
      RemappingBinding(source: .button(.south), destination: system),
      RemappingBinding(
        source: .button(.south),
        destination: virtual,
        longHold: RemappingLongHold(durationMs: 500, destination: system)
      ),
      RemappingBinding(
        source: .button(.south),
        destination: virtual,
        doubleTap: RemappingDoubleTap(windowMs: 250, destination: system)
      )
    ]
    for binding in alternatives {
      #expect(makeProfile(outputPolicy: policy, bindings: [binding]).requiresSystemInputAccess)
      let layer = RemappingLayer(
        name: "Alternate",
        activationMode: .hold,
        activator: .button(.leftShoulder),
        bindings: [binding]
      )
      #expect(makeProfile(outputPolicy: policy, layers: [layer]).requiresSystemInputAccess)
    }
    let chord = RemappingChord(
      sources: [.button(.south), .button(.east)], destination: system
    )
    let sequence = RemappingSequence(
      sources: [.button(.south), .button(.east)], windowMs: 500, destination: system
    )
    #expect(makeProfile(outputPolicy: policy, chords: [chord]).requiresSystemInputAccess)
    #expect(makeProfile(outputPolicy: policy, sequences: [sequence]).requiresSystemInputAccess)
    #expect(!makeProfile(outputPolicy: policy).requiresSystemInputAccess)
    #expect(makeProfile().requiresSystemInputAccess)
  }

  @Test(arguments: RemappingVirtualGamepadPolicy.allCases)
  func virtualOutputRequiresIsolation(_ virtualGamepad: RemappingVirtualGamepadPolicy) throws {
    let policy = RemappingOutputPolicy(virtualGamepad: virtualGamepad)
    #expect(policy.requiresExclusiveInput == (virtualGamepad != .disabled))
    let profile = makeProfile(outputPolicy: policy)
    try profile.validate()
    let data = try JSONEncoder().encode(profile)
    #expect(try JSONDecoder().decode(RemappingProfile.self, from: data) == profile)
  }

  @Test func systemInputCanRequireExclusiveOwnership() {
    let policy = RemappingOutputPolicy(physicalInput: .exclusive)
    #expect(policy.virtualGamepad == .disabled)
    #expect(policy.requiresExclusiveInput)
    #expect(!RemappingOutputPolicy.systemInput.requiresExclusiveInput)
  }

  @Test func virtualSteeringRequiresMappedVirtualOutput() throws {
    let stick = RemappingProfile(
      name: "Stick steering",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      stickMappings: [RemappingStickMapping(source: .left, mode: .steering)],
      bindings: []
    )
    #expect(throws: RemappingValidationError.virtualOutputRequired) { try stick.validate() }

    let motion = RemappingProfile(
      name: "Motion steering",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      motionTuning: RemappingMotionTuning(steering: RemappingMotionSteering()),
      bindings: []
    )
    try motion.validate()
    #expect(!motion.requiresSystemInputAccess)
  }

  @Test func versionTwoIsRejectedAtValidationAndDecode() throws {
    let profile = makeProfile(schemaVersion: 2)
    #expect(throws: RemappingValidationError.unsupportedSchemaVersion(2)) {
      try profile.validate()
    }
    let data = try JSONEncoder().encode(profile)
    #expect(throws: RemappingValidationError.unsupportedSchemaVersion(2)) {
      try JSONDecoder().decode(RemappingProfile.self, from: data)
    }
  }

  @Test func unknownOutputPolicyIsRejected() throws {
    let data = try JSONEncoder().encode(makeProfile())
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["output_policy"] = ["virtual_gamepad": "future", "physical_input": "shared"]
    let invalid = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(RemappingProfile.self, from: invalid)
    }
  }

  private func makeProfile(
    schemaVersion: Int = RemappingProfile.currentSchemaVersion,
    outputPolicy: RemappingOutputPolicy = .systemInput,
    bindings: [RemappingBinding] = [],
    chords: [RemappingChord] = [],
    sequences: [RemappingSequence] = [],
    layers: [RemappingLayer] = []
  ) -> RemappingProfile {
    RemappingProfile(
      schemaVersion: schemaVersion,
      name: "Output",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: outputPolicy,
      bindings: bindings,
      chords: chords,
      sequences: sequences,
      layers: layers
    )
  }
}
