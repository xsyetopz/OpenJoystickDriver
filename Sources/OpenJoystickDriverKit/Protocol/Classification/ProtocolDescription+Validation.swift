import Foundation

extension ProtocolDescription {
  /// Why a startup write's condition names a variant the family lacks (E5004) or a parameter or
  /// value the description does not declare (E5002), or nil.
  func conditionProblem(
    _ condition: StartupWriteCondition,
    fileName: String
  ) -> ProtocolDescriptionProblem? {
    for variant in condition.variants ?? [] where !variants.contains(variant) {
      return ProtocolDescriptionProblem(
        .unknownProtocolVariant,
        "\(fileName): \(family.rawValue) has no variant \(variant.rawValue)"
      )
    }
    guard let rule = condition.rule else { return nil }
    guard case .enumeration(let declared)? = parameters[rule.parameter] else {
      return ProtocolDescriptionProblem(
        .invalidProtocolDescription,
        "\(fileName): when names \(rule.parameter), which is not an enumeration parameter of "
          + family.rawValue
      )
    }
    for value in rule.values where !declared.contains(value) {
      return ProtocolDescriptionProblem(
        .invalidProtocolDescription,
        "\(fileName): when names \(value), which \(rule.parameter) does not declare"
      )
    }
    return nil
  }

  /// Why a parameter rule names a variant the family lacks (E5004) or a parameter the description
  /// does not declare (E5002), or nil.
  func ruleProblem(fileName: String) -> ProtocolDescriptionProblem? {
    for rule in parameterRules {
      for variant in rule.variants where !variants.contains(variant) {
        return ProtocolDescriptionProblem(
          .unknownProtocolVariant,
          "\(fileName): \(family.rawValue) has no variant \(variant.rawValue)"
        )
      }
      for name in rule.parameters.sorted() where parameters[name] == nil {
        return ProtocolDescriptionProblem(
          .invalidProtocolDescription,
          "\(fileName): parameterRules names \(name), which the description does not declare"
        )
      }
    }
    return nil
  }

  /// Why the defaults name something the family's driver does not read, or nil.
  ///
  /// The rule reads only this description, so it holds while the bundle is still loading.
  var scopeViolation: ControllerRecordProblem? {
    sectionScopeViolation ?? rumbleScopeViolation ?? sessionKeyScopeViolation
      ?? sessionFieldScopeViolation ?? tuningScopeViolation
  }

  /// Why the input layout, the HID usage map, or the receiver power-off applies to a family that
  /// does not read it, or nil.
  private var sectionScopeViolation: ControllerRecordProblem? {
    if inputLayouts != nil, !recordSections.contains(.input) {
      return .rule(
        "error.E5007.protocolDescription.inputLayout",
        "an input layout applies only to a family that reads one"
      )
    }
    if hidUsageMap != nil || !hidUsageShapes.isEmpty, !recordSections.contains(.hidUsageMap) {
      return .rule(
        "error.E5007.protocolDescription.usageMap",
        "a HID usage map applies only to a family that reads one"
      )
    }
    return nil
  }

  /// Why the rumble template applies to a family that does not read it, or targets the wrong
  /// packet kind, or resends beside a family keep-alive, or nil.
  private var rumbleScopeViolation: ControllerRecordProblem? {
    if rumbleTemplate != nil || !variantRumble.isEmpty, !recordSections.contains(.rumble) {
      return RumbleOutputTemplate.driverProblem
    }
    if let violation = rumbleTargetViolation { return violation }
    if keepAlive != nil,
      ([rumbleTemplate].compactMap { $0 } + Array(variantRumble.values)).contains(where: {
        $0.resendIntervalMilliseconds != nil
      })
    {
      return RumbleOutputTemplate.resendWithFamilyKeepAliveProblem
    }
    return nil
  }

  /// Why the receiver power-off, the HID startup, or the listed session keys do not suit the
  /// family, or nil.
  private var sessionKeyScopeViolation: ControllerRecordProblem? {
    if receiverPowerOff != nil, family != .xboxXUSB {
      return .rule(
        "error.E5007.protocolDescription.receiverPowerOff",
        "receiverPowerOff applies only to XboxXUSB"
      )
    }
    if !startupWrites.isEmpty, rawUSB == .always {
      return .rule(
        "error.E5007.session.hidStartup",
        "HID startup writes apply only to HID controllers"
      )
    }
    if sessionKeys != family.generalSessionFields {
      let read = family.generalSessionFields.map(\.rawValue).sorted()
      return read.isEmpty
        ? .rule(
          "error.E5007.protocolDescription.sessionKeysNone",
          [family.rawValue],
          "\(family.rawValue) reads no session keys"
        )
        : .rule(
          "error.E5007.protocolDescription.sessionKeysRead",
          [family.rawValue, read.joined(separator: ", ")],
          "\(family.rawValue) reads the session keys \(read.joined(separator: ", "))"
        )
    }
    if let unlisted = presentGeneralSessionFields.subtracting(sessionKeys).map(\.rawValue).min() {
      return .rule(
        "error.E5007.protocolDescription.sessionKeyUnlisted",
        [unlisted],
        "defaults.session sets \(unlisted), which sessionKeys does not list"
      )
    }
    return nil
  }

