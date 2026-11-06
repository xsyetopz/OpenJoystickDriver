import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A rumble template's `resendIntervalMilliseconds`: the driver's keep-alive sends the last
/// rumble report again while a motor runs and stops after a zero report.
struct RumbleResendTests {
  private static let running = RumbleIntensities(lowFrequency: UnipolarValue(0x8000))

  private static func usbTemplate(resend: Int?) throws -> RumbleOutputTemplate {
    try RumbleOutputTemplate(
      target: .usb(length: 4),
      bytes: [0x00, 0x04, 0x00, 0x00],
      motors: [.lowFrequency: .init(byte: 2), .highFrequency: .init(byte: 3)],
      resendIntervalMilliseconds: resend
    )
  }

  private static func hidTemplate(resend: Int?) throws -> RumbleOutputTemplate {
    try RumbleOutputTemplate(
      target: .hid(ControllerTemplateReport(kind: .output, reportID: 0x10, length: 10)),
      motors: [.lowFrequency: .init(byte: 2, encoding: .switchHDRumble)],
      counterByte: 1,
      resendIntervalMilliseconds: resend
    )
  }

  private func usbBytes(_ writes: [PhysicalOutputWrite]) -> [[UInt8]] {
    writes.compactMap { write in
      if case .usb(let packet, _) = write { packet.bytes } else { nil }
    }
  }

  private func hidBytes(_ writes: [PhysicalOutputWrite]) -> [[UInt8]] {
    writes.compactMap { write in
      if case .hidOutput(let report) = write { report.bytes } else { nil }
    }
  }

  @Test
  func xidResendsTheLastReportWhileAMotorRunsThenStops() throws {
    let driver = xidDriver(rumbleTemplate: try Self.usbTemplate(resend: 40))
    #expect(driver.sessionPlan.usbKeepAliveIntervalNanoseconds == 40_000_000)
    #expect(driver.keepAliveWrites().isEmpty)
    let sent = try driver.encode(.setRumble(Self.running, duration: .held)).writes
    #expect(usbBytes(sent) == [[0x00, 0x04, 0x80, 0x00]])
    #expect(usbBytes(driver.keepAliveWrites()) == usbBytes(sent))
    #expect(usbBytes(driver.keepAliveWrites()) == usbBytes(sent))
    _ = try driver.encode(.stopRumble)
    #expect(driver.keepAliveWrites().isEmpty)
  }

  @Test
  func aZeroSetRumbleStopsTheResends() throws {
    let driver = xidDriver(rumbleTemplate: try Self.usbTemplate(resend: 40))
    _ = try driver.encode(.setRumble(Self.running, duration: .held))
    _ = try driver.encode(.setRumble(.off, duration: .held))
    #expect(driver.keepAliveWrites().isEmpty)
  }

  @Test
  func aNewSessionStopsTheResends() throws {
    let driver = xidDriver(rumbleTemplate: try Self.usbTemplate(resend: 40))
    _ = try driver.encode(.setRumble(Self.running, duration: .held))
    driver.resetProtocolState()
    #expect(driver.keepAliveWrites().isEmpty)
  }

  @Test
  func withoutAResendIntervalThereIsNoKeepAlive() throws {
    let driver = xidDriver(rumbleTemplate: try Self.usbTemplate(resend: nil))
    _ = try driver.encode(.setRumble(Self.running, duration: .held))
    #expect(driver.sessionPlan.usbKeepAliveIntervalNanoseconds == nil)
    #expect(driver.keepAliveWrites().isEmpty)
  }

  @Test
  func xusbResendsOnTheUSBChannel() throws {
    let driver = XUSBDriver(rumbleTemplate: try Self.usbTemplate(resend: 25))
    #expect(driver.sessionPlan.usbKeepAliveIntervalNanoseconds == 25_000_000)
    #expect(driver.sessionPlan.hidKeepAliveIntervalNanoseconds == nil)
    let sent = try driver.encode(.setRumble(Self.running, duration: .held)).writes
    #expect(usbBytes(driver.keepAliveWrites()) == usbBytes(sent))
    _ = try driver.encode(.stopRumble)
    #expect(driver.keepAliveWrites().isEmpty)
  }

  @Test
  func shieldResendsOnTheHIDChannel() throws {
    let driver = NVIDIAShieldDriver(
      isShield2015: true,
      rumbleTemplate: try Self.hidTemplate(resend: 30)
    )
    #expect(driver.sessionPlan.hidKeepAliveIntervalNanoseconds == 30_000_000)
    let sent = try driver.encode(.setRumble(Self.running, duration: .held)).writes
    #expect(hidBytes(driver.keepAliveWrites()) == hidBytes(sent))
    _ = try driver.encode(.stopRumble)
    #expect(driver.keepAliveWrites().isEmpty)
  }

