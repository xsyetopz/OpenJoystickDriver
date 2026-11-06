import Foundation

/// Payload byte (after the USB report ID) whose bit 2 is set while Sony's wireless adapter has no
/// pad connected; SDL `HIDAPI_DriverPS4_IsPacketValid` reads it as `data[31] & 0x04`.
let ds4AdapterStatusOffset = 30
/// The bit of the adapter status byte that is set while the adapter has no pad connected.
let ds4AdapterNoPadFlag: UInt8 = 0x04

/// Sony DualShock 4 hardware that SDL `SDL_hidapi_ps4.c` handles differently from a plain pad.
public enum DualShock4Model: Equatable, Sendable {
  /// A DualShock 4 without model-specific behavior.
  case standard
  /// Sony's wireless adapter (`054C:0BA0`, SDL `USB_PRODUCT_SONY_DS4_DONGLE`). It sends USB
  /// reports for a paired pad, flags reports sent without one, and returns USB calibration in
  /// the Bluetooth gyro endpoint order.
  case wirelessAdapter
  /// STRIKEPAD grip (`054C:05C5`, SDL `USB_PRODUCT_SONY_DS4_STRIKEPAD`). SDL doubles its gyro
  /// scale and doubles and negates its accelerometer scale: "The Armor-X Pro seems to only deliver
  /// half the acceleration it should, and in the opposite direction on all axes".
  case strikePad

  /// The model a controller record selects with the `WirelessAdapter` role or the `StrikePad`
  /// motion scale.
  public init(parameters: ProtocolParameters) {
    if parameters.role == .wirelessAdapter {
      self = .wirelessAdapter
    } else if parameters.motionScale == .strikePad {
      self = .strikePad
    } else {
      self = .standard
    }
  }

  /// Returns `calibration`, scaled by the Strike Pad's gyro and accelerometer factors for that
  /// model.
  func scaled(_ calibration: SonyMotionCalibration) -> SonyMotionCalibration {
    self == .strikePad ? calibration.scaled(gyro: 2, accel: -2) : calibration
  }
}

extension DualShock4Driver {
  /// Returns and clears the connection change that is pending.
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? {
    defer { pendingConnectionState = nil }
    return pendingConnectionState
  }

  /// SDL's adapter presence: a report without the no-pad flag connects the pad; flagged reports for
  /// 500 ms after the last live one disconnect it.
  ///
  /// Returns whether the report carries input.
  func acceptsAdapterReport(_ payload: [UInt8], receivedAt: UInt64) -> Bool {
    guard model == .wirelessAdapter, payload.count > ds4AdapterStatusOffset else { return true }
    guard payload[ds4AdapterStatusOffset] & ds4AdapterNoPadFlag == 0 else {
      if adapterPadConnected, let lastAdapterPadReportAt,
        receivedAt &- lastAdapterPadReportAt >= adapterDisconnectNanoseconds
      {
        setAdapterPadConnected(false)
      }
      return false
    }
    lastAdapterPadReportAt = receivedAt
    if !adapterPadConnected { setAdapterPadConnected(true) }
    return true
  }

  /// Forgets the adapter's pad connection, so the next report decides it again.
  func resetAdapterPresence() {
    adapterPadConnected = false
    lastAdapterPadReportAt = nil
    pendingConnectionState = nil
  }

  /// Records whether the adapter has a pad connected and queues the change; a disconnect resets the
  /// input state, the sensor clock and the sensor timestamp.
  private func setAdapterPadConnected(_ connected: Bool) {
    adapterPadConnected = connected
    pendingConnectionState = connected ? .connected : .disconnected
    if !connected {
      state = .neutral
      sensorClock.reset()
      previousSensorTimestamp = nil
    }
  }
}
