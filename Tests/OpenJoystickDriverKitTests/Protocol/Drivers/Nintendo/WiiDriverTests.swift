import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct WiiDriverTests {
  static let family = PhysicalProtocolID.nintendoWii
  static let model = ControllerModelID(vendorID: 0x057E, productID: 0x0306)

  private let driver = WiiDriver(tuning: nil, irFormat: nil)

  private func event(_ fixture: String) throws -> ControllerEvent? {
    try driver.parseReport(WiiFixtures.report(fixture))
  }

  @Test
  func registryBuildsDriverForFamily() throws {
    let donor = ControllerModelID(vendorID: 0x045E, productID: 0x02EA)
    let record = try #require(ProtocolDriverRegistry().record(for: donor))
    let built = ProtocolDriverRegistry.makeUnobservedDriver(
      protocolID: .nintendoWii,
      variant: .bluetoothClassic,
      record: record,
      model: Self.model,
      transportProfile: record.transportProfile
    )
    guard case .success(let made) = built else {
      Issue.record("no driver for NintendoWii")
      return
    }
    #expect(made is WiiDriver)
  }

  @Test
  func buttonPressesSouthAndNothingElse() throws {
    #expect(try driver.parseReport(Data([0x30, 0x00, 0x08]))?.state.pressed == [.south])
  }

  @Test
  func everyCoreButtonOfDescriptionMapsToItsControl() throws {
    let wii = try #require(Self.family.protocolDescription.wiiRemote)
    for button in wii.coreButtons {
      var bytes: [UInt8] = [0x30, 0, 0]
      bytes[1 + button.field.byte] = button.field.mask
      #expect(try driver.parseReport(Data(bytes))?.state.pressed == [button.control])
    }
  }

  @Test
  func accelerometerReassemblesTenBitsFromHighByteAndLowBits() throws {
    _ = try driver.parseReport(Data([0x31, 0x40, 0x00, 0x84, 0x00, 0x00]))
    #expect(driver.acceleration?.x == 0x212)
  }

  @Test
  func yAndZTakeTheirSingleLowBitAsBitOne() throws {
    _ = try driver.parseReport(Data([0x31, 0x00, 0x60, 0x80, 0x80, 0x80]))
    #expect(driver.acceleration == WiiDriver.RawAcceleration(x: 0x200, y: 0x202, z: 0x202))
  }

  @Test
  func accelerometerFixtureDecodesButtonsAndReading() throws {
    let event = try event("31-core-accelerometer")
    #expect(event?.state.pressed == [.dpadUp, .south])
    #expect(driver.acceleration == WiiDriver.RawAcceleration(x: 0x212, y: 0x200, z: 0x264))
  }

  @Test
  func everyModeFixtureWithButtonsDecodesThem() throws {
    let wii = try #require(Self.family.protocolDescription.wiiRemote)
    for mode in wii.reportModes where mode.blocks.contains(where: { $0.kind == .buttons }) {
      for name in try WiiFixtures.names(id: mode.id) {
        #expect(try event(name)?.state.pressed == [.dpadUp, .south], "\(name)")
      }
    }
  }

  @Test
  func reportWithoutButtonsOrShortOneGivesNoEvent() throws {
    #expect(try event("3D-extension21") == nil)
    #expect(try driver.parseReport(Data([0x31, 0x00, 0x00])) == nil)
    #expect(try driver.parseReport(Data()) == nil)
  }

  @Test
  func halfBatteryByteIsFiftyPercent() throws {
    #expect(try event("20-status-no-extension") == nil)
    #expect(driver.power?.battery.percentage == 50...50)
    #expect(driver.isBatteryLow == false)
  }

  @Test
  func fullAndLowBatteryFixtures() throws {
    _ = try event("20-status-battery-full")
    #expect(driver.power?.battery.percentage == 100...100)
    _ = try event("20-status-battery-low")
    #expect(driver.power?.battery.percentage == 8...8)
    #expect(driver.isBatteryLow)
  }

  @Test
  func readReplyAndAcknowledgementCarryNoInput() throws {
    for name in ["21-read-success", "21-read-error", "22-ack-success", "22-ack-error"] {
      #expect(try event(name) == nil, "\(name)")
    }
  }

  @Test
  func startupRequestsStatusAndSetsAccelerometerMode() {
    #expect(
      driver.startupWrites() == [
        .hidOutput(PhysicalHIDOutputReport(reportID: 0x15, bytes: [0x15, 0x00])),
        .hidOutput(PhysicalHIDOutputReport(reportID: 0x12, bytes: [0x12, 0x04, 0x31])),
      ]
    )
  }

  @Test
  func resetReturnsToNeutral() throws {
    _ = try event("31-core-accelerometer")
    driver.resetProtocolState()
    #expect(try driver.parseReport(Data([0x30, 0, 0]))?.state.pressed.isEmpty == true)
    #expect(driver.acceleration == nil)
  }
}
