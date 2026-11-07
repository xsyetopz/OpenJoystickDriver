extension ControllerRecordDocument {
  /// The record-level sections that depend on a mode's transport.
  ///
  /// Each holds for every mode of the record, whether it has one mode or many: `usb` and `route`
  /// need raw-USB modes only, `server` needs HID modes only, `bluetoothLE` needs modes whose driver
  /// reads it, and `usb.endpoints` differs from the default endpoints of some mode's family.
  func validateTransportSections(codingPath: [any CodingKey]) throws {
    func fail(_ key: String, _ message: String) -> DecodingError {
      .dataCorrupted(
        .init(codingPath: codingPath + [DocumentKey(key)], debugDescription: message)
      )
    }
    let infos = modes.map(\.protocolInfo)
    let allRawUSB = infos.allSatisfy {
      $0.protocolID.usesRawUSB(storedVariant: $0.protocolVariant)
    }
    let anyRawUSB = infos.contains {
      $0.protocolID.usesRawUSB(storedVariant: $0.protocolVariant)
    }
    if usb != nil, !allRawUSB {
      throw fail("usb", "USB overrides require a raw-USB protocol family")
    }
    if server != nil, anyRawUSB {
      throw fail("server", "server applies only to HID controllers")
    }
    if route != nil, !allRawUSB {
      throw fail("route", "route ExtensionOwned applies only to raw-USB controllers")
    }
    if bluetoothLE != nil,
      !infos.allSatisfy({ $0.protocolID.protocolDescription.recordSections.contains(.bluetoothLE) })
    {
      throw fail("bluetoothLE", "bluetoothLE requires a driver that reads it")
    }
    if let endpoints = usb?.endpoints {
      let isDefault = infos.allSatisfy {
        let defaults = $0.protocolID.protocolDescription.endpoints
        return (endpoints.input, endpoints.output) == (defaults.input, defaults.output)
      }
      if isDefault {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: codingPath + [DocumentKey("usb"), DocumentKey("endpoints")],
            debugDescription: "protocol-default endpoints must be omitted"
          )
        )
      }
    }
  }
}
