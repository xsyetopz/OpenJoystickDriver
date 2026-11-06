import Foundation

/// The first byte of a 64-byte raw event.
let steamControllerReportPrefix0: UInt8 = 0x01
/// The second byte of a raw event.
let steamControllerReportPrefix1: UInt8 = 0x00
/// The message type of a controller state payload.
let steamControllerStateMessageID: UInt8 = 0x01
/// The message type of a wireless status message.
let steamControllerWirelessMessageID: UInt8 = 0x03
/// The message type of the status message that shows a receiver's controller is connected.
let steamControllerStatusMessageID: UInt8 = 0x04
/// The length of a raw event in bytes.
let steamControllerReportLength = 64
/// The maximum value of an analog trigger.
let steamControllerTriggerMax: Float = 255
/// The maximum positive value of a signed stick or pad axis.
let steamControllerStickMax: Float = 32767
/// The wireless status value of a disconnected controller.
let steamControllerWirelessDisconnected: UInt8 = 0x01
/// The wireless status value of a connected controller.
let steamControllerWirelessConnected: UInt8 = 0x02
/// The command byte of the set-settings feature report.
let steamControllerSetSettingsValuesCommand: UInt8 = 0x87
/// The command byte of the feature report that asks for the wireless state.
let steamControllerGetWirelessStateCommand: UInt8 = 0xB4
/// The command byte of the haptic pulse feature report.
let steamControllerHapticPulseCommand: UInt8 = 0x8F
/// The payload length of the haptic pulse command.
let steamControllerHapticPulsePayloadLength: UInt8 = 8
/// The settings id of the user LED brightness.
let steamControllerUserLEDBrightnessSetting: UInt8 = 45
/// The longest duration of one haptic pulse in microseconds.
let steamControllerMaximumPulseMicroseconds = 65_535
/// The length of the pulse that stands for a held rumble, which the pad cannot hold open-ended.
let steamControllerHeldPulseMilliseconds = 65

/// Driver for the Valve Steam Controller, wired, through its wireless receiver, or over Bluetooth
/// LE.
///
/// Linux `hid-steam.c` receives 64-byte raw events prefixed with `0x01, 0x00`. Message type `0x01`
/// carries a 60-byte controller state payload with button bytes at offsets 8-10, analog triggers at
/// 11-12, left stick/left pad axes at 16-19, and right pad axes at 20-23. The description's
/// activation and deactivation feature reports run when OJD starts and stops consuming the
/// controller. Over Bluetooth LE the same messages travel in report-`0x03` segments
/// (``SteamBluetooth``).
public final class SteamControllerDriver: PhysicalProtocolDriver {

  /// Decodes the IMU sample of each state packet.
  var motionSamples = SteamMotionSamples()
  /// Decodes the pad frames of each state packet.
  var touchSamples = SteamTouchSamples()
  /// The state after the latest state packet.
  var state = ControllerState.neutral
  /// The left stick's last raw position, which a report interleaving pad and stick keeps.
  var leftStickRaw: (x: Int16, y: Int16) = (0, 0)
  /// Whether the controller is reached through a wireless receiver.
  let isWirelessReceiver: Bool
  /// Whether the controller is the classic Steam Controller paired over Bluetooth LE, which frames
  /// reports in report-`0x03` segments.
  let isBluetooth: Bool
  /// Reassembles the segments of a Bluetooth LE report.
  var bluetoothAssembler = SteamBluetoothAssembler()
  /// Keeps the chunked Bluetooth LE state between packets.
  var bluetoothState = SteamBluetoothState()
  /// Whether a logical controller is connected; always true unless a receiver says otherwise.
  var isLogicalControllerConnected: Bool
  /// The connection change that ``consumeInputConnectionStateChange()`` has not returned.
  var pendingConnectionStateChange: ControllerInputConnectionState?

  /// Creates the driver for a controller reached through a wireless receiver when
  /// `isWirelessReceiver` is true, or over Bluetooth LE when `isBluetooth` is true.
  public init(isWirelessReceiver: Bool = false, isBluetooth: Bool = false) {
    self.isWirelessReceiver = isWirelessReceiver
    self.isBluetooth = isBluetooth
    isLogicalControllerConnected = !isWirelessReceiver
  }

  /// Clears the state of the session: neutral input, motion time re-anchored and Bluetooth LE
  /// framing dropped.
  public func resetProtocolState() {
    state = .neutral
    leftStickRaw = (0, 0)
    motionSamples.reset()
    bluetoothAssembler.reset()
    bluetoothState = SteamBluetoothState()
  }
}
