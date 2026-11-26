import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Reports in the layout of Dolphin `GCAdapter.cpp` and SDL `SDL_hidapi_gamecube.c`.
///
/// Report `0x21` is 37 bytes: the report ID, then nine bytes per port at `1 + 9 * port`, which are
/// status, two button bytes, main stick X and Y, C stick X and Y, and the L and R triggers. The
/// bridge script `gcadapter_bridge.py` reads the same offsets.
private enum AdapterReport {
  /// A wired pad with the second cable plugged in: status `0x14`.
  static let wiredPowered: UInt8 = 0x14
  /// A wired pad without the second cable.
  static let wired: UInt8 = 0x10
  /// A wireless pad.
  static let wireless: UInt8 = 0x20

  /// A report with each port in `ports` resting at the center, its bytes overridden by `bytes`,
  /// keyed by the offset within the port.
  static func report(
    _ ports: [Int: UInt8] = [0: wiredPowered],
    _ bytes: [Int: [Int: UInt8]] = [:]
  )
    -> Data
  {
    var report = [UInt8](repeating: 0, count: 37)
    report[0] = 0x21
    for (port, status) in ports {
      let base = 1 + 9 * port
      report[base] = status
      for offset in 3...6 { report[base + offset] = 128 }
      report[base + 7] = 40
      report[base + 8] = 40
    }
    for (port, values) in bytes {
      for (offset, value) in values { report[1 + 9 * port + offset] = value }
    }
    return Data(report)
  }

  /// A report with port 0 connected and its bytes overridden by `bytes`.
  static func port0(_ bytes: [Int: UInt8]) -> Data { report([0: wiredPowered], [0: bytes]) }
}

/// The bytes of the HID reports in `writes`.
private func rumbleBytes(_ writes: [PhysicalOutputWrite]) -> [[UInt8]] {
  writes.compactMap { if case .hidOutput(let report) = $0 { report.bytes } else { nil } }
}

private let rumbleOn = ControllerOutputCommand.setRumble(
  RumbleIntensities(lowFrequency: UnipolarValue(normalized: 1)),
  duration: .held
)

@Suite
struct GameCubeAdapterDriverTests {
  static let family = PhysicalProtocolID.nintendoGameCubeAdapter
  static let model = ControllerModelID(vendorID: 0x057E, productID: 0x0337)

  @Test
  func connectedPortAtRestIsNeutral() throws {
    let driver = try #require(GameCubeAdapterDriver(port: 0))
    #expect(try driver.parseReport(AdapterReport.port0([:]))?.state == .neutral)
  }

  @Test(arguments: [
    (1, 0x01, Control.south), (1, 0x04, .east), (1, 0x02, .west), (1, 0x08, .north),
    (2, 0x01, .start), (2, 0x02, .rightShoulder), (2, 0x08, .leftTrigger),
    (2, 0x04, .rightTrigger),
  ])
  func buttonsFollowSDLPositionalMapping(offset: Int, mask: UInt8, control: Control) throws {
    let driver = try #require(GameCubeAdapterDriver(port: 0))
    let event = try driver.parseReport(AdapterReport.port0([offset: mask]))
    #expect(event?.state == snapshot(.press(control)))
  }

