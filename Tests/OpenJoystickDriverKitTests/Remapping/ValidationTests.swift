import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingValidationTests {
  @Test
  func turboAcceptsKeyboardAndMouseButtons() throws {
    let turbo = RemappingTurbo(repeatRateHz: 12, dutyCycle: 0.4)
    let profile = makeProfile(bindings: [
      RemappingBinding(
        source: .button(.south),
        destination: .keyboard(key: .space, modifiers: []),
        turbo: turbo
      ),
      RemappingBinding(
        source: .button(.east),
        destination: .mouseButton(.left),
        turbo: turbo
      ),
    ])

    try profile.validate()
  }

  @Test(arguments: [
    RemappingDestination.mouseMovement(.x),
    RemappingDestination.scroll(.y),
  ])
  func turboRejectsContinuousDestinations(destination: RemappingDestination) {
    let profile = makeProfile(bindings: [
      RemappingBinding(
        source: .axis(.leftStickX),
        destination: destination,
        axisTuning: .default,
        turbo: RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.5)
      ),
    ])

    #expect(throws: RemappingValidationError.turboNotSupported(index: 0)) {
      try profile.validate()
    }
  }

  @Test(arguments: [
    RemappingAxisTuning(deadzone: -0.01),
    RemappingAxisTuning(deadzone: 0.951),
    RemappingAxisTuning(gain: 0.09),
    RemappingAxisTuning(gain: 10.01),
    RemappingAxisTuning(digitalActivationThreshold: 0),
    RemappingAxisTuning(digitalActivationThreshold: 1.01),
  ])
  func tuningRejectsOutOfRangeValues(tuning: RemappingAxisTuning) {
    let profile = axisProfile(tuning: tuning)
    #expect(throws: RemappingValidationError.self) { try profile.validate() }
  }

  @Test(arguments: [
    RemappingAxisTuning(deadzone: .nan),
    RemappingAxisTuning(gain: .infinity),
    RemappingAxisTuning(digitalActivationThreshold: -.infinity),
  ])
  func tuningRejectsNonFiniteValues(tuning: RemappingAxisTuning) {
    let profile = axisProfile(tuning: tuning)
    #expect(throws: RemappingValidationError.self) { try profile.validate() }
  }

  @Test
  func tuningAcceptsInclusiveBoundaryValues() throws {
    try axisProfile(
      tuning: RemappingAxisTuning(
        deadzone: 0,
        gain: 0.1,
        digitalActivationThreshold: 0.01
      )
    ).validate()
    try axisProfile(
      tuning: RemappingAxisTuning(
        deadzone: 0.95,
        gain: 10,
        digitalActivationThreshold: 1
      )
    ).validate()
  }

  @Test(arguments: [
    RemappingTurbo(repeatRateHz: 0.99, dutyCycle: 0.5),
    RemappingTurbo(repeatRateHz: 60.01, dutyCycle: 0.5),
    RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.049),
    RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.951),
    RemappingTurbo(repeatRateHz: .nan, dutyCycle: 0.5),
    RemappingTurbo(repeatRateHz: 10, dutyCycle: .infinity),
  ])
  func turboRejectsInvalidNumericalValues(turbo: RemappingTurbo) {
    let profile = makeProfile(bindings: [
      RemappingBinding(
        source: .button(.south),
        destination: .keyboard(key: .space, modifiers: []),
        turbo: turbo
      ),
    ])
    #expect(throws: RemappingValidationError.self) { try profile.validate() }
  }

  @Test
  func duplicateBindingIdentifiersAreRejected() {
    let id = UUID()
    let profile = makeProfile(bindings: [
      RemappingBinding(
        id: id,
        source: .button(.south),
        destination: .keyboard(key: .a, modifiers: [])
      ),
      RemappingBinding(
        id: id,
        source: .button(.east),
        destination: .keyboard(key: .b, modifiers: [])
      ),
    ])
    #expect(throws: RemappingValidationError.duplicateBindingID(id)) {
      try profile.validate()
    }
  }

  @Test
  func ambiguousDuplicateSourcesAreRejected() {
    let source = RemappingSource.axisDirection(.leftStickY, .negative)
    let profile = makeProfile(bindings: [
      RemappingBinding(
        source: source,
        destination: .keyboard(key: .w, modifiers: []),
        axisTuning: .default
      ),
      RemappingBinding(
        source: source,
        destination: .keyboard(key: .arrowUp, modifiers: []),
        axisTuning: .default
      ),
    ])
    #expect(throws: RemappingValidationError.duplicateSource(source)) {
      try profile.validate()
    }
  }

  @Test(arguments: [
    "Game",
    "com..example",
    ".com.example",
    "com.example.",
    "com.example.bad_value",
    "com.-example.Game",
  ])
  func applicationScopeRequiresValidBundleIdentifier(identifier: String) {
    let profile = RemappingProfile(
      name: "Invalid scope",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .application(bundleIdentifier: identifier),
      bindings: []
    )
    #expect(throws: RemappingValidationError.invalidBundleIdentifier(identifier)) {
      try profile.validate()
    }
  }

  @Test
  func axisBindingsRequireTuningAndCompatibleDestinations() {
    let missingTuning = makeProfile(bindings: [
      RemappingBinding(source: .axis(.leftStickX), destination: .mouseMovement(.x))
    ])
    #expect(throws: RemappingValidationError.axisTuningRequired(index: 0)) {
      try missingTuning.validate()
    }

    let analogToKey = makeProfile(bindings: [
      RemappingBinding(
        source: .axis(.leftStickX),
        destination: .keyboard(key: .a, modifiers: []),
        axisTuning: .default
      ),
    ])
    #expect(throws: RemappingValidationError.incompatibleSourceAndDestination(index: 0)) {
      try analogToKey.validate()
    }

    let buttonToMotion = makeProfile(bindings: [
      RemappingBinding(source: .button(.south), destination: .mouseMovement(.x))
    ])
    #expect(throws: RemappingValidationError.incompatibleSourceAndDestination(index: 0)) {
      try buttonToMotion.validate()
    }
  }

  @Test
  func profileMetadataBoundsAreEnforced() {
    let invalidName = RemappingProfile(
      name: " Padded ",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: []
    )
    #expect(throws: RemappingValidationError.invalidProfileName) {
      try invalidName.validate()
    }

    let unsupportedVersion = RemappingProfile(
      schemaVersion: 2,
      name: "Future",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: []
    )
    #expect(throws: RemappingValidationError.unsupportedSchemaVersion(2)) {
      try unsupportedVersion.validate()
    }

    let binding = RemappingBinding(
      source: .button(.south),
      destination: .keyboard(key: .space, modifiers: [])
    )
    let oversized = makeProfile(
      bindings: Array(repeating: binding, count: RemappingProfile.maximumBindingCount + 1)
    )
    #expect(
      throws: RemappingValidationError.tooManyBindings(
        RemappingProfile.maximumBindingCount + 1
      )
    ) {
      try oversized.validate()
    }
  }

  private func makeProfile(bindings: [RemappingBinding]) -> RemappingProfile {
    RemappingProfile(
      name: "Test",
      device: RemappingDeviceScope(vendorID: 0x045E, productID: 0x02EA),
      applicationScope: .application(bundleIdentifier: "com.example.Game"),
      bindings: bindings
    )
  }

  private func axisProfile(tuning: RemappingAxisTuning) -> RemappingProfile {
    makeProfile(bindings: [
      RemappingBinding(
        source: .axis(.leftStickX),
        destination: .mouseMovement(.x),
        axisTuning: tuning
      ),
    ])
  }
}
