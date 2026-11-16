import Foundation

extension ControllerRecordDraft {
  /// The interface a mode matches: its USB class triple and, for a HID interface, its primary
  /// usage.
  private struct Signature: Hashable {
    let interfaceClass: UInt8
    let interfaceSubclass: UInt8
    let interfaceProtocol: UInt8
    let usagePage: UInt32?
    let usage: UInt32?

    /// The signature of `interface`; nil when the backend did not report its class triple.
    init?(_ interface: PhysicalInterfaceSignature) {
      guard let classCode = interface.interfaceClass,
        let subclassCode = interface.interfaceSubclass,
        let protocolCode = interface.interfaceProtocol
      else { return nil }
      self.interfaceClass = classCode
      self.interfaceSubclass = subclassCode
      self.interfaceProtocol = protocolCode
      let primary = interface.hidLayout?.primaryUsage
      usagePage = primary?.usagePage
      usage = primary?.usage
    }

    /// A mode ID that names the signature.
    var id: String {
      var parts = [
        "interface", "\(interfaceClass)", "\(interfaceSubclass)", "\(interfaceProtocol)",
      ]
      if let usagePage, let usage { parts += [String(usagePage, radix: 16), String(usage)] }
      return parts.joined(separator: "-")
    }

    /// The `match` of a mode.
    var match: [String: Any] {
      var signature: [String: Any] = [
        "interfaceClass": Int(interfaceClass), "interfaceSubclass": Int(interfaceSubclass),
        "interfaceProtocol": Int(interfaceProtocol),
      ]
      if let usagePage { signature["usagePage"] = Int(usagePage) }
      if let usage { signature["usage"] = Int(usage) }
      return ["interfaceSignature": signature]
    }
  }

  /// Drafts a record from the interfaces of `device`, which macOS lists whether or not OJD serves
  /// it.
  ///
  /// A device with an interface that meets the `HIDDescriptor` contract gets a `HIDDescriptor`
  /// mode: the `default` mode of a new `Controller`, or a patch that adds a mode matched on that
  /// interface when a bundled record holds the model. A device with no such interface gets one
  /// `HIDReportLayout` mode for each distinct interface signature and names `input` in
  /// ``missingSections``: the controls are not known without a capture. Nothing is captured, so the
  /// report fields are empty.
  ///
  /// Returns nil when no interface reports its class triple.
  public init?(model: ControllerModelID, device: PhysicalDevice) {
    let interfaces = device.interfaces ?? []
    let bundled = ControllerRecordSet.bundled.records[model]
    var taken = Set(bundled?.profile.modes.map(\.id) ?? [])
    func modeID(_ preferred: String) -> String {
      var id = preferred
      var count = 1
      while taken.contains(id) {
        count += 1
        id = "\(preferred)-\(count)"
      }
      taken.insert(id)
      return id
    }

    var modes: [[String: Any]] = []
    if let gamepad = interfaces.first(where: {
      HIDDescriptorContract.violation(in: $0.hidLayout) == nil
    }) {
      family = .hidDescriptor
      missingSections = []
      var mode: [String: Any] = [
        "id": modeID(bundled == nil ? "default" : "hid"),
        "protocol": ["family": family.rawValue],
      ]
      if bundled != nil, let signature = Signature(gamepad) { mode["match"] = signature.match }
      modes = [mode]
    } else {
      family = .hidReportLayout
      missingSections = ["input"]
      var seen = Set<Signature>()
      for signature in interfaces.compactMap(Signature.init) where seen.insert(signature).inserted {
        modes.append([
          "id": modeID(signature.id), "protocol": ["family": family.rawValue],
          "match": signature.match,
        ])
      }
    }
    guard !modes.isEmpty else { return nil }

    let body: [String: Any]
    if bundled != nil {
      body = ControllerPatch.document(selector: .identity(model), body: ["modes": modes])
    } else {
      body = [
        "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
        "vendorID": Int(model.vendorID), "productID": Int(model.productID), "modes": modes,
      ]
    }
    guard let json = try? OrderedJSON(foundation: body), let data = try? json.plistData() else {
      return nil
    }
    operation = bundled == nil ? .add : .patch
    reportID = nil
    reportLength = nil
    capturedReports = 0
    changedBytes = []
    text = String(bytes: data, encoding: .utf8) ?? ""
  }
}
