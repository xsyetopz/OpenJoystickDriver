import Foundation

/// What a Wii Remote session shows a user: the report mode, the extension and the gyro state.
///
/// Only the Wii Remote driver reports it; every other family leaves
/// ``ControllerConnectionState/wiiRemote`` nil.
public struct WiiRemoteStatus: Codable, Equatable, Sendable {
  /// The extension kinds of `nintendo-wii.plist`, by the description's kind name.
  public enum ExtensionKind: String, Codable, CaseIterable, Sendable {
    /// The Nunchuk.
    case nunchuk = "Nunchuk"
    /// The Classic Controller.
    case classicController = "ClassicController"
    /// The Classic Controller Pro.
    case classicControllerPro = "ClassicControllerPro"
    /// A Motion Plus that is not active.
    case motionPlusInactive = "MotionPlusInactive"
    /// An active Motion Plus with nothing behind it.
    case motionPlus = "MotionPlus"
    /// An active Motion Plus with a Nunchuk behind it.
    case motionPlusNunchuk = "MotionPlusNunchuk"
    /// An active Motion Plus with a Classic Controller behind it.
    case motionPlusClassic = "MotionPlusClassic"
  }

  /// The report mode the driver chose, the third byte of its `0x12` write (`ReportModeSelect`).
  public let reportMode: UInt8
  /// The extension the handshake identified; nil while none is plugged, the ID is unknown or it
  /// is unread.
  public let extensionKind: ExtensionKind?
  /// The six ID bytes of an extension the table lacks, as twelve uppercase hex digits
  /// (`UnknownExtension`).
  public let unknownExtensionID: String?
  /// Whether the driver activated Motion Plus.
  public let motionPlusActive: Bool
  /// Whether the gyro rest offset is measured; false is calibrating (`GyroRestOffset`).
  public let isGyroRestReady: Bool

  /// Creates the status from its facts.
  public init(
    reportMode: UInt8,
    extensionKind: ExtensionKind?,
    unknownExtensionID: String?,
    motionPlusActive: Bool,
    isGyroRestReady: Bool
  ) {
    self.reportMode = reportMode
    self.extensionKind = extensionKind
    self.unknownExtensionID = unknownExtensionID
    self.motionPlusActive = motionPlusActive
    self.isGyroRestReady = isGyroRestReady
  }
}

extension WiiRemoteStatus {
  /// The report mode as the hex byte, such as `0x31`.
  public var reportModeText: String { String(format: "0x%02X", reportMode) }

  /// The extension in the user's language: its name, the unknown ID, or none.
  public func extensionText(_ localization: Localization = Localization()) -> String {
    if let extensionKind { return localization.string(extensionKind.localizationKey) }
    if let unknownExtensionID {
      return localization.string("status.wiiExtensionUnknown", unknownExtensionID)
    }
    return localization.string("status.none")
  }

  /// The Motion Plus state in the user's language: off, or the gyro calibrating or ready.
  public func motionPlusText(_ localization: Localization = Localization()) -> String {
    guard motionPlusActive else { return localization.string("status.motionPlusOff") }
    return localization.string(isGyroRestReady ? "status.gyroReady" : "status.gyroCalibrating")
  }
}

extension WiiRemoteStatus.ExtensionKind {
  /// The catalog key of the kind's display name.
  fileprivate var localizationKey: String {
    switch self {
    case .nunchuk: "term.wiiExtension.nunchuk"
    case .classicController: "term.wiiExtension.classicController"
    case .classicControllerPro: "term.wiiExtension.classicControllerPro"
    case .motionPlusInactive: "term.wiiExtension.motionPlusInactive"
    case .motionPlus: "term.wiiExtension.motionPlus"
    case .motionPlusNunchuk: "term.wiiExtension.motionPlusNunchuk"
    case .motionPlusClassic: "term.wiiExtension.motionPlusClassic"
    }
  }
}
