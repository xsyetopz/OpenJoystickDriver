import Foundation
import OpenJoystickDriverKit

enum MappingRenderer {
  static func json<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    guard let result = String(data: data, encoding: .utf8) else {
      throw MappingCommandError.invalidArguments("Could not encode UTF-8 JSON.")
    }
    return result
  }

  static func profile(_ profile: RemappingProfile) -> String {
    let header =
      "\(profile.id.uuidString)  \(profile.name)  "
      + "\(profile.device.vendorID):\(profile.device.productID)  \(scope(profile.applicationScope))"
    let bindings = profile.bindings.map {
      "  \($0.id.uuidString) \(source($0.source)) -> \(destination($0.destination))"
    }
    return ([header] + bindings).joined(separator: "\n")
  }

  static func snapshot(_ snapshot: ApplicationServiceRemappingSnapshotPayload) -> String {
    var lines = ["Post-event access: \(snapshot.postEventAccess.rawValue)", "Profiles:"]
    lines += snapshot.profiles.map(profile)
    lines.append("Routes:")
    lines += snapshot.routes.map {
      "  \($0.vendorID):\($0.productID) \($0.runtimeIdentifier) "
        + "\($0.selection.rawValue)/\($0.eligibility.rawValue)"
    }
    return lines.joined(separator: "\n")
  }

  static func source(_ source: RemappingSource) -> String {
    switch source {
    case .button(let value): "button:\(value.rawValue)"
    case .dpad(let value): "dpad:\(value.rawValue)"
    case .axis(let value): "axis:\(value.rawValue)"
    case .axisDirection(let axis, let direction): "axis:\(axis.rawValue):\(direction.rawValue)"
    }
  }

  static func destination(_ destination: RemappingDestination) -> String {
    switch destination {
    case .keyboard(let key, let modifiers):
      let suffix =
        modifiers.isEmpty
        ? "" : ":mods=" + modifiers.map(\.rawValue).sorted().joined(separator: ",")
      return "key:\(key.rawValue)\(suffix)"
    case .mouseButton(let value): return "mouse:\(value.rawValue)"
    case .mouseMovement(let value): return "move:\(value.rawValue)"
    case .scroll(let value): return "scroll:\(value.rawValue)"
    }
  }

  private static func scope(_ scope: RemappingApplicationScope) -> String {
    switch scope {
    case .global: "global"
    case .application(let bundleID): "app:\(bundleID)"
    }
  }
}
