extension ControllerRecordDocument.ModeDocument {
  /// Why this mode's session cannot run on its own protocol, or nil.
  ///
  /// HID startup writes go to HID modes, raw-USB startup packets go to raw-USB families that read
  /// them and name no initialization list, a keep-alive extends a raw-USB family whose description
  /// declares none, settle, shutdown and control transfers belong to raw-USB modes, and only a
  /// driver that encodes a rumble template for the mode's variant and parameters may name one, a
  /// usb packet in a raw-USB mode and a HID report in a HID mode, and a template's resend interval
  /// needs neither a session keep-alive nor a family whose description declares one. Only a HID
  /// mode of a family whose driver encodes a player-indicator template may name one.
  func sessionViolation() -> ControllerRecordProblem? {
    let info = protocolInfo
    let rawUSB = info.protocolID.usesRawUSB(storedVariant: info.protocolVariant)
    return transportViolation(info, rawUSB: rawUSB) ?? usbStartupViolation(info)
      ?? rumbleViolation(info, rawUSB: rawUSB) ?? playerIndicatorViolation(info, rawUSB: rawUSB)
  }

  /// A session step that belongs to the other transport: HID startup writes or a repeated
  /// keep-alive on a raw-USB mode, and a raw-USB-only step on a HID mode.
  private func transportViolation(
    _ info: ControllerRecordDocument.ProtocolInfo,
    rawUSB: Bool
  ) -> ControllerRecordProblem? {
    if rawUSB {
      if !session.startupWrites.isEmpty {
        return .rule(
          "error.E5007.session.hidStartup",
          "HID startup writes apply only to HID controllers, so not to a raw-USB mode"
        )
      }
      if session.keepAlive != nil, ProtocolDescription.bundled[info.protocolID]?.keepAlive != nil {
        return .rule(
          "error.E5007.session.keepAliveFamily",
          [info.protocolID.rawValue],
          "a session keepAlive needs a raw-USB family whose description declares none"
        )
      }
      return nil
    }
    let named: [(String, Bool)] = [
      ("keepAlive", session.keepAlive != nil),
      ("keepAlive", session.keepAlive != nil),
      ("settleMilliseconds", session.settleMilliseconds != nil),
      ("shutdown", !session.shutdownWrites.isEmpty),
      ("control", !session.controlTransfers.isEmpty),
    ]
    guard let (key, _) = named.first(where: \.1) else { return nil }
    return .rule(
      "error.E5007.session.rawUSBOnly",
      [key],
      "session \(key) applies only to raw-USB modes"
    )
  }

  /// Raw-USB startup writes on a family that does not read them or that has an initialization
  /// list.
  private func usbStartupViolation(
    _ info: ControllerRecordDocument.ProtocolInfo
  ) -> ControllerRecordProblem? {
    guard !session.usbStartupWrites.isEmpty else { return nil }
    let carriesUSBWrites =
      ProtocolDescription.bundled[info.protocolID]?.usbStartupWrites.isEmpty == false
    guard !carriesUSBWrites || info.initialization != nil else { return nil }
    return .rule(
      "error.E5007.session.usbStartup",
      "raw-USB startup writes need a family that reads them and no initialization list"
    )
  }

  /// A rumble template of the wrong kind, for a driver that does not encode it, or with a resend
  /// interval that a keep-alive makes redundant.
  private func rumbleViolation(
    _ info: ControllerRecordDocument.ProtocolInfo,
    rawUSB: Bool
  ) -> ControllerRecordProblem? {
    guard let template = session.rumbleTemplate else { return nil }
    if (template.report == nil) != rawUSB {
      return .rule(
        "error.E5007.rumble.templateKind",
        "a raw-USB mode's rumble template is a usb packet, and a HID mode's is a HID report"
      )
    }
    if !info.protocolID.readsRecordRumbleTemplate(
      variant: info.protocolVariant,
      parameters: info.parameters
    ) {
      return RumbleOutputTemplate.driverProblem
    }
    if template.resendIntervalMilliseconds != nil {
      if session.keepAlive != nil { return RumbleOutputTemplate.resendWithKeepAliveProblem }
      if ProtocolDescription.bundled[info.protocolID]?.keepAlive != nil {
        return RumbleOutputTemplate.resendWithFamilyKeepAliveProblem
      }
    }
    return nil
  }

  /// A player-indicator template on a raw-USB mode or on a family whose driver encodes none.
  private func playerIndicatorViolation(
    _ info: ControllerRecordDocument.ProtocolInfo,
    rawUSB: Bool
  ) -> ControllerRecordProblem? {
    guard session.playerIndicatorTemplate != nil else { return nil }
    if rawUSB { return PlayerIndicatorOutputTemplate.templateKindProblem }
    if !info.protocolID.protocolDescription.recordSections.contains(.playerIndicator) {
      return PlayerIndicatorOutputTemplate.driverProblem
    }
    return nil
  }
}
