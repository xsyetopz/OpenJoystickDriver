import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ProfileControlActionTests {
  private let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)
  private let keyB = RemappingDestination.keyboard(key: .b, modifiers: [])
  private let keyC = RemappingDestination.keyboard(key: .c, modifiers: [])

  // MARK: Coding and validation

  @Test
  func destinationsRoundTripAsTheirDocumentShape() throws {
    let layer = UUID()
    let other = UUID()
    let cases: [(RemappingDestination, String)] = [
      (.profileSwitch(.next), #"{"profile":"Next","type":"ProfileSwitch"}"#),
      (.profileSwitch(.previous), #"{"profile":"Previous","type":"ProfileSwitch"}"#),
      (
        .profileSwitch(.profile(other)),
        #"{"profile":"\#(other.uuidString)","type":"ProfileSwitch"}"#
      ),
      (
        .layerSet(layer: layer, mode: .toggle),
        #"{"layer":"\#(layer.uuidString)","mode":"Toggle","type":"LayerSet"}"#
      ),
      (.pause(.off), #"{"mode":"Off","type":"Pause"}"#),
    ]
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    for (destination, json) in cases {
      let data = try encoder.encode(destination)
      #expect(String(bytes: data, encoding: .utf8) == json)
      #expect(try JSONDecoder().decode(RemappingDestination.self, from: data) == destination)
    }
  }

  @Test
  func badShapesAreRejected() {
    let rejected = [
      #"{"type":"ProfileSwitch","profile":"Later"}"#,
      #"{"type":"ProfileSwitch","profile":"Next","mode":"On"}"#,
      #"{"type":"Pause","mode":"Maybe"}"#,
      #"{"type":"Pause"}"#,
      #"{"type":"LayerSet","mode":"On"}"#,
    ]
    for json in rejected {
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(RemappingDestination.self, from: Data(json.utf8))
      }
    }
  }

  @Test
  func unknownLayerAndOtherBehaviorsAreRejected() throws {
    let layerID = UUID()
    let missing = profile(.layerSet(layer: layerID, mode: .on))
    #expect(throws: RemappingValidationError.unknownLayer(layerID)) { try missing.validate() }
    for behavior in [RemappingBindingBehavior.toggle, .press, .release, .pulse, .tapOnRelease] {
      let invalid = profile(.pause(.on), behavior: behavior)
      #expect(throws: RemappingValidationError.bindingBehaviorConflict(index: 0)) {
        try invalid.validate()
      }
    }
    try profile(.pause(.on), behavior: .tapOnPress).validate()
    try profile(.profileSwitch(.next)).validate()
  }

  @Test
  func switchToAProfileOfAnotherModelNamesTheDestination() throws {
    let same = profile(.pause(.on))
    let foreign = profile(.pause(.on), product: 9)
    let switching = profile(.profileSwitch(.profile(foreign.id)))
    #expect(throws: RemappingValidationError.switchProfileForOtherModel(foreign.id)) {
      try switching.validateProfileSwitches(among: [same, foreign])
    }
    #expect(throws: RemappingValidationError.unknownSwitchProfile(foreign.id)) {
      try switching.validateProfileSwitches(among: [same])
    }
    let target = profile(.pause(.on))
    try profile(.profileSwitch(.profile(target.id))).validateProfileSwitches(among: [target])
  }

  // MARK: Target resolution

  @Test
  func switchByIdNamesThatProfile() {
    let profiles = ["a", "B", "c"].map { named($0) }
    #expect(
      RemappingProfileTarget.profile(profiles[2].id).resolve(from: profiles[0].id, among: profiles)
        == profiles[2]
    )
    #expect(
      RemappingProfileTarget.profile(UUID()).resolve(from: profiles[0].id, among: profiles) == nil
    )
  }

  @Test
  func nextAndPreviousWalkNamesCaseInsensitivelyAndWrap() {
    let profiles = ["b", "A", "c"].map { named($0) }
    let (b, a, c) = (profiles[0], profiles[1], profiles[2])
    #expect(RemappingProfileTarget.next.resolve(from: a.id, among: profiles) == b)
    #expect(RemappingProfileTarget.next.resolve(from: c.id, among: profiles) == a)
    #expect(RemappingProfileTarget.previous.resolve(from: b.id, among: profiles) == a)
    #expect(RemappingProfileTarget.previous.resolve(from: a.id, among: profiles) == c)
  }

  // MARK: Engine

  @Test
  func profileSwitchEmitsTheRequestOnPressOnly() {
    var state = RemappingEngineState()
    let profile = profile(.profileSwitch(.next))
    #expect(
      press(&state, profile) == [.profileSwitch(.next, from: profile.id, identifier)]
    )
    #expect(release(&state, profile).isEmpty)
  }

  @Test
  func layerOnOffAndToggle() {
    let layer = RemappingLayer(
      name: "L",
      activationMode: .hold,
      activator: .button(.north),
      bindings: [RemappingBinding(source: .button(.east), destination: keyC)]
    )
    let layered = profile(
      .layerSet(layer: layer.id, mode: .toggle),
      extra: [
        RemappingBinding(
          source: .button(.west),
          destination: .layerSet(layer: layer.id, mode: .on)
        ),
        RemappingBinding(
          source: .button(.leftShoulder),
          destination: .layerSet(layer: layer.id, mode: .off)
        ),
      ],
      layers: [layer]
    )
    var state = RemappingEngineState()
    func tap(_ button: Control) -> Bool {
      _ = press(&state, layered, button)
      _ = release(&state, layered, button)
      return state.devices[identifier]?.layers.activeLayers.contains(layer.id) == true
    }
    #expect(
      [tap(.south), tap(.south), tap(.west), tap(.west), tap(.leftShoulder)]
        == [true, false, true, true, false]
    )

    _ = press(&state, layered, .west)
    let east = press(&state, layered, .east)
    #expect(east == [.system(.keyDown(.c))])
  }

  @Test
  func pausePassesThroughAndKeepsThePauseBinding() {
    var state = RemappingEngineState()
    let profile = profile(
      .pause(.toggle),
      extra: [RemappingBinding(source: .button(.east), destination: keyB)],
      policy: RemappingOutputPolicy(virtualGamepad: .passthrough)
    )
    #expect(press(&state, profile, .east).contains(.system(.keyDown(.b))))
    let paused = press(&state, profile)
    #expect(paused.contains(.system(.keyUp(.b))))
    #expect(state.devices[identifier]?.isPaused == true)
    _ = release(&state, profile, .east)
    let during = press(&state, profile, .east)
    #expect(!during.contains(.system(.keyDown(.b))))
    #expect(during.contains { if case .gamepad = $0 { true } else { false } })
    _ = release(&state, profile)
    _ = press(&state, profile)
    #expect(state.devices[identifier]?.isPaused == false)
  }

  @Test
  func pauseReleasesMacroOutputs() {
    let macro = RemappingMacro(
      name: "M",
      steps: [.press(.keyboard(key: .a, modifiers: [])), .wait(durationMs: 1000)]
    )
    var state = RemappingEngineState()
    let profile = profile(
      .pause(.on),
      extra: [RemappingBinding(source: .button(.east), destination: .macro(macro.id))],
      macros: [macro]
    )
    #expect(press(&state, profile, .east) == [.system(.keyDown(.a))])
    #expect(press(&state, profile).contains(.system(.keyUp(.a))))
    #expect(state.heldOutputs.isEmpty)
    #expect(!state.hasScheduledOutput)
  }

  @Test
  func pauseClearsOnProfileChangeAndDisconnect() {
    var state = RemappingEngineState()
    let first = profile(.pause(.on))
    _ = press(&state, first)
    #expect(state.devices[identifier]?.isPaused == true)
    let second = profile(.pause(.on))
    _ = state.process(inputs: [], from: identifier, profile: second, at: 1)
    #expect(state.devices[identifier]?.isPaused == false)
    _ = press(&state, second)
    _ = state.releaseController(identifier)
    #expect(state.devices[identifier] == nil)
  }

  // MARK: Helpers

  private func named(_ name: String) -> RemappingProfile {
    RemappingProfile(
      name: name,
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: .systemInput,
      bindings: []
    )
  }

  private func press(
    _ state: inout RemappingEngineState,
    _ profile: RemappingProfile,
    _ button: Control = .south
  ) -> [RemappingEngineAction] {
    state.process(inputs: [.press(button)], from: identifier, profile: profile, at: 0)
  }

  private func release(
    _ state: inout RemappingEngineState,
    _ profile: RemappingProfile,
    _ button: Control = .south
  ) -> [RemappingEngineAction] {
    state.process(inputs: [.release(button)], from: identifier, profile: profile, at: 0)
  }

  private func profile(
    _ destination: RemappingDestination,
    behavior: RemappingBindingBehavior = .hold,
    extra: [RemappingBinding] = [],
    layers: [RemappingLayer] = [],
    macros: [RemappingMacro] = [],
    product: UInt16 = 2,
    policy: RemappingOutputPolicy = .systemInput
  ) -> RemappingProfile {
    RemappingProfile(
      name: "P",
      device: RemappingDeviceScope(vendorID: 1, productID: product),
      applicationScope: .global,
      outputPolicy: policy,
      bindings: [
        RemappingBinding(source: .button(.south), destination: destination, behavior: behavior)
      ] + extra,
      layers: layers,
      macros: macros
    )
  }
}
