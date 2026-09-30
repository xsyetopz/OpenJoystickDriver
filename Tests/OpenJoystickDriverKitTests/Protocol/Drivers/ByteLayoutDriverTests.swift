import Foundation
import OpenJoystickDriverKit
import Testing

struct ByteLayoutDriverTests {
  // MARK: - Report fixtures

  private func neutralReport() -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 22)
    // Sticks rest at 127/128, the pair that centers on 127.5.
    bytes[3] = 127
    bytes[4] = 128
    bytes[5] = 127
    bytes[6] = 128
    return bytes
  }

  /// `hat` bits: 1 right, 2 left, 4 up, 8 down.
  /// `face` bits: 0x80 Y, 0x40 B, 0x20 A, 0x10 X.
  private func report(
    meta: UInt8 = 0,
    lsX: UInt8 = 127,
    lsY: UInt8 = 128,
    rsX: UInt8 = 127,
    rsY: UInt8 = 128,
    hat: UInt8 = 0,
    face: UInt8 = 0,
    leftShoulder: Bool = false,
    rightShoulder: Bool = false,
    lt: UInt8 = 0,
    rt: UInt8 = 0
  ) -> [UInt8] {
    var bytes = neutralReport()
    bytes[1] = meta
    bytes[3] = lsX
    bytes[4] = lsY
    bytes[5] = rsX
    bytes[6] = rsY
    if hat & 0x01 != 0 { bytes[7] = 0x80 }
    if hat & 0x02 != 0 { bytes[8] = 0x80 }
    if hat & 0x04 != 0 { bytes[9] = 0x80 }
    if hat & 0x08 != 0 { bytes[10] = 0x80 }
    if face & 0x80 != 0 { bytes[11] = 0x80 }
    if face & 0x40 != 0 { bytes[12] = 0x80 }
    if face & 0x20 != 0 { bytes[13] = 0x80 }
    if face & 0x10 != 0 { bytes[14] = 0x80 }
    if leftShoulder { bytes[15] = 0x80 }
    if rightShoulder { bytes[16] = 0x80 }
    bytes[17] = lt
    bytes[18] = rt
    return bytes
  }

  private func parse(
    _ driver: ByteLayoutDriver,
    _ bytes: [UInt8],
    at _: UInt64 = 0
  ) -> ControllerState? {
    try? driver.parse(report: Data(bytes), receivedAt: MonotonicTimestamp(nanoseconds: 1))?.state
  }

  // MARK: - Buttons

  @Test
  func faceButtonsAppearInThePressedSet() throws {
    let driver = ByteLayoutDriver()
    #expect(parse(driver, neutralReport()) == nil)

    let state = try #require(parse(driver, report(face: 0x20 | 0x10)))
    #expect(state.pressed == [.faceSouth, .faceWest])

    let released = try #require(parse(driver, report(face: 0x20)))
    #expect(released.pressed == [.faceSouth])
  }

  @Test
  func metaAndShoulderButtonsMapToTheirOwnControls() throws {
    let driver = ByteLayoutDriver()
    let state = try #require(
      parse(
        driver,
        report(meta: 0x01 | 0x02 | 0x04 | 0x08, leftShoulder: true, rightShoulder: true)
      )
    )
    #expect(
      state.pressed == [
        .view, .menu, .leftStickClick, .rightStickClick, .leftShoulder, .rightShoulder,
      ]
    )
  }

  // MARK: - Hat

  @Test
  func hatCombinesFourBytesIntoADirection() throws {
    let driver = ByteLayoutDriver()
    #expect(try #require(parse(driver, report(hat: 0x04))).hat == .north)
    #expect(try #require(parse(driver, report(hat: 0x04 | 0x01))).hat == .northEast)
    #expect(try #require(parse(driver, report(hat: 0x08 | 0x02))).hat == .southWest)
    #expect(try #require(parse(driver, report(hat: 0))).hat == .neutral)
  }

  // MARK: - Sticks

  @Test
  func sticksReportRawDeviceOrientation() throws {
    let driver = ByteLayoutDriver()
    // Byte 255 is +1 and byte 0 is -1; StickPosition negates yDown into the Y-up frame,
    // so a raw 0 on Y arrives as up.
    let state = try #require(parse(driver, report(lsX: 255, lsY: 0, rsX: 0, rsY: 255)))
    #expect(state.leftStick.x.normalized == 1)
    #expect(state.leftStick.y.normalized == 1)
    #expect(state.rightStick.x.normalized == -1)
    #expect(state.rightStick.y.normalized == -1)
  }

  @Test
  func deadzoneSuppressesRestNoise() throws {
    let driver = ByteLayoutDriver()
    _ = parse(driver, neutralReport())
    // 128 is within the deadzone of 127.5, so rest noise reports nothing.
    #expect(parse(driver, report(lsX: 128, lsY: 128)) == nil)

    // 140 is 12.5 from center, normalized 0.098, outside the 0.08 deadzone.
    #expect(parse(driver, report(lsX: 140, lsY: 140)) != nil)
  }

  // MARK: - Triggers

  @Test
  func triggersNormalizeToUnipolarRange() throws {
    let driver = ByteLayoutDriver()
    // Released triggers equal neutral, so this frame carries no change.
    #expect(parse(driver, report(lt: 0, rt: 0)) == nil)

    let pressed = try #require(parse(driver, report(lt: 255, rt: 128)))
    #expect(abs(pressed.leftTrigger.normalized - 1) < 0.001)
    #expect(abs(pressed.rightTrigger.normalized - 128.0 / 255.0) < 0.001)

    let released = try #require(parse(driver, report(lt: 0, rt: 0)))
    #expect(released.leftTrigger == .min)
    #expect(released.rightTrigger == .min)
  }

  // MARK: - Malformed frames

  @Test
  func shortReportIsIgnoredAndKeepsState() throws {
    let driver = ByteLayoutDriver()
    _ = parse(driver, report(face: 0x20))
    #expect(
      try driver.parse(report: Data([0x01, 0x02, 0x03]), receivedAt: .init(nanoseconds: 2)) == nil
    )

    // State survived the malformed frame.
    #expect(try #require(parse(driver, report(face: 0))).pressed.isEmpty)
  }

  @Test
  func identicalReportCarriesNoEvent() throws {
    let driver = ByteLayoutDriver()
    _ = parse(driver, neutralReport())
    #expect(parse(driver, neutralReport()) == nil)
  }

  @Test
  func resetReturnsToNeutral() throws {
    let driver = ByteLayoutDriver()
    _ = parse(driver, report(lsX: 255, face: 0x20))
    driver.resetProtocolState()
    // After a reset the held controls reappear, proving state was cleared.
    let state = try #require(parse(driver, report(lsX: 255, face: 0x20)))
    #expect(state.pressed == [.faceSouth])
  }

  // MARK: - Wiring

  /// Reports reach this driver only while it declines element decoding.
  @Test
  func driverDeclaresRawReportsRatherThanElementValues() {
    #expect(!ByteLayoutDriver().sessionPlan.parsesHIDElementValues)
  }
}
