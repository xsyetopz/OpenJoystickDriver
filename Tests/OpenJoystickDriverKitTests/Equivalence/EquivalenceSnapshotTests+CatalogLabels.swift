import Foundation

@testable import OpenJoystickDriverKit

/// Stable snapshot labels for catalog enums. Each label is a string written here, so renaming a
/// Swift case, a family, or a protocol id changes only the switch below, not the
/// snapshot text of every record. A new case fails to compile until it gets a label.
extension EquivalenceSnapshotCatalogTests {
  static func label(_ id: PhysicalProtocolID) -> String {
    switch id {
    case .hidDescriptor: "hid-descriptor"
    case .hidReportLayout: "hid-report-layout"
    case .xboxXID: "xbox-xid"
    case .xboxXUSB: "xbox-xusb"
    case .xboxGIP: "xbox-gip"
    case .sonySixaxis: "sony-sixaxis"
    case .sonyDualShock4: "sony-dual-shock4"
    case .sonyDualSense: "sony-dual-sense"
    case .nintendoSwitch1: "nintendo-switch1"
    case .nintendoSwitch2: "nintendo-switch2"
    case .nintendoSwitchInputOnly: "nintendo-switch-input-only"
    case .valveSteamController: "valve-steam-controller"
    case .valveSteamTriton: "valve-steam-triton"
    case .valveSteamDeck: "valve-steam-deck"
    case .vendorFlydigi: "vendor-flydigi"
    case .vendorPS3ThirdParty: "vendor-ps3-third-party"
    case .vendorGameSir: "vendor-game-sir"
    case .vendorNVIDIAShield: "vendor-nvidia-shield"
    case .nintendoWii: "nintendo-wii"
    default: id.commandLineName
    }
  }

  static func label(_ variant: PhysicalProtocolVariantID?) -> String {
    switch variant {
    case nil: "-"
    case .usb?: "usb"
    case .bluetoothClassic?: "bluetooth-classic"
    case .bluetoothLE?: "bluetooth-le"
    case .gamepad?: "gamepad"
    case .wired?: "wired"
    case .receiver?: "receiver"
    case .dongle?: "dongle"
    case .enhancedHID?: "enhanced-hid"
    }
  }

  static func label(_ ownership: ControllerServer) -> String {
    switch ownership {
    case .system: "macos"
    case .ojd: "ojd"
    }
  }

  static func label(_ policy: GIPKeepAlivePolicy) -> String {
    switch policy {
    case .enabled: "enabled"
    case .disabled: "disabled"
    }
  }

  static func label(_ kind: PhysicalHIDReportKind) -> String {
    switch kind {
    case .input: "input"
    case .output: "output"
    case .feature: "feature"
    }
  }

  static func label(_ transport: PhysicalTransport?) -> String {
    switch transport {
    case nil: "all"
    case .usb?: "usb"
    case .bluetoothClassic?: "bluetooth-classic"
    case .bluetoothLE?: "bluetooth-le"
    case .proprietaryRadioReceiver?: "radio-receiver"
    }
  }

  static func label(_ key: ControllerTuning.Key) -> String {
    switch key {
    case .stickDeadzone: "stickDeadzone"
    case .inputLivenessTimeoutMs: "inputLivenessTimeoutMs"
    case .hidStartupRecoveryIntervalMs: "hidStartupRecoveryIntervalMs"
    case .hidStartupRecoveryRounds: "hidStartupRecoveryRounds"
    case .hidStartupIntervalMs: "hidStartupIntervalMs"
    case .minimumHIDOutputIntervalMs: "minimumHIDOutputIntervalMs"
    case .lizardResendTicks: "lizardResendTicks"
    case .usbCommandTimeoutMs: "usbCommandTimeoutMs"
    case .presenceResendReports: "presenceResendReports"
    case .adapterDisconnectDelayMs: "adapterDisconnectDelayMs"
    case .usbStartupIntervalMs: "usbStartupIntervalMs"
    case .usbStartupRetryDelayMs: "usbStartupRetryDelayMs"
    case .usbTransferTimeoutMs: "usbTransferTimeoutMs"
    case .frameQueueCapacity: "frameQueueCapacity"
    case .irWriteIntervalMs: "irWriteIntervalMs"
    case .speakerMaxSeconds: "speakerMaxSeconds"
    case .replyTimeoutMs: "replyTimeoutMs"
    }
  }

  static func label(_ motor: PhysicalRumbleMotor) -> String {
    switch motor {
    case .lowFrequency: "low-frequency"
    case .highFrequency: "high-frequency"
    case .leftTrigger: "left-trigger"
    case .rightTrigger: "right-trigger"
    case .leftHaptic: "left-haptic"
    case .rightHaptic: "right-haptic"
    }
  }

  static func label(_ feature: PhysicalLightingFeature) -> String {
    switch feature {
    case .playerIndicator: "player-indicator"
    case .programmableColor: "programmable-color"
    case .programmableBrightness: "programmable-brightness"
    }
  }

  static func label(_ trigger: PhysicalAdaptiveTrigger) -> String {
    switch trigger {
    case .left: "left"
    case .right: "right"
    }
  }

  /// Control ids are the persisted profile identifiers, so their raw values are the labels.
  static func labels(_ controls: Set<Control>) -> String {
    controls.map(\.rawValue).sorted().joined(separator: ",")
  }

  static func hex(_ bytes: [UInt8]) -> String {
    bytes.map { unsafe String(format: "%02X", $0) }.joined()
  }
}