  @Test
  func dPadBitsFormTheHat() throws {
    let driver = try #require(GameCubeAdapterDriver(port: 0))
    #expect(try driver.parseReport(AdapterReport.port0([1: 0x80]))?.state == snapshot(.hat(.north)))
    #expect(
      try driver.parseReport(AdapterReport.port0([1: 0x40 | 0x20]))?.state
        == snapshot(.hat(.southEast))
    )
    #expect(try driver.parseReport(AdapterReport.port0([1: 0x10]))?.state == snapshot(.hat(.west)))
  }

  @Test
  func sticksSpanEightyEightAroundCenterWithYInverted() throws {
    let driver = try #require(GameCubeAdapterDriver(port: 0))
    let event = try driver.parseReport(AdapterReport.port0([3: 216, 4: 216, 5: 40, 6: 40]))
    #expect(event?.state == snapshot(.leftStick(x: 1, y: -1), .rightStick(x: -1, y: 1)))
  }

  @Test
  func triggersRunFrom40To216() throws {
    let driver = try #require(GameCubeAdapterDriver(port: 0))
    let event = try driver.parseReport(AdapterReport.port0([7: 216, 8: 40]))
    #expect(event?.state == snapshot(.leftTrigger(1)))
  }

  @Test
  func rangeWidensToObservedExtremesAndResetsOnReconnect() throws {
    let driver = try #require(GameCubeAdapterDriver(port: 0))
    _ = try driver.parseReport(AdapterReport.port0([3: 255]))
    let widened = try driver.parseReport(AdapterReport.port0([3: 216]))
    #expect(widened?.state != snapshot(.leftStick(x: 1, y: 0)))
    _ = try driver.parseReport(AdapterReport.report([:]))
    let reconnected = try driver.parseReport(AdapterReport.port0([3: 216]))
    #expect(reconnected?.state == snapshot(.leftStick(x: 1, y: 0)))
  }

  @Test
  func statusChangesQueueConnectAndDisconnect() throws {
    let driver = try #require(GameCubeAdapterDriver(port: 0))
    _ = try driver.parseReport(AdapterReport.report([:]))
    #expect(driver.consumeInputConnectionStateChange() == nil)
    _ = try driver.parseReport(AdapterReport.port0([1: 0x01]))
    #expect(driver.consumeInputConnectionStateChange() == .connected)
    #expect(driver.consumeInputConnectionStateChange() == nil)
    let empty = try driver.parseReport(AdapterReport.report([:]))
    #expect(driver.consumeInputConnectionStateChange() == .disconnected)
    #expect(empty?.state == .neutral)
  }

  @Test
  func eachPortReadsOnlyItsOwnBytes() throws {
    let port0 = try #require(GameCubeAdapterDriver(port: 0))
    let port3 = try #require(GameCubeAdapterDriver(port: 3))
    let report = AdapterReport.report(
      [0: AdapterReport.wired, 3: AdapterReport.wireless],
      [3: [1: 0x01]]
    )
    #expect(try port0.parseReport(report)?.state == .neutral)
    #expect(try port3.parseReport(report)?.state == snapshot(.press(.south)))
  }

  @Test
  func otherReportsAreIgnored() throws {
    let driver = try #require(GameCubeAdapterDriver(port: 0))
    #expect(try driver.parseReport(Data(AdapterReport.port0([:]).prefix(36))) == nil)
    var wrongID = [UInt8](AdapterReport.port0([:]))
    wrongID[0] = 0x22
    #expect(try driver.parseReport(Data(wrongID)) == nil)
  }

  @Test(arguments: [-1, 4])
  func portOutsideTheAdapterHasNoDriver(port: Int) {
    #expect(GameCubeAdapterDriver(port: port) == nil)
  }

  @Test
  func onlyPortZeroSendsTheStartReport() throws {
    let port0 = try #require(GameCubeAdapterDriver(port: 0))
    let port1 = try #require(GameCubeAdapterDriver(port: 1))
    #expect(rumbleBytes(port0.startupWrites()) == [[0x13]])
    #expect(port1.startupWrites().isEmpty)
  }

  @Test
  func portsSharingABankWriteEveryPortsMotor() throws {
    let bank = GameCubeAdapterRumbleBank()
    let port0 = try #require(GameCubeAdapterDriver(port: 0, rumbleBank: bank))
    let port2 = try #require(GameCubeAdapterDriver(port: 2, rumbleBank: bank))
    let report = AdapterReport.report([
      0: AdapterReport.wiredPowered, 2: AdapterReport.wiredPowered,
    ])
    _ = try port0.parseReport(report)
    _ = try port2.parseReport(report)
    #expect(rumbleBytes(try port0.encode(rumbleOn).writes) == [[0x11, 1, 0, 0, 0]])
    #expect(rumbleBytes(try port2.encode(rumbleOn).writes) == [[0x11, 1, 0, 1, 0]])
    #expect(rumbleBytes(try port0.encode(.stopRumble).writes) == [[0x11, 0, 0, 1, 0]])
  }

  @Test
  func rumbleNeedsAWiredPadAndTheSecondCable() throws {
    let wireless = try #require(GameCubeAdapterDriver(port: 0))
    _ = try wireless.parseReport(AdapterReport.report([0: AdapterReport.wireless]))
    #expect(throws: ControllerOutputError.unsupportedCapability(rumbleOn.capability)) {
      try wireless.encode(rumbleOn)
    }
    let unpowered = try #require(GameCubeAdapterDriver(port: 0))
    _ = try unpowered.parseReport(AdapterReport.report([0: AdapterReport.wired]))
    #expect(throws: ControllerOutputError.notReady) { try unpowered.encode(rumbleOn) }
    let empty = try #require(GameCubeAdapterDriver(port: 0))
    #expect(throws: ControllerOutputError.notReady) { try empty.encode(rumbleOn) }
    #expect(rumbleBytes(try empty.encode(.stopRumble).writes) == [[0x11, 0, 0, 0, 0]])
  }

  @Test
  func keepAliveResendsWhileAMotorRunsAndOnceAfterTheStop() throws {
    let driver = try #require(GameCubeAdapterDriver(port: 1))
    _ = try driver.parseReport(AdapterReport.report([1: AdapterReport.wiredPowered]))
    #expect(driver.keepAliveWrites().isEmpty)
    _ = try driver.encode(rumbleOn)
    #expect(rumbleBytes(driver.keepAliveWrites()) == [[0x11, 0, 1, 0, 0]])
    #expect(rumbleBytes(driver.keepAliveWrites()) == [[0x11, 0, 1, 0, 0]])
    _ = try driver.parseReport(AdapterReport.report([:]))
    #expect(rumbleBytes(driver.keepAliveWrites()) == [[0x11, 0, 0, 0, 0]])
    #expect(driver.keepAliveWrites().isEmpty)
  }
}
