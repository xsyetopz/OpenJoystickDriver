import Foundation

extension ControllerRecordDocument {
  /// The record's `bluetoothLE` section: the GATT characteristic that carries vibration.
  struct BluetoothLE: Decodable {
    /// An uppercase UUID string, as the schema requires.
    let vibrationCharacteristic: String

    /// Decodes the Bluetooth LE section, which holds exactly `vibrationCharacteristic`; any other
    /// key is rejected.
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
}
