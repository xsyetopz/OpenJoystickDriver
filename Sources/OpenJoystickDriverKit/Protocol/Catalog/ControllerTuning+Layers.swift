import Foundation

extension ControllerTuning {
  /// One tuning value, named as in the `tuning` section of a record and of `all.patch.plist`.
  ///
  /// The cases are in the order `validateTuning` reports a family-scope violation.
  public enum Key: String, CaseIterable, Codable, Sendable {
    /// The stick deadzone.
    case stickDeadzone
    /// The input liveness timeout.
    case inputLivenessTimeoutMs
    /// The interval of the HID startup recovery.
    case hidStartupRecoveryIntervalMs
    /// The number of HID startup recovery rounds.
    case hidStartupRecoveryRounds
    /// The interval between HID startup writes.
    case hidStartupIntervalMs
    /// The minimum interval between HID output reports.
    case minimumHIDOutputIntervalMs
    /// The number of keep-alive ticks between resends of lizard mode off.
    case lizardResendTicks
    /// The timeout of a USB command.
    case usbCommandTimeoutMs
    /// The number of reports between presence inquiry resends.
    case presenceResendReports
    /// The delay after which a silent adapter counts as disconnected.
    case adapterDisconnectDelayMs
    /// The interval between USB startup writes.
    case usbStartupIntervalMs
    /// The delay before a USB startup retry.
    case usbStartupRetryDelayMs
    /// The timeout of a USB transfer.
    case usbTransferTimeoutMs
    /// The wait after each Wii Remote IR register write.
    case irWriteIntervalMs
    /// The longest clip the Wii Remote speaker plays.
    case speakerMaxSeconds
    /// The wait for the reply to a Wii Remote read or write.
    case replyTimeoutMs
    /// The capacity of the frame queue.
    case frameQueueCapacity
    /// The stored centre of the left stick X axis.
    case leftStickCenterX
    /// The stored centre of the left stick Y axis.
    case leftStickCenterY
    /// The stored centre of the right stick X axis.
    case rightStickCenterX
    /// The stored centre of the right stick Y axis.
    case rightStickCenterY
    /// The stored left stick deflection that reads as full.
    case leftStickRange
    /// The stored right stick deflection that reads as full.
    case rightStickRange
    /// The stored rest value of the left trigger.
    case leftTriggerRest
    /// The stored fully pressed value of the left trigger.
    case leftTriggerFull
    /// The stored rest value of the right trigger.
    case rightTriggerRest
    /// The stored fully pressed value of the right trigger.
    case rightTriggerFull

    /// Whether the driver picks a value while no layer sets the key.
    ///
    /// No driver picks a stick deadzone or a calibration value, so none applies until a layer
    /// sets one.
    public var hasDriverValue: Bool {
      self != .stickDeadzone && !ControllerCalibration.keys.contains(self)
    }

    /// The keys every driver reads, whatever its family.
    static let alwaysRead: Set<Key> = ControllerCalibration.keys.union([
      .stickDeadzone, .frameQueueCapacity,
    ])
  }

  /// The keys this tuning sets.
  public var setKeys: Set<Key> { Set(Key.allCases.filter { text(of: $0) != nil }) }

  /// The value of `key` as the JSON number it is written as; nil when unset.
  public func text(of key: Key) -> String? {
    switch key {
    case .stickDeadzone: stickDeadzone.map { "\($0)" }
    case .inputLivenessTimeoutMs: inputLivenessTimeoutMilliseconds.map(String.init)
    case .hidStartupRecoveryIntervalMs: hidStartupRecoveryIntervalMilliseconds.map(String.init)
    case .hidStartupRecoveryRounds: hidStartupRecoveryRounds.map(String.init)
    case .hidStartupIntervalMs: hidStartupIntervalMilliseconds.map(String.init)
    case .minimumHIDOutputIntervalMs: minimumHIDOutputIntervalMilliseconds.map(String.init)
    case .lizardResendTicks: lizardResendTicks.map(String.init)
    case .usbCommandTimeoutMs: usbCommandTimeoutMilliseconds.map(String.init)
    case .presenceResendReports: presenceResendReports.map(String.init)
    case .adapterDisconnectDelayMs: adapterDisconnectDelayMilliseconds.map(String.init)
    case .usbStartupIntervalMs: usbStartupIntervalMilliseconds.map(String.init)
    case .usbStartupRetryDelayMs: usbStartupRetryDelayMilliseconds.map(String.init)
    case .usbTransferTimeoutMs: usbTransferTimeoutMilliseconds.map(String.init)
    case .irWriteIntervalMs: irWriteIntervalMilliseconds.map(String.init)
    case .speakerMaxSeconds: speakerMaxSeconds.map(String.init)
    case .replyTimeoutMs: replyTimeoutMilliseconds.map(String.init)
    case .frameQueueCapacity: frameQueueCapacity.map(String.init)
    case .leftStickCenterX, .leftStickCenterY, .rightStickCenterX, .rightStickCenterY,
      .leftStickRange, .rightStickRange, .leftTriggerRest, .leftTriggerFull, .rightTriggerRest,
      .rightTriggerFull:
      calibration.values[key].map { "\($0)" }
    }
  }

