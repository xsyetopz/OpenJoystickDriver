import Testing

@testable import OpenJoystickDriverKit

struct MotionBiasTests {
  private func reading(_ x: Double, accelY: Double = 1) throws -> ControllerMotionReading {
    try #require(ControllerMotionReading(
      gyroscopeDegreesPerSecond: ControllerMotionVector(x: x, y: 0, z: 0),
      accelerationG: ControllerMotionVector(x: 0, y: accelY, z: 0),
      calibrationSource: .deviceFactory
    ))
  }

  @Test func steadyBiasRequiresTimeAndDoesNotAlterFactoryReading() throws {
    var bias = RemappingMotionBias()
    let input = try reading(0.8)
    for _ in 0..<100 { _ = bias.update(input, deltaTime: 0.01, automatic: true) }
    #expect(bias.offset.x == 0)
    for _ in 0..<110 { _ = bias.update(input, deltaTime: 0.01, automatic: true) }
    #expect(bias.isSteady)
    #expect(abs(bias.offset.x - 0.8) < 0.000001)
    #expect(input.gyroscopeDegreesPerSecond.x == 0.8)
    #expect(input.calibrationSource == .deviceFactory)
  }

  @Test func movementAndGapsCannotAccumulateStillness() throws {
    var bias = RemappingMotionBias()
    for index in 0..<1000 {
      _ = bias.update(
        try reading(index.isMultiple(of: 2) ? 1 : 2), deltaTime: 0.01, automatic: true
      )
    }
    #expect(bias.offset.x == 0)
    for _ in 0..<100 { _ = bias.update(try reading(1), deltaTime: 0.01, automatic: true) }
    _ = bias.update(try reading(1), deltaTime: 10, automatic: true)
    for _ in 0..<100 { _ = bias.update(try reading(1), deltaTime: 0.01, automatic: true) }
    #expect(!bias.isSteady)
    for _ in 0..<500 {
      _ = bias.update(try reading(1, accelY: 2), deltaTime: 0.01, automatic: true)
    }
    #expect(bias.offset.x == 0)
  }

  @Test func manualCollectionIsTimeWeightedAndPauseRetainsOffset() throws {
    var bias = RemappingMotionBias()
    bias.startManualCollection()
    _ = bias.update(try reading(1), deltaTime: 0.01, automatic: false)
    _ = bias.update(try reading(3), deltaTime: 0.03, automatic: false)
    #expect(abs(bias.offset.x - 2.5) < 0.000001)
    bias.pauseManualCollection()
    let corrected = bias.update(try reading(4), deltaTime: 0.01, automatic: false)
    #expect(corrected.x == 1.5)
    let accepted = bias.setOffset(ControllerMotionVector(x: .nan, y: 0, z: 0))
    #expect(!accepted)
    #expect(bias.offset.x == 2.5)
    bias.reset()
    #expect(bias.offset.x == 0)
  }
}
