import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RegionSourceTests {
  private let device = LogicalControllerID(vendorID: 1, productID: 2)
  private let keys: [RemappingKeyboardKey] = [.a, .b, .c, .d, .e, .f, .g, .h]

  /// The raw stick magnitude that the default 0.1 deadzone calibrates to `value`.
  private func raw(_ value: Double) -> Float { Float(0.1 + value * 0.9) }

  private func profile(
    _ pairs: [(RemappingSource, RemappingKeyboardKey)],
    triggerMappings: [RemappingTriggerMapping] = []
  ) -> RemappingProfile {
    RemappingProfile(
      name: "Regions",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      triggerMappings: triggerMappings,
      bindings: pairs.map {
        RemappingBinding(source: $0, destination: .keyboard(key: $1, modifiers: []))
      }
    )
  }

  private func ring(
    _ inner: Double,
    _ outer: Double,
    from: Double? = nil,
    to: Double? = nil,
    hysteresis: Double = 0.05,
    stick: RemappingStickSource = .left
  ) -> RemappingSource {
    .stickRegion(
      RemappingStickRegionSource(
        stick: stick,
        innerRadius: inner,
        outerRadius: outer,
        fromDegrees: from,
        toDegrees: to,
        hysteresis: hysteresis
      )
    )
  }

  private func band(
    _ from: Double,
    _ to: Double,
    trigger: RemappingTriggerSource = .right
  ) -> RemappingSource {
    .triggerBand(RemappingTriggerBandSource(trigger: trigger, from: from, to: to, hysteresis: 0.05))
  }

  private func area(
    _ x: Double,
    _ y: Double,
    _ width: Double,
    _ height: Double
  ) -> RemappingSource {
    .touchArea(
      RemappingTouchAreaSource(surface: .primary, x: x, y: y, width: width, height: height)
    )
  }

  private func run(
    _ engine: inout RemappingEngineState,
    _ profile: RemappingProfile,
    _ input: InputChange
  ) -> [RemappingEngineAction] {
    engine.process(inputs: [input], from: device, profile: profile, at: 0)
  }

  @Test
  func outerRingIsButtonWithHysteresisOnItsInnerEdge() throws {
    let profile = profile([(ring(0.8, 1), .a)])
    try profile.validate()
    var engine = RemappingEngineState()
    #expect(run(&engine, profile, .leftStick(x: raw(0.7), y: 0)).isEmpty)
    #expect(run(&engine, profile, .leftStick(x: raw(0.9), y: 0)) == [.system(.keyDown(.a))])
    #expect(run(&engine, profile, .leftStick(x: raw(0.78), y: 0)).isEmpty)
    #expect(run(&engine, profile, .leftStick(x: raw(0.7), y: 0)) == [.system(.keyUp(.a))])
    #expect(run(&engine, profile, .leftStick(x: raw(0.79), y: 0)).isEmpty)
    #expect(run(&engine, profile, .leftStick(x: raw(1), y: 0)) == [.system(.keyDown(.a))])
  }

  @Test
  func regionOfOneStickIgnoresOther() {
    let profile = profile([(ring(0.5, 1), .a)])
    var engine = RemappingEngineState()
    #expect(run(&engine, profile, .rightStick(x: 1, y: 0)).isEmpty)
  }

  @Test(arguments: 0..<8)
  func eightSectorsPressOnlyTheirOwnKey(index: Int) throws {
    let sectors = (0..<8).map { ring(0.5, 1, from: Double($0) * 45, to: Double($0 + 1) * 45) }
    let profile = profile(Array(zip(sectors, keys)))
    try profile.validate()
    let angle = (Double(index) * 45 + 22.5) * .pi / 180
    var engine = RemappingEngineState()
    let actions = run(&engine, profile, .leftStick(x: Float(sin(angle)), y: Float(-cos(angle))))
    #expect(actions == [.system(.keyDown(keys[index]))])
  }

  @Test
  func sectorMayWrapPastUp() {
    let profile = profile([(ring(0.5, 1, from: 315, to: 45), .a)])
    var engine = RemappingEngineState()
    #expect(run(&engine, profile, .leftStick(x: 0, y: -1)) == [.system(.keyDown(.a))])
  }

  @Test
  func regionChangeReleasesBeforeItPresses() {
    let profile = profile([(ring(0.5, 0.8, hysteresis: 0), .a), (ring(0.8, 1, hysteresis: 0), .b)])
    var engine = RemappingEngineState()
    #expect(run(&engine, profile, .leftStick(x: raw(0.6), y: 0)) == [.system(.keyDown(.a))])
    #expect(
      run(&engine, profile, .leftStick(x: raw(0.95), y: 0))
        == [.system(.keyUp(.a)), .system(.keyDown(.b))]
    )
  }

  @Test
  func overlapIsRejected() throws {
    for pair in [
      (ring(0.5, 1), ring(0.7, 1)), (ring(0, 1, from: 0, to: 90), ring(0.2, 0.4, from: 45, to: 90)),
      (ring(0, 1, from: 350, to: 10), ring(0, 1, from: 5, to: 20)),
    ] {
      #expect(throws: RemappingValidationError.overlappingRegions) {
        try profile([(pair.0, .a), (pair.1, .b)]).validate()
      }
    }
    try profile([
      (ring(0.5, 0.8), .a), (ring(0.8, 1), .b), (ring(0.5, 1, stick: .right), .c),
      (ring(0, 0.5, from: 0, to: 180), .d), (ring(0, 0.5, from: 180, to: 0), .e),
    ]).validate()
  }

  @Test
  func threeTriggerBandsPressOnlyBandOfPull() throws {
    let profile = profile([(band(0.1, 0.4), .a), (band(0.4, 0.8), .b), (band(0.8, 1), .c)])
    try profile.validate()
    var engine = RemappingEngineState()
    #expect(run(&engine, profile, .rightTrigger(0.6)) == [.system(.keyDown(.b))])
    #expect(run(&engine, profile, .rightTrigger(0.38)).isEmpty)
    #expect(
      run(&engine, profile, .rightTrigger(0.3)) == [.system(.keyUp(.b)), .system(.keyDown(.a))]
    )
    #expect(
      run(&engine, profile, .rightTrigger(1)) == [.system(.keyUp(.a)), .system(.keyDown(.c))]
    )
    #expect(run(&engine, profile, .leftTrigger(1)).isEmpty)
  }

  @Test
  func dualStageMappingAndBandsOfOneTriggerAreRejected() throws {
    let mapping = RemappingTriggerMapping(source: .right)
    #expect(throws: RemappingValidationError.triggerBandWithDualStage(.right)) {
      try profile([(band(0.1, 0.5), .a)], triggerMappings: [mapping]).validate()
    }
    try profile([(band(0.1, 0.5, trigger: .left), .a)], triggerMappings: [mapping]).validate()
  }

  @Test
  func touchRectangleIsDownWhileContactLiesInIt() throws {
    let profile = profile([(area(0, 0, 0.5, 0.5), .a)])
    try profile.validate()
    func touch(_ active: Bool, _ x: Double, _ y: Double) -> InputChange {
      let scale = Double(UInt16.max)
      return .touch(
        ControllerTouchSample(
          surface: .primary,
          timestamp: MonotonicTimestamp(nanoseconds: 0),
          contacts: [
            ControllerTouchContact(
              slot: 0,
              isActive: active,
              x: UInt16(x * scale),
              y: UInt16(y * scale)
            )
          ]
        )
      )
    }
    var engine = RemappingEngineState()
    #expect(run(&engine, profile, touch(true, 0.1, 0.1)) == [.system(.keyDown(.a))])
    #expect(run(&engine, profile, touch(true, 0.2, 0.3)).isEmpty)
    #expect(run(&engine, profile, touch(true, 0.8, 0.1)) == [.system(.keyUp(.a))])
    #expect(run(&engine, profile, touch(true, 0.1, 0.1)) == [.system(.keyDown(.a))])
    #expect(run(&engine, profile, touch(false, 0.1, 0.1)) == [.system(.keyUp(.a))])
  }

  @Test
  func invalidShapesAreRejected() {
    let rings: [RemappingSource] = [
      ring(0.8, 0.8), ring(-0.1, 0.5), ring(0.5, 1.1), ring(0.5, 1, hysteresis: -0.1),
      ring(0.5, 1, hysteresis: 0.5), ring(0.5, 1, from: 10, to: 10), ring(0.5, 1, from: -1, to: 10),
      ring(0.5, 1, from: 0, to: 361), ring(0.5, 1, from: 10, to: nil), ring(0.5, .nan),
    ]
    for source in rings {
      #expect(throws: RemappingValidationError.invalidStickRegion) {
        try profile([(source, .a)]).validate()
      }
    }
    for source in [band(0.5, 0.5), band(0.6, 0.5), band(-0.1, 0.5), band(0.5, 1.1)] {
      #expect(throws: RemappingValidationError.invalidTriggerBand) {
        try profile([(source, .a)]).validate()
      }
    }
    let areas = [area(0, 0, 0, 0.5), area(0.6, 0, 0.5, 0.5), area(0, 0.6, 0.5, 0.5)]
    for source in areas + [area(-0.1, 0, 0.5, 0.5)] {
      #expect(throws: RemappingValidationError.invalidTouchArea) {
        try profile([(source, .a)]).validate()
      }
    }
  }

  @Test
  func commandLineSourcesParseToRegions() throws {
    #expect(
      try RemappingCommandValueParser.source("stick-region:left:0.8-1")
        == .stickRegion(RemappingStickRegionSource(stick: .left, innerRadius: 0.8, outerRadius: 1))
    )
    #expect(
      try RemappingCommandValueParser.source("stick-region:right:0.5-1:45-90")
        == .stickRegion(
          RemappingStickRegionSource(
            stick: .right,
            innerRadius: 0.5,
            outerRadius: 1,
            fromDegrees: 45,
            toDegrees: 90
          )
        )
    )
    #expect(
      try RemappingCommandValueParser.source("trigger-band:right:0.1-0.4")
        == .triggerBand(RemappingTriggerBandSource(trigger: .right, from: 0.1, to: 0.4))
    )
    #expect(
      try RemappingCommandValueParser.source("touch:primary:area:0:0:0.5:0.5")
        == .touchArea(
          RemappingTouchAreaSource(surface: .primary, x: 0, y: 0, width: 0.5, height: 0.5)
        )
    )
    for text in [
      "stick-region:middle:0.8-1", "stick-region:left:0.8", "stick-region:left:0.8-1:45",
      "stick-region:left:0.8-1-2", "stick-region:left:a-1", "trigger-band:left:0.1",
      "trigger-band:left:0.1-nan", "touch:primary:area:0:0:0.5", "touch:primary:area:0:0:x:0.5",
    ] {
      #expect(throws: RemappingCommandValueError.invalidSource(text)) {
        try RemappingCommandValueParser.source(text)
      }
    }
  }

  @Test
  func sourcesRoundTripThroughProfileDocumentAndRejectForeignKeys() throws {
    let sources = [
      ring(0.8, 1, from: 45, to: 90), ring(0.8, 1), band(0.1, 0.4), area(0, 0, 0.5, 1),
    ]
    for source in sources {
      let data = try JSONEncoder().encode(source)
      #expect(try JSONDecoder().decode(RemappingSource.self, from: data) == source)
    }
    let foreign = Data(
      #"{"type":"TriggerBand","trigger":"Left","from":0.1,"to":0.4,"hysteresis":0.05,"x":1}"#.utf8
    )
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(RemappingSource.self, from: foreign)
    }
    let half = Data(
      (#"{"type":"StickRegion","stick":"Left","innerRadius":0.5,"outerRadius":1,"#
        + #""hysteresis":0.05,"fromDegrees":10}"#).utf8
    )
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(RemappingSource.self, from: half)
    }
  }
}
