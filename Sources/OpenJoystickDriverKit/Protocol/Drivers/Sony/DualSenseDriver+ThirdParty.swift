import Foundation

let dualSenseSonyVendorID: UInt16 = 0x054C
/// SDL's `k_EPS5FeatureReportIdCapabilities`; a valid reply is 48 bytes with `0x28` at byte 2.
let dualSenseCapabilitiesReportID: UInt8 = 0x03
let dualSenseCapabilitiesReportLength = 48
let dualSenseCapabilitiesMarker: UInt8 = 0x28
/// SDL's `BLUETOOTH_DISCONNECT_TIMEOUT_MS`, which it also applies to third-party dongles.
let dualSenseDongleDisconnectNanoseconds: UInt64 = 500_000_000
/// SDL's `PS5StatePacketAlt_t` is 48 bytes; SDL checks a dongle's sequence only in a full packet.
let dualSenseAlternatePayloadLength = 48

/// The features of a DualSense-protocol controller. Sony controllers have all of them;
/// third-party controllers report theirs through SDL's capability probe.
struct DualSenseFeatures: OptionSet {
  let rawValue: UInt8

  static let sensors = Self(rawValue: 0x01)
  static let lightbar = Self(rawValue: 0x02)
  static let vibration = Self(rawValue: 0x04)
  static let touchpad = Self(rawValue: 0x08)
  static let playerIndicator = Self(rawValue: 0x10)
  static let all: Self = [.sensors, .lightbar, .vibration, .touchpad, .playerIndicator]

  /// Decodes SDL's capability reply: byte 4 carries sensors `0x02`, lightbar `0x04`, vibration
  /// `0x08` and touchpad `0x40`; byte 20 carries the player indicator `0x80`.
  init?(capabilityReply bytes: [UInt8]) {
    guard bytes.count == dualSenseCapabilitiesReportLength,
      bytes[0] == dualSenseCapabilitiesReportID, bytes[2] == dualSenseCapabilitiesMarker
    else { return nil }
    var features: Self = []
    for (mask, feature) in [
      (UInt8(0x02), Self.sensors), (0x04, .lightbar), (0x08, .vibration), (0x40, .touchpad),
    ] where bytes[4] & mask != 0 { features.insert(feature) }
    if bytes[20] & 0x80 != 0 { features.insert(.playerIndicator) }
    self = features
  }

  init(rawValue: UInt8) { self.rawValue = rawValue }
}

/// A non-Sony controller that speaks the DualSense protocol, handled as SDL's
/// `HIDAPI_DriverPS5` handles non-Sony vendor IDs.
///
/// SDL reads capability report `0x03`. A valid reply lists the controller's features and
/// switches it to SDL's alternate input report, which moves the touch contacts to payload bytes
/// 31 and 35 and carries a 16-bit microsecond sensor timestamp at 27. A controller that does not
/// answer keeps the standard report with no sensors, touchpad or output, except the Razer models
/// SDL names, which never answer. Output is limited to the reported features and never includes
/// adaptive triggers.
struct DualSenseThirdPartyModel: Equatable {
  /// Features assumed before the probe, which stand when the controller does not answer.
  let unprobedFeatures: DualSenseFeatures
  /// Whether the controller sends the alternate report without answering the probe.
  let usesAlternateReportUnprobed: Bool
  /// Whether a valid probe reply omits vibration that the controller has.
  let forcesVibration: Bool
  /// A wireless receiver that keeps reporting while no controller is paired to it.
  let isDongle: Bool

  init(vendorID: UInt16, productID: UInt16) {
    let identity = [vendorID, productID]
    switch identity {
    // Razer Wolverine V2 Pro wired and wireless: sensors and touchpad, no vibration.
    case [0x1532, 0x100B], [0x1532, 0x100C]:
      unprobedFeatures = [.sensors, .touchpad]
      usesAlternateReportUnprobed = true
    // Razer Kitsune and Raiju V3 Pro wired and wireless: touchpad only.
    case [0x1532, 0x1012], [0x1532, 0x1024], [0x1532, 0x1026]:
      unprobedFeatures = [.touchpad]
      usesAlternateReportUnprobed = true
    default:
      unprobedFeatures = []
      usesAlternateReportUnprobed = false
    }
    // NACON Revolution 5 Pro wired and wireless.
    forcesVibration = identity == [0x3285, 0x0D18] || identity == [0x3285, 0x0D19]
    isDongle = [[0x3285, 0x0D18], [0x1532, 0x100C], [0x1532, 0x1026]].contains(identity)
  }
}

extension DualSenseDriver {
  /// Installs the probe result: the reported features and the alternate report.
  func applyCapabilityReply(_ bytes: [UInt8]) -> Bool {
    guard let thirdParty, var reported = DualSenseFeatures(capabilityReply: bytes) else {
      return false
    }
    if thirdParty.forcesVibration { reported.insert(.vibration) }
    features = reported
    useAlternateReport()
    return true
  }

  /// SDL's alternate report counts sensor time in microseconds in 16 bits.
  func useAlternateReport() {
    guard !usesAlternateReport else { return }
    usesAlternateReport = true
    sensorClock = SonySensorClock(mask: 0xFFFF, tickNumerator: 3000)
  }

  /// SDL's dongle check: a dongle repeats its last packet sequence while no controller is
  /// connected. The first packet only anchors the sequence. A repeat for 500 ms disconnects the
  /// controller; a new sequence connects it. Returns whether the report carries live input.
  func acceptsDongleReport(_ payload: [UInt8], receivedAt: UInt64) -> Bool {
    guard thirdParty?.isDongle == true, payload.count >= dualSenseAlternatePayloadLength else {
      return true
    }
    let sequence = payload[11..<15].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    defer { lastPacketSequence = sequence }
    guard let previous = lastPacketSequence else { return false }
    guard sequence != previous else {
      if dongleConnected, let lastLiveReportAt,
        receivedAt &- lastLiveReportAt >= dualSenseDongleDisconnectNanoseconds
      {
        setDongleConnected(false)
      }
      return false
    }
    lastLiveReportAt = receivedAt
    if !dongleConnected { setDongleConnected(true) }
    return true
  }

  private func setDongleConnected(_ connected: Bool) {
    dongleConnected = connected
    pendingConnectionState = connected ? .connected : .disconnected
    if !connected {
      state = .neutral
      sensorClock.reset()
    }
  }

  func resetDonglePresence() {
    lastPacketSequence = nil
    lastLiveReportAt = nil
    dongleConnected = false
    pendingConnectionState = nil
  }
}
