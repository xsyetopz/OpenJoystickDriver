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
  var scopeViolation: String? {
    if inputLayouts != nil, !recordSections.contains(.input) {
      return "an input layout applies only to a family that reads one"
    }
    if hidUsageMap != nil || !hidUsageShapes.isEmpty, !recordSections.contains(.hidUsageMap) {
      return "a HID usage map applies only to a family that reads one"
    }
    if rumbleTemplate != nil || !variantRumble.isEmpty, !recordSections.contains(.rumble) {
      return "rumble templates require a driver that encodes them"
    }
    if let violation = rumbleTargetViolation { return violation }
    if keepAlive != nil,
      ([rumbleTemplate].compactMap { $0 } + Array(variantRumble.values)).contains(where: {
        $0.resendIntervalMilliseconds != nil
      })
    {
      return RumbleOutputTemplate.resendWithFamilyKeepAliveProblem
    }
    if receiverPowerOff != nil, family != .xboxXUSB {
      return "receiverPowerOff applies only to XboxXUSB"
    }
    if !startupWrites.isEmpty, rawUSB == .always {
      return "HID startup writes apply only to HID controllers"
    }
    if sessionKeys != family.generalSessionFields {
      let read = family.generalSessionFields.map(\.rawValue).sorted()
      return read.isEmpty
        ? "\(family.rawValue) reads no session keys"
        : "\(family.rawValue) reads the session keys \(read.joined(separator: ", "))"
    }
    if let unlisted = presentGeneralSessionFields.subtracting(sessionKeys).map(\.rawValue).min() {
      return "defaults.session sets \(unlisted), which sessionKeys does not list"
    }
    if let violation = keepAliveViolation { return violation }
    if (activation + deactivation).contains(where: {
      $0.transport.map { !writeTransports.contains($0) } ?? false
    }) {
      return "activation and deactivation name only a transport writeTransports lists"
    }
    if presentSessionFields != family.sessionFields {
      let unread = presentSessionFields.subtracting(family.sessionFields).sorted()
      let missing = family.sessionFields.subtracting(presentSessionFields).sorted()
      return unread.isEmpty
        ? "\(family.rawValue) must set \(missing.joined(separator: ", "))"
        : "\(family.rawValue) does not read \(unread.joined(separator: ", "))"
    }
    if let namedPackets, !namedPackets.allIDs(startWith: "\(family.rawValue)/") {
      return "each named packet id starts with \(family.rawValue)/"
    }
    if rawUSB == .always, !tuningKeys.isEmpty {
      return "a family that is always raw USB reads its tuning through rawUSBTuningKeys"
    }
    if rawUSB == .never, !rawUSBTuningKeys.isEmpty {
      return "rawUSBTuningKeys apply only to a family with a raw-USB variant"
    }
    if let tuning {
      let scope = tuningKeys.union(rawUSBTuningKeys).union(ControllerTuning.Key.alwaysRead)
      for key in ControllerTuning.Key.allCases
      where tuning.setKeys.contains(key) && !scope.contains(key) {
        return "\(key) is not read by the \(family.rawValue) driver"
      }
    }
    for (variant, tuning) in variantTuning.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
      let scope = tuningScope(variant: variant)
      for key in ControllerTuning.Key.allCases
      where tuning.setKeys.contains(key) && !scope.contains(key) {
        return "\(key) is not read by the \(family.rawValue):\(variant.rawValue) driver"
      }
    }
    return nil
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
  var rumbleTargetViolation: String? {
    let mismatch =
      "a raw-USB variant's rumble template is a usb packet, and a HID variant's is a HID report"
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
  var keepAliveViolation: String? {
    guard let keepAlive else { return nil }
    let reads = tuningKeys.union(rawUSBTuningKeys)
    for write in keepAlive.writes {
      switch write.payload {
      case .hid where rawUSB == .always:
        return "a HID keep-alive write applies only to HID controllers"
      case .usb where rawUSB == .never:
        return "a raw-USB keep-alive write applies only to a family with a raw-USB variant"
      default: break
      }
      if let key = write.resendTuning, !reads.contains(key) || tuning?.text(of: key) == nil {
        return "resendTuning names \(key.rawValue), which the family must read and default"
      }
    }
    return nil
  }
}
