import Foundation

/// The typed, family-scoped values of a controller record's `protocol.parameters`.
///
/// Each field is declared by the protocol drivers named beside it; ``violation(family:variant:)``
/// rejects a field outside its driver. A parameter changes how the driver decodes or reaches a
/// variant; one that decodes a fixed extra button bit also declares that control. Capability
/// corrections are ``ControllerCapabilityDelta``. An absent field keeps the driver's default, so
/// a record never spells a default value.
public struct ProtocolParameters: Codable, Equatable, Sendable {
  /// Where a GIP packet carries the Share button, counted back from the packet's end (Linux
  /// xpad `MAP_SHARE_BUTTON` 18, `MAP_SHARE_OFFSET` 26); a pad without it has no Share. `XboxGIP`.
  public struct ShareButton: Codable, Equatable, Sendable {
    /// The offset of the Share button from the end of the packet, in bytes.
    public let fromEnd: Int

    /// Creates the parameter from a packet-end offset.
    public init(fromEnd: Int) { self.fromEnd = fromEnd }

    /// The packet-end offsets a record may name.
    static let fromEndRange = 1...255

    /// Decodes `fromEnd`, which must be in `fromEndRange`; any other key is rejected.
    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["fromEnd"])
      fromEnd = try container.decode(Int.self, for: "fromEnd")
      guard Self.fromEndRange.contains(fromEnd) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("fromEnd")],
            debugDescription: "fromEnd must be in \(Self.fromEndRange)"
          )
        )
      }
    }
  }

  /// The axis and button permutation of a Nintendo controller.
  ///
  /// `NintendoSwitch1` takes `Pro`, `JoyConLeft` and `JoyConRight`; `NintendoSwitch2` also takes
  /// `GameCube`, the NSO GameCube controller with analog triggers and flash trigger calibration. On
  /// `NintendoSwitch2` the Joy-Con values select the Joy-Con 2 layout.
  public enum Layout: String, Codable, CaseIterable, Sendable {
    /// The Switch Pro Controller layout.
    case pro = "Pro"
    /// The left Joy-Con layout.
    case joyConLeft = "JoyConLeft"
    /// The right Joy-Con layout.
    case joyConRight = "JoyConRight"
    /// The NSO GameCube controller layout.
    case gameCube = "GameCube"
  }

  /// What a Switch pad's USB link does. `ChargingOnly` is a pad that enumerates over USB for
  /// charging but speaks the protocol only over Bluetooth (SDL
  /// `HIDAPI_DriverSwitch_IsSupportedDevice`, Linux `hid-nintendo.c` device table).
  /// `NintendoSwitch1`.
  public enum USBProtocol: String, Codable, CaseIterable, Sendable {
    /// The pad enumerates over USB for charging only.
    case chargingOnly = "ChargingOnly"
  }

  /// How GameSir enhanced HID lighting memory is organized. `ProfileSlots`: the driver reads the
  /// active slot at startup, tracks it, and writes color and brightness into that slot.
  /// `VendorGameSir` enhanced HID.
  public enum LightingMemory: String, Codable, CaseIterable, Sendable {
    /// The driver reads the active lighting slot at startup and writes colour and brightness into
    /// it.
    case profileSlots = "ProfileSlots"
  }

  /// Where a third-party PS3 pad's hat comes from. `DpadPressure`: its hat bits are untrusted, so
  /// any nonzero D-pad pressure byte holds its direction (SDL `SDL_hidapi_ps3.c`, Saitek Cyborg
  /// V.3 Rumble Pad). `VendorPS3ThirdParty`.
  public enum HatSource: String, Codable, CaseIterable, Sendable {
    /// Any nonzero D-pad pressure byte holds its direction.
    case dpadPressure = "DpadPressure"
  }

  /// Which motion calibration report a DualShock 4 trusts.
  ///
  /// `Factory`: the report is trusted. SDL `SDL_hidapi_ps4.c` reads it only on Sony's own
  /// controllers; other pads keep the nominal scale. `SonyDualShock4`.
  public enum MotionCalibration: String, Codable, CaseIterable, Sendable {
    /// The factory calibration report is trusted.
    case factory = "Factory"
  }

  /// The part a Sony device plays. `WirelessAdapter` (`SonyDualShock4`) is Sony's DualShock 4
  /// wireless adapter (SDL `USB_PRODUCT_SONY_DS4_DONGLE`): output waits for a paired pad, and its
  /// calibration uses the Bluetooth gyro order. `Receiver` (`SonyDualSense`) is a third-party
  /// wireless receiver that keeps reporting with no controller paired.
  public enum Role: String, Codable, CaseIterable, Sendable {
    /// Sony's DualShock 4 wireless adapter.
    case wirelessAdapter = "WirelessAdapter"
    /// A third-party wireless receiver.
    case receiver = "Receiver"
  }

  /// The motion scale of a DualShock 4 model. `StrikePad` is the STRIKEPAD grip (SDL
  /// `USB_PRODUCT_SONY_DS4_STRIKEPAD`): doubled gyro scale and doubled, negated accelerometer
  /// scale. `SonyDualShock4`.
  public enum MotionScale: String, Codable, CaseIterable, Sendable {
    /// The STRIKEPAD grip.
    case strikePad = "StrikePad"
  }

  /// The input report revision of an NVIDIA SHIELD controller. `Shield2015` is the 2015
  /// controller (SDL `SDL_hidapi_shield.c` V103): plain rumble output report and a touchpad
  /// click; without it the driver runs the input-only 2017 controller. `VendorNVIDIAShield`.
  public enum ReportRevision: String, Codable, CaseIterable, Sendable {
    /// The 2015 SHIELD controller.
    case shield2015 = "Shield2015"
  }

  /// Who made a DualSense-protocol controller.
  ///
  /// `ThirdParty` is one that Sony did not make: the driver follows SDL's non-Sony path, probing
  /// for features. The other `SonyDualSense` fields describe a third-party DualSense and need this
  /// one.
  public enum Maker: String, Codable, CaseIterable, Sendable {
    /// A DualSense-protocol controller that Sony did not make.
    case thirdParty = "ThirdParty"
  }

  /// Where a GIP packet carries the Share button; nil for a pad without one.
  public var shareButton: ShareButton?
  /// The axis and button permutation of a Nintendo controller.
  public var layout: Layout?
  /// What a Switch pad's USB link does.
  public var usbProtocol: USBProtocol?
  /// GameSir enhanced HID reports the inner grips in extras-byte bits 0x40 and 0x80.
  public var innerGrips: Bool?
  /// How GameSir enhanced HID lighting memory is organized.
  public var lightingMemory: LightingMemory?
  /// Where a third-party PS3 pad's hat comes from.
  public var hatSource: HatSource?
  /// Which motion calibration report a DualShock 4 trusts.
  public var motionCalibration: MotionCalibration?
  /// The part a Sony device plays.
  public var role: Role?
  /// The motion scale of a DualShock 4 model.
  public var motionScale: MotionScale?
  /// The input report revision of an NVIDIA SHIELD controller.
  public var reportRevision: ReportRevision?
  /// Who made a DualSense-protocol controller.
  public var maker: Maker?
  /// Third-party DualSense with sensors though it does not answer the probe (SDL's Razer list).
  public var unprobedSensors: Bool?
  /// Third-party DualSense with a touchpad though it does not answer the probe (SDL's Razer list).
  ///
  /// Either unprobed field also selects the alternate report without a probe reply.
  public var unprobedTouchpad: Bool?
  /// Third-party DualSense whose probe reply omits the vibration it has (SDL's NACON entry).
  public var forcedVibration: Bool?

  /// A record that names no parameter.
  public static let none = Self()

  /// Creates parameters; every field not given keeps the driver's default.
  public init(
    shareButton: ShareButton? = nil,
    layout: Layout? = nil,
    usbProtocol: USBProtocol? = nil,
    innerGrips: Bool? = nil,
    lightingMemory: LightingMemory? = nil,
    hatSource: HatSource? = nil,
    motionCalibration: MotionCalibration? = nil,
    role: Role? = nil,
    motionScale: MotionScale? = nil,
    reportRevision: ReportRevision? = nil,
    maker: Maker? = nil,
    unprobedSensors: Bool? = nil,
    unprobedTouchpad: Bool? = nil,
    forcedVibration: Bool? = nil
  ) {
    self.shareButton = shareButton
    self.layout = layout
    self.usbProtocol = usbProtocol
    self.innerGrips = innerGrips
    self.lightingMemory = lightingMemory
    self.hatSource = hatSource
    self.motionCalibration = motionCalibration
    self.role = role
    self.motionScale = motionScale
    self.reportRevision = reportRevision
    self.maker = maker
    self.unprobedSensors = unprobedSensors
    self.unprobedTouchpad = unprobedTouchpad
    self.forcedVibration = forcedVibration
  }

  /// Every parameter name a record may write.
  static let names: Set<String> = [
    "shareButton", "layout", "usbProtocol", "innerGrips", "lightingMemory", "hatSource",
    "motionCalibration", "role", "motionScale", "reportRevision", "maker",
    "unprobedSensors", "unprobedTouchpad", "forcedVibration",
  ]

  /// Strictly decodes the object: an unknown name or a value of the wrong type fails, and a
  /// flag is `true` or absent.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    try container.rejectUnknown(allowed: Self.names)
    guard !container.allKeys.isEmpty else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "parameters must not be empty")
      )
    }
    func flag(_ name: String) throws -> Bool? {
      guard let value = try container.decodeOptional(Bool.self, for: name) else { return nil }
      guard value else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey(name)],
            debugDescription: "\(name) is true or omitted"
          )
        )
      }
      return true
    }
    shareButton = try container.decodeOptional(ShareButton.self, for: "shareButton")
    layout = try container.decodeOptional(Layout.self, for: "layout")
    usbProtocol = try container.decodeOptional(USBProtocol.self, for: "usbProtocol")
    innerGrips = try flag("innerGrips")
    lightingMemory = try container.decodeOptional(LightingMemory.self, for: "lightingMemory")
    hatSource = try container.decodeOptional(HatSource.self, for: "hatSource")
    motionCalibration = try container.decodeOptional(
      MotionCalibration.self,
      for: "motionCalibration"
    )
    role = try container.decodeOptional(Role.self, for: "role")
    motionScale = try container.decodeOptional(MotionScale.self, for: "motionScale")
    reportRevision = try container.decodeOptional(ReportRevision.self, for: "reportRevision")
    maker = try container.decodeOptional(Maker.self, for: "maker")
    unprobedSensors = try flag("unprobedSensors")
    unprobedTouchpad = try flag("unprobedTouchpad")
    forcedVibration = try flag("forcedVibration")
  }

  /// The set parameters as sorted `name=value` entries; empty when the record names none.
  public var entries: [String] {
    var result: [String] = []
    if let shareButton { result.append("shareButton.fromEnd=\(shareButton.fromEnd)") }
    if let layout { result.append("layout=\(layout.rawValue)") }
    if let usbProtocol { result.append("usbProtocol=\(usbProtocol.rawValue)") }
    if innerGrips != nil { result.append("innerGrips=true") }
    if let lightingMemory { result.append("lightingMemory=\(lightingMemory.rawValue)") }
    if let hatSource { result.append("hatSource=\(hatSource.rawValue)") }
    if let motionCalibration { result.append("motionCalibration=\(motionCalibration.rawValue)") }
    if let role { result.append("role=\(role.rawValue)") }
    if let motionScale { result.append("motionScale=\(motionScale.rawValue)") }
    if let reportRevision { result.append("reportRevision=\(reportRevision.rawValue)") }
    if let maker { result.append("maker=\(maker.rawValue)") }
    if unprobedSensors != nil { result.append("unprobedSensors=true") }
    if unprobedTouchpad != nil { result.append("unprobedTouchpad=true") }
    if forcedVibration != nil { result.append("forcedVibration=true") }
    return result.sorted()
  }

  /// One line for CLI and log output: the entries joined by commas, or `none`.
  public var summary: String { entries.isEmpty ? "none" : entries.joined(separator: ",") }

  /// Whether the record names no parameter.
  public var isEmpty: Bool { entries.isEmpty }

  /// The names of the set parameters.
  private var setNames: Set<String> {
    var result: Set<String> = []
    if shareButton != nil { result.insert("shareButton") }
    if layout != nil { result.insert("layout") }
    if usbProtocol != nil { result.insert("usbProtocol") }
    if innerGrips != nil { result.insert("innerGrips") }
    if lightingMemory != nil { result.insert("lightingMemory") }
    if hatSource != nil { result.insert("hatSource") }
    if motionCalibration != nil { result.insert("motionCalibration") }
    if role != nil { result.insert("role") }
    if motionScale != nil { result.insert("motionScale") }
    if reportRevision != nil { result.insert("reportRevision") }
    if maker != nil { result.insert("maker") }
    if unprobedSensors != nil { result.insert("unprobedSensors") }
    if unprobedTouchpad != nil { result.insert("unprobedTouchpad") }
    if forcedVibration != nil { result.insert("forcedVibration") }
    return result
  }

  /// The parameter names the family's protocol description declares.
  static func declared(by family: PhysicalProtocolID) -> Set<String> {
    ProtocolDescription.bundled[family].map { Set($0.parameters.keys) } ?? []
  }

  /// Why the parameters cannot belong to `family`, or nil when its driver declares them all and
  /// they agree with one another.
  func violation(
    family: PhysicalProtocolID,
    variant: PhysicalProtocolVariantID?
  ) -> String? {
    guard setNames.isSubset(of: Self.declared(by: family)) else {
      return "parameters must be declared by the selected driver"
    }
    if let description = ProtocolDescription.bundled[family] {
      for rule in description.parameterRules where rule.applies(to: variant) {
        if let problem = rule.violation(setting: setNames) { return problem }
      }
    }
    return valueViolation(family: family)
  }

  /// The parameters that take one of a fixed set of names.
  static let enumerationNames: Set<String> = [
    "layout", "usbProtocol", "lightingMemory", "hatSource", "motionCalibration", "role",
    "motionScale", "reportRevision", "maker",
  ]

  /// The name an enumeration parameter is set to; nil when it is unset or not an enumeration.
  func enumerationValue(_ name: String) -> String? {
    switch name {
    case "layout": layout?.rawValue
    case "usbProtocol": usbProtocol?.rawValue
    case "lightingMemory": lightingMemory?.rawValue
    case "hatSource": hatSource?.rawValue
    case "motionCalibration": motionCalibration?.rawValue
    case "role": role?.rawValue
    case "motionScale": motionScale?.rawValue
    case "reportRevision": reportRevision?.rawValue
    case "maker": maker?.rawValue
    default: nil
    }
  }

  /// Why a set parameter holds a value its family's description does not declare, or nil.
  ///
  /// The enum values and integer ranges come from the description, not from this type.
  private func valueViolation(family: PhysicalProtocolID) -> String? {
    guard let declared = ProtocolDescription.bundled[family]?.parameters else { return nil }
    for name in Self.enumerationNames.sorted() {
      guard let value = enumerationValue(name), case .enumeration(let values)? = declared[name]
      else { continue }
      if !values.contains(value) { return "\(name) \(value) is not one of \(values)" }
    }
    if let shareButton, case .object(let fields)? = declared["shareButton"],
      let range = fields["fromEnd"], !range.contains(shareButton.fromEnd)
    {
      return "shareButton.fromEnd must be in \(range)"
    }
    return nil
  }
}
