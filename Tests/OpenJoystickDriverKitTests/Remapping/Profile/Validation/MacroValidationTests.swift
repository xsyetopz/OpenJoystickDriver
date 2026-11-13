import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct MacroValidationTests {
  private let keyA = RemappingDestination.keyboard(key: .a, modifiers: [])
  private let keyB = RemappingDestination.keyboard(key: .b, modifiers: [])

  @Test
  func validMacroRoundTripsAndValidates() throws {
    let macro = RemappingMacro(
      name: "Combo",
      steps: [.tap(keyA), .wait(durationMs: 100), .tap(keyB)],
      repeatMode: .whileHeld,
      whileRunning: .restart,
      interruptOnRelease: true
    )
    let profile = profile(macros: [macro])
    try profile.validate()
    let data = try JSONEncoder().encode(profile)
    #expect(try JSONDecoder().decode(RemappingProfile.self, from: data) == profile)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("\"repeat\":\"WhileHeld\""))
  }

  @Test
  func stepDestinationsAreKeysButtonsAndDirections() throws {
    let allowed: [RemappingDestination] = [
      keyA, .mouseButton(.left), .gamepadButton(.south), .gamepadDpad(.up),
    ]
    for destination in allowed {
      try profile(
        macros: [RemappingMacro(name: "M", steps: [.tap(destination)])],
        policy: RemappingOutputPolicy(virtualGamepad: .mapped)
      ).validate()
    }
    let rejected: [RemappingDestination] = [
      .mouseMovement(.x), .scroll(.y), .gamepadAxis(.leftStickX),
      .physical(.brightness(0.5)),
    ]
    for destination in rejected {
      let invalid = profile(macros: [RemappingMacro(name: "M", steps: [.tap(destination)])])
      #expect(throws: RemappingValidationError.invalidMacroStepDestination(index: 0, step: 0)) {
        try invalid.validate()
      }
    }
  }

  @Test
  func macroInsideMacroNamesStep() {
    let inner = RemappingMacro(name: "Inner", steps: [.tap(keyA)])
    let outer = RemappingMacro(name: "Outer", steps: [.tap(keyA), .press(.macro(inner.id))])
    #expect(throws: RemappingValidationError.macroNestingNotAllowed(index: 1, step: 1)) {
      try profile(macros: [inner, outer]).validate()
    }
  }

  @Test
  func unknownMacroDestinationIsRejected() {
    let missing = UUID()
    let invalid = profile(macros: [], destination: .macro(missing))
    #expect(throws: RemappingValidationError.unknownMacro(missing)) { try invalid.validate() }
  }

  @Test
  func knownMacroDestinationIsAccepted() throws {
    let macro = RemappingMacro(name: "Combo", steps: [.tap(keyA)])
    try profile(macros: [macro], destination: .macro(macro.id)).validate()
  }

  @Test
  func countAndFieldLimits() throws {
    let tap = RemappingMacroStep.tap(keyA)
    let many = (0..<17).map { RemappingMacro(name: "M\($0)", steps: [tap]) }
    #expect(throws: RemappingValidationError.tooManyMacros(17)) {
      try profile(macros: many).validate()
    }
    try profile(macros: Array(many.prefix(16))).validate()

    let invalid: [(RemappingMacro, String)] = [
      (RemappingMacro(name: "M", steps: []), "steps"),
      (RemappingMacro(name: "M", steps: Array(repeating: tap, count: 33)), "steps"),
      (RemappingMacro(name: "M", steps: [tap], repeatMode: .count(0)), "repeat"),
      (RemappingMacro(name: "M", steps: [tap], repeatMode: .count(501)), "repeat"),
      (RemappingMacro(name: "M", steps: [.wait(durationMs: 5001)]), "steps[0].durationMs"),
      (RemappingMacro(name: "M", steps: [.wait(durationMs: -1)]), "steps[0].durationMs"),
      (RemappingMacro(name: "M", steps: [.wait(durationMs: .nan)]), "steps[0].durationMs"),
      (
        RemappingMacro(name: "M", steps: [.chord(destinations: [keyA], holdMs: 5001)]),
        "steps[0].holdMs"
      ),
      (
        RemappingMacro(name: "M", steps: [.chord(destinations: [], holdMs: 10)]),
        "steps[0].destinations"
      ),
      (RemappingMacro(name: "", steps: [tap]), "name"),
    ]
    for (macro, field) in invalid {
      #expect(throws: RemappingValidationError.invalidMacro(index: 0, field: field)) {
        try profile(macros: [macro]).validate()
      }
    }
    try profile(macros: [
      RemappingMacro(name: "M", steps: Array(repeating: tap, count: 32), repeatMode: .count(500)),
      RemappingMacro(name: "N", steps: [.wait(durationMs: 5000), .wait(durationMs: 0)]),
    ]).validate()
  }

  @Test
  func duplicateNamesAndIdentifiersAreRejected() {
    let tap = RemappingMacroStep.tap(keyA)
    let first = RemappingMacro(name: "Combo", steps: [tap])
    #expect(throws: RemappingValidationError.duplicateMacroName(index: 1)) {
      try profile(macros: [first, RemappingMacro(name: "combo", steps: [tap])]).validate()
    }
    #expect(throws: RemappingValidationError.duplicateMacroID(first.id)) {
      try profile(macros: [first, RemappingMacro(id: first.id, name: "Other", steps: [tap])])
        .validate()
    }
  }

  @Test
  func runTimeBoundsNameLimit() throws {
    let waits = Array(repeating: RemappingMacroStep.wait(durationMs: 5000), count: 8)
    #expect(throws: RemappingValidationError.macroRunTimeExceeded(index: 0, limit: "one-pass")) {
      try profile(macros: [RemappingMacro(name: "Long", steps: waits)]).validate()
    }
    // A chord hold counts like a wait: 6 x 5000 ms is exactly the pass limit.
    let held = Array(
      repeating: RemappingMacroStep.chord(destinations: [keyA], holdMs: 5000),
      count: 6
    )
    try profile(macros: [RemappingMacro(name: "Held", steps: held)]).validate()
    let counted = RemappingMacro(
      name: "Counted",
      steps: [.wait(durationMs: 5000)],
      repeatMode: .count(61)
    )
    #expect(throws: RemappingValidationError.macroRunTimeExceeded(index: 0, limit: "repeat")) {
      try profile(macros: [counted]).validate()
    }
    try profile(macros: [
      RemappingMacro(name: "Edge", steps: [.wait(durationMs: 5000)], repeatMode: .count(60)),
      RemappingMacro(name: "Held", steps: [.wait(durationMs: 5000)], repeatMode: .whileHeld),
    ]).validate()
  }

  @Test
  func strictCodingRejectsMisplacedKeysAndShapes() throws {
    let macro = RemappingMacro(name: "Combo", steps: [.tap(keyA)])
    let data = try JSONEncoder().encode(profile(macros: [macro]))
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let list = try #require(root["macros"] as? [[String: Any]])
    var variants: [[String: Any]] = []
    var extra = list[0]
    extra["extra"] = 1
    variants.append(extra)
    var missing = list[0]
    missing.removeValue(forKey: "interruptOnRelease")
    variants.append(missing)
    var badRepeat = list[0]
    badRepeat["repeat"] = "Forever"
    variants.append(badRepeat)
    var badWhileRunning = list[0]
    badWhileRunning["whileRunning"] = "Queue"
    variants.append(badWhileRunning)
    var badStep = list[0]
    badStep["steps"] = [["type": "Wait", "durationMs": 5, "holdMs": 5]]
    variants.append(badStep)
    var unknownStep = list[0]
    unknownStep["steps"] = [["type": "Jump"]]
    variants.append(unknownStep)
    for variant in variants {
      var document = root
      document["macros"] = [variant]
      let bytes = try JSONSerialization.data(withJSONObject: document)
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(RemappingProfile.self, from: bytes)
      }
    }
  }

  // MARK: Helpers

  private func profile(
    macros: [RemappingMacro],
    destination: RemappingDestination? = nil,
    policy: RemappingOutputPolicy = .systemInput
  ) -> RemappingProfile {
    RemappingProfile(
      name: "Macros",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: policy,
      bindings: [
        RemappingBinding(source: .button(.south), destination: destination ?? keyA)
      ],
      macros: macros
    )
  }
}