  /// This tuning with every key that `higher` sets replaced by the value of `higher`.
  public func overlaid(by higher: Self) -> Self {
    Self(
      stickDeadzone: higher.stickDeadzone ?? stickDeadzone,
      inputLivenessTimeoutMilliseconds: higher.inputLivenessTimeoutMilliseconds
        ?? inputLivenessTimeoutMilliseconds,
      hidStartupIntervalMilliseconds: higher.hidStartupIntervalMilliseconds
        ?? hidStartupIntervalMilliseconds,
      minimumHIDOutputIntervalMilliseconds: higher.minimumHIDOutputIntervalMilliseconds
        ?? minimumHIDOutputIntervalMilliseconds,
      hidStartupRecoveryIntervalMilliseconds: higher.hidStartupRecoveryIntervalMilliseconds
        ?? hidStartupRecoveryIntervalMilliseconds,
      hidStartupRecoveryRounds: higher.hidStartupRecoveryRounds ?? hidStartupRecoveryRounds,
      lizardResendTicks: higher.lizardResendTicks ?? lizardResendTicks,
      usbCommandTimeoutMilliseconds: higher.usbCommandTimeoutMilliseconds
        ?? usbCommandTimeoutMilliseconds,
      presenceResendReports: higher.presenceResendReports ?? presenceResendReports,
      adapterDisconnectDelayMilliseconds: higher.adapterDisconnectDelayMilliseconds
        ?? adapterDisconnectDelayMilliseconds,
      usbStartupIntervalMilliseconds: higher.usbStartupIntervalMilliseconds
        ?? usbStartupIntervalMilliseconds,
      usbStartupRetryDelayMilliseconds: higher.usbStartupRetryDelayMilliseconds
        ?? usbStartupRetryDelayMilliseconds,
      usbTransferTimeoutMilliseconds: higher.usbTransferTimeoutMilliseconds
        ?? usbTransferTimeoutMilliseconds,
      irWriteIntervalMilliseconds: higher.irWriteIntervalMilliseconds
        ?? irWriteIntervalMilliseconds,
      speakerMaxSeconds: higher.speakerMaxSeconds ?? speakerMaxSeconds,
      replyTimeoutMilliseconds: higher.replyTimeoutMilliseconds ?? replyTimeoutMilliseconds,
      frameQueueCapacity: higher.frameQueueCapacity ?? frameQueueCapacity,
      calibration: ControllerCalibration(
        values: calibration.values.merging(higher.calibration.values) { $1 }
      )
    )
  }

