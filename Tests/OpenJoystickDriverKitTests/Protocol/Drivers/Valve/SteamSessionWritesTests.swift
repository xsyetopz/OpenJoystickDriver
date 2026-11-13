import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The activation and deactivation reports of the three Valve drivers, byte for byte and in
/// order: SDL `ResetSteamController`, `DisableDeckLizardMode` and the Triton settings, with
/// Linux `hid-steam.c` for the restore.
@Suite("Valve session writes")
struct SteamSessionWritesTests {
  private func padded(_ prefix: [UInt8], to length: Int) -> [UInt8] {
    prefix + [UInt8](repeating: 0, count: length - prefix.count)
  }

  private func reports(_ writes: [PhysicalOutputWrite]) -> [(id: UInt8, bytes: [UInt8])] {
    writes.hidFeatures.map { ($0.reportID, $0.bytes) }
  }

  private func expect(
    _ writes: [PhysicalOutputWrite],
    equal expected: [(id: UInt8, bytes: [UInt8])]
  ) {
    let actual = reports(writes)
    #expect(actual.count == expected.count)
    for (actual, expected) in zip(actual, expected) {
      #expect(actual.id == expected.id)
      #expect(actual.bytes == expected.bytes)
    }
  }

  /// The USB activation follows SDL `ResetSteamController`.
  ///
  /// It sends `81`, `8E 00`, then one settings write with
  /// `SETTING_LEFT_TRACKPAD_MODE` (7) and `SETTING_RIGHT_TRACKPAD_MODE` (8) set to `TRACKPAD_NONE`
  /// (7), `SETTING_SMOOTH_ABSOLUTE_MOUSE` (24) set to 0 and `SETTING_IMU_MODE` (48) set to `0x18`.
  /// Not checked on hardware (task H5).
  @Test
  func steamControllerActivationOverUSBLoadsDefaultsAndClearsSmoothAbsoluteMouse() {
    let driver = SteamControllerDriver()
    expect(
      driver.activationWrites(),
      equal: [
        (0, padded([0x81], to: 64)),
        (0, padded([0x8E, 0], to: 64)),
        (0, padded([0x87, 12, 7, 7, 0, 8, 7, 0, 24, 0, 0, 48, 0x18, 0], to: 64)),
      ]
    )
  }

  /// The same sequence in report-3 segments of 20 bytes, with `SETTING_WIRELESS_PACKET_VERSION`
  /// (49) set to 2 after the four settings.
  @Test
  func steamControllerActivationOverBluetoothLEFramesSameSequence() {
    let driver = SteamControllerDriver(isBluetooth: true)
    expect(
      driver.activationWrites(),
      equal: [
        (3, padded([0x03, 0xC0, 0x81], to: 20)),
        (3, padded([0x03, 0xC0, 0x8E], to: 20)),
        (
          3,
          padded(
            [0x03, 0xC0, 0x87, 15, 7, 7, 0, 8, 7, 0, 24, 0, 0, 48, 0x18, 0, 49, 2, 0],
            to: 20
          )
        ),
      ]
    )
  }

  @Test
  func steamControllerOverUSB() {
    let driver = SteamControllerDriver()
    expect(
      driver.deactivationWrites(),
      equal: [(0, padded([0x85], to: 64)), (0, padded([0x8E], to: 64))]
    )
  }

  @Test
  func steamControllerOverBluetoothLE() {
    let driver = SteamControllerDriver(isBluetooth: true)
    expect(
      driver.deactivationWrites(),
      equal: [(3, padded([0x03, 0xC0, 0x85], to: 20)), (3, padded([0x03, 0xC0, 0x8E], to: 20))]
    )
  }

  @Test
  func steamDeck() {
    let driver = SteamDeckDriver()
    expect(
      driver.activationWrites(),
      equal: [
        (0, padded([0x81], to: 64)),
        (
          0,
          padded(
            [0x87, 18, 24, 0, 0, 7, 7, 0, 8, 7, 0, 52, 0xFF, 0xFF, 53, 0xFF, 0xFF, 71, 0, 0],
            to: 64
          )
        ),
      ]
    )
    expect(
      driver.deactivationWrites(),
      equal: [(0, padded([0x85], to: 64)), (0, padded([0x8E], to: 64))]
    )
  }

  @Test
  func steamTriton() {
    let driver = SteamTritonDriver()
    expect(
      driver.activationWrites(),
      equal: [
        (1, padded([0x01, 0x87, 3, 9, 0, 0], to: 64)),
        (1, padded([0x01, 0x87, 3, 48, 0x18, 0], to: 64)),
      ]
    )
    expect(driver.deactivationWrites(), equal: [(1, padded([0x01, 0x87, 3, 48, 0, 0], to: 64))])
  }
}
