import Foundation

extension PassiveUSBRegistryFactParser {
  /// Reads the speed properties of `node` and its descendants into one observation.
  static func observeSpeed(_ node: PassiveUSBRegistryNode) -> PassiveUSBSpeedObservation {
    let keys = ["USBSpeed", "Device Speed", "UsbLinkSpeed", "USB Speed"]
    var candidates: [(String, PassiveUSBNegotiatedSpeed)] = []
    var properties: [PassiveUSBSpeedPropertyObservation] = []
    func visit(_ node: PassiveUSBRegistryNode) {
      for key in keys {
        guard let value = node.properties[key] else { continue }
        let speed = speedValue(key: key, value: value)
        properties.append(
          PassiveUSBSpeedPropertyObservation(
            key: key,
            rawType: rawType(value),
            rawValue: rawValue(value),
            decodedSpeed: speed
          )
        )
        if let speed { candidates.append((key, speed)) }
      }
      node.children.forEach(visit)
    }
    visit(node)
    let speeds = Set(candidates.map(\.1))
    if candidates.isEmpty {
      return PassiveUSBSpeedObservation(
        state: .absent,
        speed: nil,
        sources: [],
        values: [],
        properties: properties
      )
    }
    let agreedSpeed = speeds.count == 1 ? speeds.first : nil
    return PassiveUSBSpeedObservation(
      state: agreedSpeed == nil ? .ambiguous : .observed,
      speed: agreedSpeed,
      sources: candidates.map(\.0),
      values: candidates.map { String(describing: $0.1) },
      properties: properties
    )
  }

  /// The speed each numeric code of a registry speed property stands for, by property key.
  ///
  /// `USBSpeed` code 0 and every code a table omits decode to no speed.
  private static let numericSpeedCodes: [String: [UInt64: PassiveUSBNegotiatedSpeed]] = [
    "USBSpeed": [
      1: .full, 2: .low, 3: .high, 4: .superSpeed, 5: .superSpeedPlus, 6: .superSpeedPlus,
    ],
    "Device Speed": [
      0: .low, 1: .full, 2: .high, 3: .superSpeed, 4: .superSpeedPlus, 5: .superSpeedPlus,
    ],
    "UsbLinkSpeed": [
      1_500_000: .low,
      12_000_000: .full,
      480_000_000: .high,
      5_000_000_000: .superSpeed,
      10_000_000_000: .superSpeedPlus,
      20_000_000_000: .superSpeedPlus,
    ],
  ]

  /// The speed each spelling of a textual speed property stands for, lowercased without hyphens.
  private static let textSpeedNames: [String: PassiveUSBNegotiatedSpeed] = [
    "low": .low, "lowspeed": .low,
    "full": .full, "fullspeed": .full,
    "high": .high, "highspeed": .high,
    "superspeed": .superSpeed, "ss": .superSpeed,
    "superspeedplus": .superSpeedPlus, "ssplus": .superSpeedPlus,
  ]

  /// Decodes the speed that the property `key` shows with `value`, or nil when it does not decode.
  static func speedValue(
    key: String,
    value: PassiveUSBRegistryNode.Value
  ) -> PassiveUSBNegotiatedSpeed? {
    switch value {
    case .unsignedInteger(let raw): numericSpeedCodes[key]?[raw]
    case .string(let raw): textSpeedNames[raw.lowercased().replacingOccurrences(of: "-", with: "")]
    case .bytes: nil
    }
  }

  /// Returns the name of the type of `value`.
  static func rawType(_ value: PassiveUSBRegistryNode.Value) -> String {
    switch value {
    case .unsignedInteger: return "unsignedInteger"
    case .string: return "string"
    case .bytes: return "bytes"
    }
  }

  /// Returns `value` as text; a byte array shows only its length.
  static func rawValue(_ value: PassiveUSBRegistryNode.Value) -> String {
    switch value {
    case .unsignedInteger(let raw): return String(raw)
    case .string(let raw): return raw
    case .bytes(let raw): return "bytes:\(raw.count)"
    }
  }

}
