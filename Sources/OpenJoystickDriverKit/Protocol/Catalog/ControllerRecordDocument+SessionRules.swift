extension ControllerRecordDocument.ModeDocument {
  /// Why this mode's session cannot run on its own protocol, or nil.
  ///
  /// HID startup writes go to HID modes, raw-USB startup packets go to raw-USB families that read
  /// them and name no initialization list, a keep-alive extends a raw-USB family whose description
  /// declares none, settle, shutdown and control transfers belong to raw-USB modes, and only a
  /// driver that encodes a rumble template for the mode's variant and parameters may name one, a
  /// usb packet in a raw-USB mode and a HID report in a HID mode, and a template's resend interval
  /// needs neither a session keep-alive nor a family whose description declares one.
  func sessionViolation() -> String? {
    let info = protocolInfo
    let rawUSB = info.protocolID.usesRawUSB(storedVariant: info.protocolVariant)
    if rawUSB {
      if !session.startupWrites.isEmpty {
        return "HID startup writes apply only to HID controllers, so not to a raw-USB mode"
      }
      if session.keepAlive != nil, ProtocolDescription.bundled[info.protocolID]?.keepAlive != nil {
        return "a session keepAlive needs a raw-USB family whose description declares none"
      }
    } else {
      let named: [(String, Bool)] = [
        ("keepAlive", session.keepAlive != nil),
        ("settleMilliseconds", session.settleMilliseconds != nil),
        ("shutdown", !session.shutdownWrites.isEmpty),
        ("control", !session.controlTransfers.isEmpty),
      ]
      if let (key, _) = named.first(where: \.1) {
        return "session \(key) applies only to raw-USB modes"
      }
    }
    if !session.usbStartupWrites.isEmpty {
      let carriesUSBWrites =
        ProtocolDescription.bundled[info.protocolID]?.usbStartupWrites.isEmpty == false
      if !carriesUSBWrites || info.initialization != nil {
        return "raw-USB startup writes need a family that reads them and no initialization list"
      }
    }
    if let template = session.rumbleTemplate {
      if (template.report == nil) != rawUSB {
        return "a raw-USB mode's rumble template is a usb packet, and a HID mode's is a HID report"
      }
      if !info.protocolID.readsRecordRumbleTemplate(
        variant: info.protocolVariant,
        parameters: info.parameters
      ) {
        return "rumble templates require a driver that encodes them"
      }
      if template.resendIntervalMilliseconds != nil {
        if session.keepAlive != nil { return RumbleOutputTemplate.resendWithKeepAliveProblem }
        if ProtocolDescription.bundled[info.protocolID]?.keepAlive != nil {
          return RumbleOutputTemplate.resendWithFamilyKeepAliveProblem
        }
      }
    }
    return nil
  }
}
