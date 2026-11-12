import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var nanoseconds: UInt64 = 1_000

  var now: UInt64 { lock.withLock { nanoseconds } }

  func advance(minutes: UInt64) { lock.withLock { nanoseconds += minutes * 60 * 1_000_000_000 } }
}

@Suite
struct IdleDisconnectTests {
  private let clock = TestClock()

  private func pipeline(variant: PhysicalProtocolVariantID) -> DevicePipeline {
    let clock = clock
    return DevicePipeline(
      identifier: LogicalControllerID(vendorID: 1, productID: 2),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: HIDDescriptorDriver(model: ControllerModelID(vendorID: 1, productID: 2)),
      dispatcher: CapturingOutputDispatcher(),
      binding: ProtocolBinding(
        protocolID: .hidDescriptor,
        variant: variant,
        accessBackend: .hid,
        interfaceNumber: nil,
        rule: .catalogRecord,
        matchedPredicates: [],
        record: nil
      )
    ) { clock.now }
  }

  private func report(_ state: ControllerState) -> ControllerEvent {
    ControllerEvent(timestamp: MonotonicTimestamp(nanoseconds: clock.now), state: state)
  }

  private var pressed: ControllerState { ControllerState.neutral.applying([.press(.south)]) }

  @Test
  func theSettingIsOffOnAFreshInstallation() throws {
    let store = SettingsStore(directory: RootedDataDirectory.temporary())

    #expect(try store.idleDisconnectMinutes() == nil)
    #expect(try store.load().idleDisconnectMinutes == nil)
  }

  @Test
  func theSettingRoundTripsThroughTheUserFile() throws {
    let store = SettingsStore(directory: RootedDataDirectory.temporary())

    try store.setIdleDisconnectMinutes(15)
    #expect(try store.idleDisconnectMinutes() == 15)

    try store.setIdleDisconnectMinutes(nil)
    #expect(try store.idleDisconnectMinutes() == nil)
  }

  @Test
  func fifteenMinutesWithoutChangedInputOnBluetoothIsDue() async {
    let pipeline = pipeline(variant: .bluetoothClassic)

    clock.advance(minutes: 14)
    #expect(await pipeline.isIdleDisconnectDue(afterMinutes: 15) == false)

    clock.advance(minutes: 1)
    #expect(await pipeline.isIdleDisconnectDue(afterMinutes: 15))
  }

  @Test
  func changedInputRestartsTheTime() async {
    let pipeline = pipeline(variant: .bluetoothClassic)
    clock.advance(minutes: 14)

    await pipeline.handleParsedEvent(report(pressed), now: clock.now)
    clock.advance(minutes: 14)

    #expect(await pipeline.isIdleDisconnectDue(afterMinutes: 15) == false)
    clock.advance(minutes: 1)
    #expect(await pipeline.isIdleDisconnectDue(afterMinutes: 15))
  }

  @Test
  func repeatedUnchangedReportsDoNotRestartTheTime() async {
    let pipeline = pipeline(variant: .bluetoothClassic)
    await pipeline.handleParsedEvent(report(pressed), now: clock.now)

    for _ in 0..<5 {
      clock.advance(minutes: 3)
      await pipeline.handleParsedEvent(report(pressed), now: clock.now)
    }

    #expect(await pipeline.isIdleDisconnectDue(afterMinutes: 15))
  }

  /// macOS keeps a Bluetooth LE HID link up after `IOBluetoothDevice.closeConnection()` returns
  /// success, so no idle disconnect can end it.
  @Test(arguments: [PhysicalProtocolVariantID.usb, .wired, .receiver, .dongle, .bluetoothLE])
  func aCableReceiverOrBluetoothLELinkNeverDisconnects(variant: PhysicalProtocolVariantID) async {
    let pipeline = pipeline(variant: variant)

    clock.advance(minutes: 600)

    #expect(await pipeline.isIdleDisconnectDue(afterMinutes: 15) == false)
  }

  @Test
  func restartingTheWindowDelaysTheNextAttempt() async {
    let pipeline = pipeline(variant: .bluetoothClassic)
    clock.advance(minutes: 15)

    await pipeline.restartIdleWindow()

    #expect(await pipeline.isIdleDisconnectDue(afterMinutes: 15) == false)
    clock.advance(minutes: 15)
    #expect(await pipeline.isIdleDisconnectDue(afterMinutes: 15))
  }
}
