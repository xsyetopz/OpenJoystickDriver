import Foundation

extension ControllerRecordDocument {
  /// The record's `bluetoothLE` section: the GATT characteristic that carries vibration.
  struct BluetoothLE: Decodable {
    /// An uppercase UUID string, as the schema requires.
    let vibrationCharacteristic: String

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["vibrationCharacteristic"])
      let uuid = try container.decode(String.self, for: "vibrationCharacteristic")
      // `uuidString` is the uppercase canonical form, so equality checks the exact format.
      guard UUID(uuidString: uuid)?.uuidString == uuid else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("vibrationCharacteristic")],
            debugDescription: "vibrationCharacteristic must be an uppercase UUID"
          )
        )
      }
      vibrationCharacteristic = uuid
    }
  }

  /// Only the Switch 2 Bluetooth LE central reads the section.
  func validateBluetoothLE(codingPath: [any CodingKey]) throws {
    guard bluetoothLE != nil,
      protocolInfo.protocolID != .nintendoSwitch1 || !protocolInfo.quirks.contains(.switch2)
    else { return }
    throw DecodingError.dataCorrupted(
      .init(
        codingPath: codingPath + [DocumentKey("bluetoothLE")],
        debugDescription: "bluetoothLE requires a Switch 2 controller"
      )
    )
  }
}
