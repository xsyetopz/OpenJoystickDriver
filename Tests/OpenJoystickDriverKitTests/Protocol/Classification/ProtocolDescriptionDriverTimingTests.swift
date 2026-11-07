import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Each family timing a driver reads comes from the family's description, and a record's tuning
/// overrides it.
@Suite
struct ProtocolDescriptionDriverTimingTests {
  private static let millisecond = DeviceTransportProfile.nanosecondsPerMillisecond

  @Test
  func steamTritonReadsTheLizardResend() {
    #expect(SteamTritonDriver().lizardResendTicks == 75)
    #expect(SteamTritonDriver(tuning: .init(lizardResendTicks: 9)).lizardResendTicks == 9)
  }

  @Test
  func switch2ReadsTheCommandChannel() {
    let channel = PhysicalProtocolID.nintendoSwitch2.protocolDescription.commandChannel
    #expect(channel?.interface == 1)
    #expect(channel?.inEndpoint == 0x82)
    #expect(channel?.replyLength == 0x50)
    #expect(channel?.usbReplyTimeoutMilliseconds == 100)
    #expect(channel?.bluetoothLEReplyTimeoutMilliseconds == 500)
    let usb = Switch2Driver(link: .usb).sessionPlan.usbCommandChannel
    #expect(usb?.interfaceNumber == 1)
    #expect(usb?.inEndpoint == 0x82)
    #expect(usb?.replyLength == 0x50)
    #expect(usb?.replyTimeoutMilliseconds == 100)
    let bluetoothLE = Switch2Driver(link: .bluetoothLE).sessionPlan.usbCommandChannel
    #expect(bluetoothLE?.replyTimeoutMilliseconds == 500)
  }

  @Test
  func switch2ReadsTheTrailingStopPackets() {
    let count = PhysicalProtocolID.nintendoSwitch2.described(limit: \.trailingStopPackets)
    #expect(count == 2)
    let driver = Switch2Driver(layout: .pro)
    let half = RumbleIntensities(lowFrequency: UnipolarValue(0x8000), highFrequency: .min)
    _ = driver.encoded(.setRumble(half, duration: .milliseconds(100)))
    _ = driver.encoded(.stopRumble)
    let stops = (0..<(count + 2)).map { _ in driver.keepAliveWrites().hidOutputs.count }
    #expect(stops == [Int](repeating: 1, count: count) + [0, 0])
  }

  @Test
  func switch2ReadsTheCommandTimeout() {
    #expect(Switch2Driver().commandTimeoutMilliseconds == 1_000)
    let tuned = Switch2Driver(tuning: .init(usbCommandTimeoutMilliseconds: 250))
    #expect(tuned.commandTimeoutMilliseconds == 250)
    guard case .usb(let packet, _) = tuned.command([0, 0, 0]) else {
      Issue.record("a Switch 2 command is a USB write")
      return
    }
    #expect(packet.timeoutMilliseconds == 250)
  }

  @Test
  func gameSirReadsTheUSBTimeout() {
    #expect(GameSirDriver(protocol: .g7ProUSB).usbTimeoutMilliseconds == 2_000)
    let tuned = GameSirDriver(
      protocol: .g7ProUSB,
      tuning: .init(usbCommandTimeoutMilliseconds: 300)
    )
    #expect(tuned.usbTimeoutMilliseconds == 300)
  }

  @Test
  func gipReadsTheAnnounceResendAndTheHandshakePacing() {
    let driver = GIPDriver()
    #expect(driver.announceResendInterval == 4)
    #expect(driver.sessionPlan.usbStartupIntervalNanoseconds == 50 * Self.millisecond)
    #expect(
      driver.sessionPlan.usbStartupRetryDelays == [
        1_000 * Self.millisecond, 2_000 * Self.millisecond,
      ]
    )
    let tuning = ControllerTuning(
      presenceResendReports: 6,
      usbStartupIntervalMilliseconds: 10,
      usbStartupRetryDelayMilliseconds: 100
    )
    #expect(GIPDriver(tuning: tuning).announceResendInterval == 6)
    let plan = driver.sessionPlan.tuned(tuning)
    #expect(plan.usbStartupIntervalNanoseconds == 10 * Self.millisecond)
    #expect(plan.usbStartupRetryDelays == [100 * Self.millisecond, 200 * Self.millisecond])
  }

  @Test
  func gipReadsTheHandshakeAttemptsAndTheAnnounceResendLimit() {
    let description = PhysicalProtocolID.xboxGIP.protocolDescription
    #expect(description.handshakeAttempts == 3)
    #expect(description.announceResendLimit == 8)
    #expect(GIPDriver().sessionPlan.usbStartupRetryDelays.count == 2)
  }

  @Test
  func xusbReadsTheTransferTimeout() {
    #expect(XUSBDriver().usbTimeoutMilliseconds == 2_000)
    #expect(
      XUSBDriver(tuning: .init(usbTransferTimeoutMilliseconds: 750)).usbTimeoutMilliseconds == 750
    )
  }

  @Test
  func xidReadsTheTransferTimeout() {
    let plain = try? xidDriver().encode(.stopRumble)
    #expect(plain.onlyPacket.timeoutMilliseconds == 2_000)
    let tuned = xidDriver(tuning: .init(usbTransferTimeoutMilliseconds: 750))
    let plan = try? tuned.encode(.stopRumble)
    #expect(plan.onlyPacket.timeoutMilliseconds == 750)
  }

  @Test
  func sonyAdaptersReadTheDisconnectDelay() {
    #expect(DualShock4Driver().adapterDisconnectNanoseconds == 500 * Self.millisecond)
    #expect(DualSenseDriver().dongleDisconnectNanoseconds == 500 * Self.millisecond)
    let tuning = ControllerTuning(adapterDisconnectDelayMilliseconds: 40)
    #expect(DualShock4Driver(tuning: tuning).adapterDisconnectNanoseconds == 40 * Self.millisecond)
    #expect(DualSenseDriver(tuning: tuning).dongleDisconnectNanoseconds == 40 * Self.millisecond)
  }
}
