import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct WiiDriverExtensionTests {
  private static let wii = PhysicalProtocolID.nintendoWii.protocolDescription.wiiRemote
  private let driver = WiiDriver()

  /// A mode `0x32` report: the core bytes, the six extension bytes and two spare.
  private func report(_ data: Data) -> Data {
    Data([0x32, 0, 0]) + data + Data([0, 0])
  }

  private func event(_ kind: String, _ sample: String) throws -> ControllerEvent? {
    driver.extensionKind = .known(kind)
    return try driver.parseReport(report(WiiFixtureFolder.extensions.bytes(sample)))
  }

  @Test
  func theNunchukStickIsCenteredOnTheFirstSampleAndReachesItsEnds() throws {
    #expect(try event("Nunchuk", "data-nunchuk-rest")?.state.leftStick == .center)
    let right = Data([0xFF, 0x00, 0x80, 0x80, 0x80, 0x03])
    let state = try #require(try driver.parseReport(report(right))?.state)
    #expect(state.leftStick.x.rawValue >= 32_000)
    // Y grows upward on the wire and downward in the state.
    #expect(state.leftStick.y == .max)
    let left = Data([0x00, 0xFF, 0x80, 0x80, 0x80, 0x03])
    #expect(try driver.parseReport(report(left))?.state.leftStick.x == .min)
  }

  @Test
  func theNunchukButtonsAreDownWhenTheirBitIsClear() throws {
    #expect(try event("Nunchuk", "data-nunchuk-rest")?.state.pressed.isEmpty == true)
    #expect(
      try event("Nunchuk", "data-nunchuk-low")?.state.pressed == [.leftTrigger, .leftShoulder]
    )
  }

  @Test
  func aClassicReportWithAPressedGivesEastAndNothingElse() throws {
    var bytes = Array(try WiiFixtureFolder.extensions.bytes("data-classic-rest"))
    bytes[5] &= ~0x10
    driver.extensionKind = .known("ClassicController")
    #expect(try driver.parseReport(report(Data(bytes)))?.state.pressed == [.east])
  }

  @Test
  func theClassicSticksAndTriggersScaleFromTheirCenters() throws {
    #expect(try event("ClassicController", "data-classic-rest")?.state.leftStick == .center)
    let high = try #require(try event("ClassicController", "data-classic-high")?.state)
    #expect(high.leftStick.x.rawValue >= 31_000)
    #expect(high.rightStick.x.rawValue >= 30_000)
    #expect(high.leftTrigger == .max)
    #expect(high.rightTrigger == .max)
    let low = try #require(try event("ClassicController", "data-classic-low")?.state)
    #expect(low.leftStick.x == .min)
    #expect(low.leftTrigger == .min)
  }

  @Test
  func anUnknownExtensionLeavesTheExtensionBytesUndecoded() throws {
    driver.extensionKind = .unknown([1, 2, 3, 4, 5, 6])
    #expect(try driver.parseReport(report(Data([0x23, 0x1B, 0, 0, 0, 0])))?.state == .neutral)
  }

  @Test
  func theDriverDeclaresTheCoreAndEveryExtensionControlAndMotion() throws {
    let wii = try #require(Self.wii)
    var expected = Set(wii.coreButtons.map(\.control))
    for layout in wii.extensions.compactMap(\.layout) {
      expected.formUnion(layout.buttons.map(\.control))
      expected.formUnion(layout.sticks.map(\.control))
      expected.formUnion(layout.triggers.map(\.control))
    }
    #expect(driver.capabilities.controls == expected)
    #expect(driver.capabilities.motion)
    #expect([.leftStickX, .rightStickY, .rightTrigger, .east].allSatisfy(expected.contains))
  }

  /// Zero at 0x200 and gravity at 0x300 on every axis.
  private func calibrate() {
    driver.accelerometerCalibration = WiiDriver.AccelerometerCalibration([
      0x80, 0x80, 0x80, 0, 0xC0, 0xC0, 0xC0, 0, 0, 0,
    ])
  }

  @Test
  func theAccelerometerReadingBecomesAMotionSampleInMetresPerSecondSquared() throws {
    calibrate()
    let event = try #require(try driver.parseReport(Data([0x31, 0, 0, 0xC0, 0x80, 0x80]), at: 7))
    let sample = try #require(event.motion.first)
    #expect(abs(sample.acceleration.x - 9.80665) < 1e-9)
    #expect(sample.acceleration.y == 0)
    #expect(sample.angularVelocity == ControllerMotionVector(x: 0, y: 0, z: 0))
    #expect(sample.calibrationSource == .deviceFactory)
    #expect(sample.timestamp.monotonic == MonotonicTimestamp(nanoseconds: 7))
  }

  @Test
  func noMotionSampleBeforeTheCalibrationIsRead() throws {
    #expect(try driver.parseReport(Data([0x31, 0, 0, 0xC0, 0x80, 0x80]))?.motion.isEmpty == true)
  }
}