  /// This tuning without the keys outside `keys`.
  func keeping(_ keys: Set<Key>) -> Self {
    Self(
      stickDeadzone: keys.contains(.stickDeadzone) ? stickDeadzone : nil,
      inputLivenessTimeoutMilliseconds: keys.contains(.inputLivenessTimeoutMs)
        ? inputLivenessTimeoutMilliseconds : nil,
      hidStartupIntervalMilliseconds: keys.contains(.hidStartupIntervalMs)
        ? hidStartupIntervalMilliseconds : nil,
      minimumHIDOutputIntervalMilliseconds: keys.contains(.minimumHIDOutputIntervalMs)
        ? minimumHIDOutputIntervalMilliseconds : nil,
      hidStartupRecoveryIntervalMilliseconds: keys.contains(.hidStartupRecoveryIntervalMs)
        ? hidStartupRecoveryIntervalMilliseconds : nil,
      hidStartupRecoveryRounds: keys.contains(.hidStartupRecoveryRounds)
        ? hidStartupRecoveryRounds : nil,
      lizardResendTicks: keys.contains(.lizardResendTicks) ? lizardResendTicks : nil,
      usbCommandTimeoutMilliseconds: keys.contains(.usbCommandTimeoutMs)
        ? usbCommandTimeoutMilliseconds : nil,
      presenceResendReports: keys.contains(.presenceResendReports) ? presenceResendReports : nil,
      adapterDisconnectDelayMilliseconds: keys.contains(.adapterDisconnectDelayMs)
        ? adapterDisconnectDelayMilliseconds : nil,
      usbStartupIntervalMilliseconds: keys.contains(.usbStartupIntervalMs)
        ? usbStartupIntervalMilliseconds : nil,
      usbStartupRetryDelayMilliseconds: keys.contains(.usbStartupRetryDelayMs)
        ? usbStartupRetryDelayMilliseconds : nil,
      usbTransferTimeoutMilliseconds: keys.contains(.usbTransferTimeoutMs)
        ? usbTransferTimeoutMilliseconds : nil,
      irWriteIntervalMilliseconds: keys.contains(.irWriteIntervalMs)
        ? irWriteIntervalMilliseconds : nil,
      speakerMaxSeconds: keys.contains(.speakerMaxSeconds) ? speakerMaxSeconds : nil,
      replyTimeoutMilliseconds: keys.contains(.replyTimeoutMs) ? replyTimeoutMilliseconds : nil,
      frameQueueCapacity: keys.contains(.frameQueueCapacity) ? frameQueueCapacity : nil,
      calibration: ControllerCalibration(
        values: calibration.values.filter { keys.contains($0.key) }
      )
    )
  }
}

extension ControllerRecord {
  /// Whether this controller's driver reads `key`; `all.patch.plist` sets it only where this holds.
  public func reads(_ key: ControllerTuning.Key) -> Bool { tuningScope.contains(key) }
}

extension ControllerTuning {
  /// Why `key` does not apply to a controller of this family and stored variant, or nil when a
  /// driver reads it.
  ///
  /// A nil `protocolID` is a record with no known family: it reads only `stickDeadzone` and
  /// `frameQueueCapacity`. The family's description holds the keys.
  static func scopeViolation(
    _ key: Key,
    protocolID: PhysicalProtocolID?,
    variant: PhysicalProtocolVariantID?
  ) -> ControllerRecordProblem? {
    guard !scope(protocolID: protocolID, variant: variant).contains(key) else { return nil }
    let driver = protocolID?.rawValue ?? "unknown"
    return .rule(
      "error.E5007.tuning.keyNotRead",
      [key.rawValue, driver],
      "\(key.rawValue) is not read by the \(driver) driver"
    )
  }

  /// The keys that a controller of this family and stored variant reads.
  static func scope(
    protocolID: PhysicalProtocolID?,
    variant: PhysicalProtocolVariantID?
  ) -> Set<Key> {
    guard let description = protocolID?.protocolDescription else { return Key.alwaysRead }
    return description.tuningScope(variant: variant)
  }

  /// The keys that a controller of the record `document` reads: those every mode's family and
  /// variant reads.
  static func scope(ofDocument document: OrderedJSON) -> Set<Key> {
    var modes: [OrderedJSON] = []
    if case .array(let items)? = document["modes"], items.allSatisfy({ $0.members != nil }) {
      modes = items
    }
    let scopes = modes.map { mode -> Set<Key> in
      let info = mode["protocol"]
      let protocolID = info?["family"]?.string.flatMap(PhysicalProtocolID.init(rawValue:))
      let variant = info?["variant"]?.string.flatMap(PhysicalProtocolVariantID.init(rawValue:))
      return scope(protocolID: protocolID, variant: variant)
    }
    return scopes.dropFirst().reduce(scopes.first ?? Key.alwaysRead) { $0.intersection($1) }
  }
}

extension ControllerRecordDocument {
  /// Why `key` does not apply to a mode of this record, or nil when the driver of every mode
  /// reads it.
  func tuningScopeViolation(_ key: ControllerTuning.Key) -> ControllerRecordProblem? {
    modes.lazy.compactMap { mode in
      ControllerTuning.scopeViolation(
        key,
        protocolID: mode.protocolInfo.protocolID,
        variant: mode.protocolInfo.protocolVariant
      )
    }.first
  }
}
