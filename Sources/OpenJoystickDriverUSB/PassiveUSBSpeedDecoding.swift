import Foundation

extension PassiveUSBRegistryFactParser {
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
    if speeds.count == 1, let speed = speeds.first {
      return PassiveUSBSpeedObservation(
        state: .observed,
        speed: speed,
        sources: candidates.map(\.0),
        values: candidates.map { String(describing: $0.1) },
        properties: properties
      )
    }
    return PassiveUSBSpeedObservation(
      state: .ambiguous,
      speed: nil,
      sources: candidates.map(\.0),
      values: candidates.map { String(describing: $0.1) },
      properties: properties
    )
  }

  static func speedValue(key: String, value: PassiveUSBRegistryNode.Value)
    -> PassiveUSBNegotiatedSpeed?
  {
    switch value {
    case .unsignedInteger(let raw):
      switch key {
      case "USBSpeed":
        switch raw {
        case 0: return nil
        case 1: return .full
        case 2: return .low
        case 3: return .high
        case 4: return .superSpeed
        case 5, 6: return .superSpeedPlus
        default: return nil
        }
      case "Device Speed":
        switch raw {
        case 0: return .low
        case 1: return .full
        case 2: return .high
        case 3: return .superSpeed
        case 4, 5: return .superSpeedPlus
        default: return nil
        }
      case "UsbLinkSpeed":
        switch raw {
        case 1_500_000: return .low
        case 12_000_000: return .full
        case 480_000_000: return .high
        case 5_000_000_000: return .superSpeed
        case 10_000_000_000, 20_000_000_000: return .superSpeedPlus
        default: return nil
        }
      default: return nil
      }
    case .string(let raw):
      switch raw.lowercased().replacingOccurrences(of: "-", with: "") {
      case "low", "lowspeed": return .low
      case "full", "fullspeed": return .full
      case "high", "highspeed": return .high
      case "superspeed", "ss": return .superSpeed
      case "superspeedplus", "ssplus": return .superSpeedPlus
      default: return nil
      }
    case .bytes: return nil
    }
  }

  static func rawType(_ value: PassiveUSBRegistryNode.Value) -> String {
    switch value {
    case .unsignedInteger: return "unsignedInteger"
    case .string: return "string"
    case .bytes: return "bytes"
    }
  }

  static func rawValue(_ value: PassiveUSBRegistryNode.Value) -> String {
    switch value {
    case .unsignedInteger(let raw): return String(raw)
    case .string(let raw): return raw
    case .bytes(let raw): return "bytes:\(raw.count)"
    }
  }

}
