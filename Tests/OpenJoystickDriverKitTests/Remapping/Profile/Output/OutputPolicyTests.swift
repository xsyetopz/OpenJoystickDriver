import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingOutputPolicyTests {
  @Test
  func alternateAndLayerDestinationsRequireSystemInputAccess() {
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
      ),
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
    let chord = RemappingChord(sources: [.button(.south), .button(.east)], destination: system)
    let sequence = RemappingSequence(
      sources: [.button(.south), .button(.east)],
      windowMs: 500,
      destination: system
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

  @Test
  func systemInputCanRequireExclusiveOwnership() {
    let policy = RemappingOutputPolicy(physicalInput: .exclusive)
    #expect(policy.virtualGamepad == .disabled)
    #expect(policy.requiresExclusiveInput)
    #expect(!RemappingOutputPolicy.systemInput.requiresExclusiveInput)
  }

  @Test
  func virtualSteeringRequiresMappedVirtualOutput() throws {
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

  @Test
  func unknownOutputPolicyIsRejected() throws {
    let data = try JSONEncoder().encode(makeProfile())
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["outputPolicy"] = ["virtualGamepad": "future", "physicalInput": "shared"]
    let invalid = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(RemappingProfile.self, from: invalid)
    }
  }

  @Test
  func suppressesAllControllerInputClassifiesEveryOutputFamily() {
    let policy = RemappingOutputPolicy(virtualGamepad: .mapped)
    #expect(makeProfile(outputPolicy: policy).suppressesAllControllerInput)
    #expect(
      makeProfile(
        outputPolicy: policy,
        bindings: [
          RemappingBinding(
            source: .button(.south),
            destination: .keyboard(key: .space, modifiers: [])
          )
        ]
      ).suppressesAllControllerInput
    )
    #expect(
      makeProfile(
        outputPolicy: policy,
        bindings: [
          RemappingBinding(
            source: .button(.south),
            destination: .physical(.color(ControllerColor(red: 1, green: 2, blue: 3)))
          )
        ]
      ).suppressesAllControllerInput
    )
    #expect(
      !makeProfile(
        outputPolicy: policy,
        bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(.south))]
      ).suppressesAllControllerInput
    )
    #expect(
      !RemappingProfile(
        name: "Motion",
        device: RemappingDeviceScope(vendorID: 1, productID: 2),
        applicationScope: .global,
        outputPolicy: policy,
        gyroOutput: RemappingGyroOutput(mode: .leftStick),
        bindings: []
      ).suppressesAllControllerInput
    )
    #expect(
      !RemappingProfile(
        name: "Touch",
        device: RemappingDeviceScope(vendorID: 1, productID: 2),
        applicationScope: .global,
        outputPolicy: policy,
        touchMappings: [RemappingTouchMapping(surface: .primary, mode: .rightStick)],
        bindings: []
      ).suppressesAllControllerInput
    )
    #expect(
      !RemappingProfile(
        name: "Trigger",
        device: RemappingDeviceScope(vendorID: 1, productID: 2),
        applicationScope: .global,
        outputPolicy: policy,
        triggerMappings: [RemappingTriggerMapping(source: .left, passthrough: true)],
        bindings: []
      ).suppressesAllControllerInput
    )
    #expect(
      !makeProfile(
        outputPolicy: policy,
        layers: [
          RemappingLayer(
            name: "Layer",
            activationMode: .hold,
            activator: .button(.leftShoulder),
            bindings: [
              RemappingBinding(source: .button(.south), destination: .gamepadButton(.south))
            ]
          )
        ]
      ).suppressesAllControllerInput
    )
  }

  @Test
  func producesNoOutputCountsEveryOutputFamily() {
    let policy = RemappingOutputPolicy(virtualGamepad: .mapped)
    #expect(makeProfile(outputPolicy: policy).producesNoOutput)
    #expect(!makeProfile().producesNoOutput)
    let passthrough = RemappingOutputPolicy(virtualGamepad: .passthrough)
    #expect(!makeProfile(outputPolicy: passthrough).producesNoOutput)
    let keyboard = RemappingDestination.keyboard(key: .space, modifiers: [])
    let physical = RemappingDestination.physical(.color(ControllerColor(red: 1, green: 2, blue: 3)))
    for destination in [keyboard, physical, .gamepadButton(.south)] {
      let binding = RemappingBinding(source: .button(.south), destination: destination)
      #expect(!makeProfile(outputPolicy: policy, bindings: [binding]).producesNoOutput)
      let layer = RemappingLayer(
        name: "Layer",
        activationMode: .hold,
        activator: .button(.leftShoulder),
        bindings: [binding]
      )
      #expect(!makeProfile(outputPolicy: policy, layers: [layer]).producesNoOutput)
    }
    let chord = RemappingChord(sources: [.button(.south), .button(.east)], destination: keyboard)
    #expect(!makeProfile(outputPolicy: policy, chords: [chord]).producesNoOutput)
    let sequence = RemappingSequence(
      sources: [.button(.south), .button(.east)],
      windowMs: 500,
      destination: physical
    )
    #expect(!makeProfile(outputPolicy: policy, sequences: [sequence]).producesNoOutput)
    #expect(
      !makeProfile(
        outputPolicy: policy,
        bindings: [
          RemappingBinding(
            source: .button(.south),
            destination: .physical(.color(ControllerColor(red: 0, green: 0, blue: 0))),
            longHold: RemappingLongHold(durationMs: 500, destination: keyboard)
          )
        ]
      ).producesNoOutput
    )
    #expect(
      !RemappingProfile(
        name: "Light color",
        device: RemappingDeviceScope(vendorID: 1, productID: 2),
        applicationScope: .global,
        outputPolicy: policy,
        physicalColor: ControllerColor(red: 1, green: 2, blue: 3),
        bindings: []
      ).producesNoOutput
    )
    #expect(
      !RemappingProfile(
        name: "Gyro mouse",
        device: RemappingDeviceScope(vendorID: 1, productID: 2),
        applicationScope: .global,
        outputPolicy: policy,
        gyroOutput: RemappingGyroOutput(mode: .mouse),
        bindings: []
      ).producesNoOutput
    )
    #expect(
      !RemappingProfile(
        name: "Stick mouse",
        device: RemappingDeviceScope(vendorID: 1, productID: 2),
        applicationScope: .global,
        outputPolicy: policy,
        stickMappings: [RemappingStickMapping(source: .left)],
        bindings: []
      ).producesNoOutput
    )
    #expect(
      !RemappingProfile(
        name: "Touch pointer",
        device: RemappingDeviceScope(vendorID: 1, productID: 2),
        applicationScope: .global,
        outputPolicy: policy,
        touchMappings: [RemappingTouchMapping(surface: .primary, mode: .pointer)],
        bindings: []
      ).producesNoOutput
    )
  }

  @Test
  func restoringAndClearingInputPreserveOnlyTheRequiredProfileState() {
    let profile = RemappingProfile(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      name: "Configured",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .application(bundleIdentifier: "com.example.Game"),
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped, physicalInput: .exclusive),
      physicalColor: ControllerColor(red: 1, green: 2, blue: 3),
      gyroOutput: RemappingGyroOutput(mode: .mouse),
      stickMappings: [RemappingStickMapping(source: .left)],
      triggerMappings: [RemappingTriggerMapping(source: .left)],
      touchMappings: [RemappingTouchMapping(surface: .primary, mode: .pointer)],
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .space, modifiers: [])
        )
      ],
      chords: [
        RemappingChord(
          sources: [.button(.south), .button(.east)],
          destination: .keyboard(key: .a, modifiers: [])
        )
      ],
      sequences: [
        RemappingSequence(
          sources: [.button(.south), .button(.east)],
          windowMs: 200,
          destination: .keyboard(key: .b, modifiers: [])
        )
      ],
      layers: [
        RemappingLayer(name: "Layer", activationMode: .hold, activator: .button(.leftShoulder))
      ]
    )

    let restored = profile.restoringDefaultInput()
    #expect(restored.outputPolicy.virtualGamepad == .passthrough)
    #expect(restored.outputPolicy.physicalInput == .exclusive)
    #expect(restored.id == profile.id)
    #expect(restored.bindings == profile.bindings)
    #expect(restored.physicalColor == profile.physicalColor)

    let cleared = profile.clearingAllInput()
    #expect(cleared.suppressesAllControllerInput)
    #expect(!cleared.producesNoOutput)
    #expect(cleared.outputPolicy.physicalInput == .exclusive)
    #expect(cleared.id == profile.id)
    #expect(cleared.name == profile.name)
    #expect(cleared.device == profile.device)
    #expect(cleared.applicationScope == profile.applicationScope)
    #expect(cleared.physicalColor == profile.physicalColor)
    #expect(cleared.motionTuning == .default)
    #expect(cleared.gyroOutput == .default)
    #expect(cleared.stickMappings.isEmpty)
    #expect(cleared.triggerMappings.isEmpty)
    #expect(cleared.touchMappings.isEmpty)
    #expect(cleared.bindings.isEmpty)
    #expect(cleared.chords.isEmpty)
    #expect(cleared.sequences.isEmpty)
    #expect(cleared.layers.isEmpty)
  }

  private func makeProfile(
    outputPolicy: RemappingOutputPolicy = .systemInput,
    bindings: [RemappingBinding] = [],
    chords: [RemappingChord] = [],
    sequences: [RemappingSequence] = [],
    layers: [RemappingLayer] = []
  ) -> RemappingProfile {
    RemappingProfile(
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