  /// Why the keep-alive, the activation transports, the session fields, or the named packets do
  /// not suit the family, or nil.
  private var sessionFieldScopeViolation: ControllerRecordProblem? {
    if let violation = keepAliveViolation { return violation }
    if (activation + deactivation).contains(where: {
      $0.transport.map { !writeTransports.contains($0) } ?? false
    }) {
      return .rule(
        "error.E5007.protocolDescription.activationTransport",
        "activation and deactivation name only a transport writeTransports lists"
      )
    }
    if presentSessionFields != family.sessionFields {
      let unread = presentSessionFields.subtracting(family.sessionFields).sorted()
      let missing = family.sessionFields.subtracting(presentSessionFields).sorted()
      return unread.isEmpty
        ? .rule(
          "error.E5007.protocolDescription.sessionMissing",
          [family.rawValue, missing.joined(separator: ", ")],
          "\(family.rawValue) must set \(missing.joined(separator: ", "))"
        )
        : .rule(
          "error.E5007.protocolDescription.sessionUnread",
          [family.rawValue, unread.joined(separator: ", ")],
          "\(family.rawValue) does not read \(unread.joined(separator: ", "))"
        )
    }
    if let namedPackets, !namedPackets.allIDs(startWith: "\(family.rawValue)/") {
      return .rule(
        "error.E5007.protocolDescription.namedPacketPrefix",
        [family.rawValue],
        "each named packet id starts with \(family.rawValue)/"
      )
    }
    return nil
  }

  /// Why the tuning keys or the tuning defaults do not suit the family's driver, or nil.
  private var tuningScopeViolation: ControllerRecordProblem? {
    if rawUSB == .always, !tuningKeys.isEmpty {
      return .rule(
        "error.E5007.protocolDescription.tuningRawUSB",
        "a family that is always raw USB reads its tuning through rawUSBTuningKeys"
      )
    }
    if rawUSB == .never, !rawUSBTuningKeys.isEmpty {
      return .rule(
        "error.E5007.protocolDescription.rawUSBTuningKeys",
        "rawUSBTuningKeys apply only to a family with a raw-USB variant"
      )
    }
    if let tuning,
      let key = Self.firstUnreadKey(
        of: tuning,
        scope: tuningKeys.union(rawUSBTuningKeys).union(ControllerTuning.Key.alwaysRead)
      )
    {
      return .rule(
        "error.E5007.tuning.keyNotRead",
        [key.rawValue, family.rawValue],
        "\(key) is not read by the \(family.rawValue) driver"
      )
    }
    for (variant, tuning) in variantTuning.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
      guard let key = Self.firstUnreadKey(of: tuning, scope: tuningScope(variant: variant)) else {
        continue
      }
      return .rule(
        "error.E5007.tuning.keyNotRead",
        [key.rawValue, "\(family.rawValue):\(variant.rawValue)"],
        "\(key) is not read by the \(family.rawValue):\(variant.rawValue) driver"
      )
    }
    return nil
  }

  /// The first key that `tuning` sets and `scope` lacks, or nil.
  private static func firstUnreadKey(
    of tuning: ControllerTuning,
    scope: Set<ControllerTuning.Key>
  ) -> ControllerTuning.Key? {
    ControllerTuning.Key.allCases.first { tuning.setKeys.contains($0) && !scope.contains($0) }
  }

  /// The general `defaults.session` keys the description sets, rumble aside.
  var presentGeneralSessionFields: Set<SessionKey> {
    var keys: Set<SessionKey> = []
    if !startupWrites.isEmpty || !usbStartupWrites.isEmpty { keys.insert(.startup) }
    if keepAlive != nil { keys.insert(.keepAlive) }
    return keys
  }

  /// Why a rumble template targets a packet kind that its variants do not use, or nil: a raw-USB
  /// variant's template is a usb packet and a HID variant's is a HID report.
  ///
  /// The flat template is checked against each variant of the family that has no template of its
  /// own; a family with no variants has the one unnamed variant.
  var rumbleTargetViolation: ControllerRecordProblem? {
    let mismatch = ControllerRecordProblem.rule(
      "error.E5007.rumble.templateKind",
      "a raw-USB variant's rumble template is a usb packet, and a HID variant's is a HID report"
    )
    if let rumbleTemplate {
      let flatVariants: [PhysicalProtocolVariantID?] =
        variants.isEmpty ? [nil] : variants.map(Optional.some)
      for variant in flatVariants where variant.map({ variantRumble[$0] == nil }) ?? true {
        if (rumbleTemplate.report == nil) != rawUSB.applies(to: variant) { return mismatch }
      }
    }
    for (variant, template) in variantRumble.sorted(by: { $0.key.rawValue < $1.key.rawValue })
    where (template.report == nil) != rawUSB.applies(to: variant) {
      return mismatch
    }
    return nil
  }

  /// Why the keep-alive names something the family's driver does not read, or nil.
  var keepAliveViolation: ControllerRecordProblem? {
    guard let keepAlive else { return nil }
    let reads = tuningKeys.union(rawUSBTuningKeys)
    for write in keepAlive.writes {
      switch write.payload {
      case .hid where rawUSB == .always:
        return .rule(
          "error.E5007.protocolDescription.keepAliveHID",
          "a HID keep-alive write applies only to HID controllers"
        )
      case .usb where rawUSB == .never:
        return .rule(
          "error.E5007.protocolDescription.keepAliveUSB",
          "a raw-USB keep-alive write applies only to a family with a raw-USB variant"
        )
      default: break
      }
      if let key = write.resendTuning, !reads.contains(key) || tuning?.text(of: key) == nil {
        return .rule(
          "error.E5007.protocolDescription.keepAliveResendTuning",
          [key.rawValue],
          "resendTuning names \(key.rawValue), which the family must read and default"
        )
      }
    }
    return nil
  }
}
