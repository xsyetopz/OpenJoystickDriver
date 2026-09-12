import Foundation
import OpenJoystickDriverKit

enum MappingRenderer {
  static func json<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    guard let result = String(data: data, encoding: .utf8) else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text("cli.mapping.jsonEncodeFailed", "Could not encode UTF-8 JSON.")
      )
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
    let touchMappings = profile.touchMappings.map { mapping in
      "  touch:\(mapping.surface.rawValue) mode:\(mapping.mode.rawValue) "
        + "pointer-sensitivity:\(mapping.pointerSensitivity) "
        + "stick-radius:\(mapping.stickRadius) deadzone:\(mapping.deadzone)"
    }
    let stickMappings = profile.stickMappings.map { mapping in
      "  stick:\(mapping.source.rawValue) mode:\(mapping.mode.rawValue) "
        + "passthrough:\(mapping.passthrough)"
    }
    let triggerMappings = profile.triggerMappings.map { mapping in
      "  trigger:\(mapping.source.rawValue) mode:\(mapping.mode.rawValue) "
        + "soft:\(mapping.softThreshold) full:\(mapping.fullThreshold) "
        + "hysteresis:\(mapping.hysteresis) window:\(mapping.skipWindowMs)ms "
        + "passthrough:\(mapping.passthrough)"
    }
    var lines = [header]
    if let settings = profile.joyConPair {
      lines.append("  joy-con-pair gyro:\(settings.gyroSelection.rawValue)")
    }
    if profile.gyroOutput.mode != .disabled || profile.gyroOutput.virtualMotion {
      lines.append(
        "  gyro-output mode:\(profile.gyroOutput.mode.rawValue) "
          + "virtual-motion:\(profile.gyroOutput.virtualMotion)"
      )
    }
    if let lean = profile.motionTuning.lean {
      lines.append(
        "  motion-lean threshold:\(lean.thresholdDegrees)deg "
          + "hysteresis:\(lean.hysteresisDegrees)deg"
      )
    }
    if let steering = profile.motionTuning.steering {
      lines.append(
        "  motion-steering output:\(steering.output.rawValue) "
          + "deadzone:\(steering.deadzoneDegrees)deg "
          + "full-scale:\(steering.fullScaleDegrees)deg"
      )
    }
    lines.append(contentsOf: stickMappings)
    lines.append(contentsOf: triggerMappings)
    lines.append(contentsOf: touchMappings)
    lines.append(contentsOf: bindings)
    lines.append(contentsOf: chords)
    lines.append(contentsOf: sequences)
    lines.append(contentsOf: layers)
    return lines.joined(separator: "\n")
  }

  static func snapshot(_ snapshot: ApplicationServiceRemappingSnapshotPayload) -> String {
    var lines = [
      CLILocalized.format(
        "cli.mapping.postEventAccess",
        "Post-event access: %@",
        snapshot.postEventAccess.rawValue
      ), CLILocalized.text("cli.mapping.profiles", "Profiles:"),
    ]
    lines += snapshot.profiles.map(profile)
    lines.append(CLILocalized.text("cli.mapping.routes", "Routes:"))
    lines += snapshot.routes.map {
      "  \($0.vendorID):\($0.productID) \($0.runtimeIdentifier) "
        + "\($0.selection.rawValue)/\($0.eligibility.rawValue)"
    }
    lines.append(CLILocalized.text("cli.mapping.joyConPairs", "Paired Joy-Cons:"))
    lines += snapshot.joyConPairs.map {
      "  \($0.sessionID.uuidString) left:\($0.leftRuntimeIdentifier) "
        + "right:\($0.rightRuntimeIdentifier) profile:\($0.profileName) "
        + "gyro:\($0.gyroSelection.rawValue)"
    }
    return lines.joined(separator: "\n")
  }

  static func source(_ source: RemappingSource) -> String {
    switch source {
    case .button(let value): "button:\(value.rawValue)"
    case .dpad(let value): "dpad:\(value.rawValue)"
    case .axis(let value): "axis:\(value.rawValue)"
    case .axisDirection(let axis, let direction): "axis:\(axis.rawValue):\(direction.rawValue)"
    case .triggerStage(let trigger, let stage):
      "trigger:\(trigger.rawValue):\(stage.rawValue)"
    case .motionLean(let direction): "motion:lean:\(direction.rawValue)"
    case .touchContact(let surface): "touch:\(surface.rawValue):contact"
    case .touchGrid(let grid):
      "touch:\(grid.surface.rawValue):grid:\(grid.columns):\(grid.rows):\(grid.column):\(grid.row)"
    case .touchSwipe(let swipe):
      "touch:\(swipe.surface.rawValue):swipe:\(swipe.direction.rawValue):\(swipe.minimumDistance)"
    }
  }

  static func destination(_ destination: RemappingDestination) -> String {
    switch destination {
    case .gamepadAxis(let axis): return "gamepad:axis:\(axis.rawValue)"
    case .gamepadDpad(let direction): return "gamepad:dpad:\(direction.rawValue)"
    case .gamepadButton(let button): return "gamepad:button:\(button.rawValue)"
    case .keyboard(let key, let modifiers):
      let suffix =
        modifiers.isEmpty
        ? "" : ":mods=" + modifiers.map(\.rawValue).sorted().joined(separator: ",")
      return "key:\(key.rawValue)\(suffix)"
    case .mouseButton(let value): return "mouse:\(value.rawValue)"
    case .mouseMovement(let value): return "move:\(value.rawValue)"
    case .scroll(let value): return "scroll:\(value.rawValue)"
    case .physical(let output): return physicalOutput(output)
    }
  }

  private static func physicalOutput(_ output: RemappingPhysicalOutput) -> String {
    switch output {
    case .rumble(let motor, let intensity):
      return "physical:rumble:\(motor.rawValue):\(intensity)"
    case .playerIndicator(let indicator):
      return "physical:player:\(indicator.rawValue)"
    case .color(let red, let green, let blue):
      return "physical:color:\(red):\(green):\(blue)"
    case .brightness(let intensity):
      return "physical:brightness:\(intensity)"
    case .adaptiveTrigger(let trigger, let effect):
      switch effect.kind {
      case .off:
        return "physical:adaptive:\(trigger.rawValue):off"
      case .resistance:
        return "physical:adaptive:\(trigger.rawValue):resistance:"
          + "\(effect.startPosition):\(effect.strength)"
      }
    }
  }

  private static func scope(_ scope: RemappingApplicationScope) -> String {
    switch scope {
    case .global: "global"
    case .application(let bundleID): "app:\(bundleID)"
    }
  }

  static func layers(_ profile: RemappingProfile) -> String {
    if profile.layers.isEmpty { return CLILocalized.text("cli.mapping.noLayers", "No layers.") }
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