  @Test
  func switch1ResendTakesAFreshCounter() throws {
    let driver = Switch1Driver(rumbleTemplate: try Self.hidTemplate(resend: 50))
    #expect(driver.sessionPlan.hidKeepAliveIntervalNanoseconds == 50_000_000)
    let first = hidBytes(try driver.encode(.setRumble(Self.running, duration: .held)).writes)
    let second = hidBytes(driver.keepAliveWrites())
    let third = hidBytes(driver.keepAliveWrites())
    #expect(first.count == 1 && second.count == 1 && third.count == 1)
    #expect(first[0][1] == 0 && second[0][1] == 1 && third[0][1] == 2)
    #expect(Array(first[0][2...]) == Array(second[0][2...]))
    _ = try driver.encode(.stopRumble)
    #expect(driver.keepAliveWrites().isEmpty)
  }

  @Test
  func aReceiverResendsOnlyWhileItsControllerIsConnected() throws {
    let driver = try #require(
      XUSBDriver(slotOrdinal: 0, rumbleTemplate: try Self.usbTemplate(resend: 25))
    )
    _ = driver.decode(Data([0x08, 0x80]))
    let sent = try driver.encode(.setRumble(Self.running, duration: .held)).writes
    #expect(usbBytes(driver.keepAliveWrites()) == usbBytes(sent))
    _ = driver.decode(Data([0x08, 0x00]))
    #expect(driver.keepAliveWrites().isEmpty)
    _ = driver.decode(Data([0x08, 0x80]))
    #expect(driver.keepAliveWrites().isEmpty)
  }

  @Test
  func reportLayoutResendsOnTheHIDChannel() throws {
    let layout = try inputLayout(
      #"{"report": {"length": {"atLeast": 2}}, "#
        + #""buttons": [{"control": "South", "bitOffset": 8, "bitSize": 1}]}"#
    )
    let driver = ReportLayoutDriver(
      layouts: try ControllerInputLayouts(layouts: [layout]),
      rumbleTemplate: try Self.hidTemplate(resend: 20)
    )
    #expect(driver.sessionPlan.hidKeepAliveIntervalNanoseconds == 20_000_000)
    #expect(driver.keepAliveWrites().isEmpty)
    let sent = try driver.encode(.setRumble(Self.running, duration: .held)).writes
    #expect(hidBytes(driver.keepAliveWrites()) == hidBytes(sent))
    _ = try driver.encode(.stopRumble)
    #expect(driver.keepAliveWrites().isEmpty)
    let plain = ReportLayoutDriver(
      layouts: try ControllerInputLayouts(layouts: [layout]),
      rumbleTemplate: try Self.hidTemplate(resend: nil)
    )
    #expect(plain.sessionPlan.hidKeepAliveIntervalNanoseconds == nil)
  }

  @Test
  func ps3ThirdPartyResendsOnTheHIDChannel() throws {
    let driver = PS3ThirdPartyDriver(
      model: ControllerModelID(vendorID: 0x0E8F, productID: 0x3075),
      rumbleTemplate: try Self.hidTemplate(resend: 35)
    )
    #expect(driver.sessionPlan.hidKeepAliveIntervalNanoseconds == 35_000_000)
    let sent = try driver.encode(.setRumble(Self.running, duration: .held)).writes
    #expect(hidBytes(driver.keepAliveWrites()) == hidBytes(sent))
    driver.resetProtocolState()
    #expect(driver.keepAliveWrites().isEmpty)
  }

  @Test
  func aJoyConResendFollowsItsSideFilter() throws {
    let both = RumbleIntensities(
      lowFrequency: UnipolarValue(0x8000),
      highFrequency: UnipolarValue(0x4000)
    )
    let rightOnly = RumbleIntensities(highFrequency: UnipolarValue(0x4000))
    let left = Switch1Driver(
      layout: .leftJoyCon,
      rumbleTemplate: try Self.hidTemplate(resend: 50)
    )
    _ = try left.encode(.setRumble(rightOnly, duration: .held))
    #expect(left.keepAliveWrites().isEmpty)
    let side = hidBytes(try left.encode(.setRumble(both, duration: .held)).writes)
    let resent = hidBytes(left.keepAliveWrites())
    #expect(resent.count == 1)
    #expect(Array(resent[0][2...]) == Array(side[0][2...]))
  }

  @Test
  func switch1WithoutAResendIntervalHasNoKeepAlive() throws {
    let driver = Switch1Driver(rumbleTemplate: try Self.hidTemplate(resend: nil))
    _ = try driver.encode(.setRumble(Self.running, duration: .held))
    #expect(driver.sessionPlan.hidKeepAliveIntervalNanoseconds == nil)
    #expect(driver.keepAliveWrites().isEmpty)
  }
}
