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
    let bindings = profile.bindings.map { binding in
      var line =
        "  \(binding.id.uuidString) \(source(binding.source)) -> "
        + "\(destination(binding.destination))"
      if let longHold = binding.longHold {
        line += "  [long-hold: \(longHold.durationMs)ms -> \(destination(longHold.destination))]"
      }
      if let doubleTap = binding.doubleTap {
        line += "  [double-tap: \(doubleTap.windowMs)ms -> \(destination(doubleTap.destination))]"
      }
      return line
    }
    let chords = profile.chords.map { chord in
      let sources = chord.sources.map(source).sorted().joined(separator: ",")
      return "  \(chord.id.uuidString) chord[\(sources)] -> \(destination(chord.destination))"
    }
    let sequences = profile.sequences.map { seq in
      let sources = seq.sources.map(source).joined(separator: ",")
      return "  \(seq.id.uuidString) sequence[\(sources)] window:\(seq.windowMs)ms -> "
        + "\(destination(seq.destination))"
    }
    let layers = profile.layers.map { layer in
      "  \(layer.id.uuidString) layer:\(layer.name) "
        + "\(layer.activationMode.rawValue):\(source(layer.activator)) "
        + "bindings:\(layer.bindings.count)"
    }
    return ([header] + bindings + chords + sequences + layers).joined(separator: "\n")
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

  static func layers(_ profile: RemappingProfile) -> String {
    if profile.layers.isEmpty { return "No layers." }
    return profile.layers.enumerated().map { index, layer in
      let bindings = layer.bindings.map { b in
        "    \(b.id.uuidString) \(source(b.source)) -> \(destination(b.destination))"
      }
      return "  [\(index)] \(layer.id.uuidString) \(layer.name) "
        + "\(layer.activationMode.rawValue):\(source(layer.activator))\n"
        + bindings.joined(separator: "\n")
    }.joined(separator: "\n")
  }
}
