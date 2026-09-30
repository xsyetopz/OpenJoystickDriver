import Foundation
import OpenJoystickDriverKit

/// Profile values as the text that `binding set` accepts and `profile show` prints.
enum ProfileText {
  static func scope(_ scope: RemappingApplicationScope) -> String {
    switch scope {
    case .global: "global"
    case .application(let bundleID): "app:\(bundleID)"
    }
  }

  static func source(_ source: RemappingSource) -> String {
    switch source {
    case .button(let value): "button:\(value.rawValue)"
    case .dpad(let value): "dpad:\(value.rawValue)"
    case .axis(let value): "axis:\(value.rawValue)"
    case .axisDirection(let axis, let direction): "axis:\(axis.rawValue):\(direction.rawValue)"
    case .triggerStage(let trigger, let stage): "trigger:\(trigger.rawValue):\(stage.rawValue)"
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
    case .rumble(let motor, let intensity): return "physical:rumble:\(motor.rawValue):\(intensity)"
    case .playerIndicator(let indicator): return "physical:player:\(indicator.rawValue)"
    case .color(let color): return "physical:color:\(color.red):\(color.green):\(color.blue)"
    case .brightness(let intensity): return "physical:brightness:\(intensity)"
    case .adaptiveTrigger(let trigger, let effect):
      switch effect.kind {
      case .off: return "physical:adaptive:\(trigger.rawValue):off"
      case .resistance:
        return "physical:adaptive:\(trigger.rawValue):resistance:"
          + "\(effect.startPosition):\(effect.strength)"
      }
    }
  }

  /// One binding as `SOURCE -> TARGET`, followed by its behavior and alternate targets.
  static func binding(_ binding: RemappingBinding) -> String {
    var line = "\(source(binding.source)) -> \(destination(binding.destination))"
    if binding.behavior != .hold { line += "  behavior:\(binding.behavior.rawValue)" }
    if binding.behavior == .pulse { line += "  pulse:\(binding.pulseDurationMs)ms" }
    if let turbo = binding.turbo { line += "  turbo:\(turbo.repeatRateHz)Hz/\(turbo.dutyCycle)" }
    if let longHold = binding.longHold {
      line += "  long-hold:\(longHold.durationMs)ms -> \(destination(longHold.destination))"
    }
    if let doubleTap = binding.doubleTap {
      line += "  double-tap:\(doubleTap.windowMs)ms -> \(destination(doubleTap.destination))"
    }
    if !binding.additionalActions.isEmpty { line += "  actions:\(binding.additionalActions.count)" }
    return line
  }

  /// Everything in the profile other than its header, one item per line.
  static func details(_ profile: RemappingProfile) -> [String] {
    var lines = [
      "output virtual-gamepad:\(profile.outputPolicy.virtualGamepad.rawValue) "
        + "physical-input:\(profile.outputPolicy.physicalInput.rawValue)"
    ]
    if let settings = profile.joyConPair {
      lines.append("joy-con-pair gyro:\(settings.gyroSelection.rawValue)")
    }
    if profile.gyroOutput.mode != .disabled {
      lines.append("gyro-output mode:\(profile.gyroOutput.mode.rawValue)")
    }
    if let lean = profile.motionTuning.lean {
      lines.append(
        "motion-lean threshold:\(lean.thresholdDegrees)deg hysteresis:\(lean.hysteresisDegrees)deg"
      )
    }
    if let steering = profile.motionTuning.steering {
      lines.append(
        "motion-steering output:\(steering.output.rawValue) "
          + "deadzone:\(steering.deadzoneDegrees)deg full-scale:\(steering.fullScaleDegrees)deg"
      )
    }
    lines += profile.stickMappings.map {
      "stick:\($0.source.rawValue) mode:\($0.mode.rawValue) passthrough:\($0.passthrough)"
    }
    lines += profile.triggerMappings.map {
      "trigger:\($0.source.rawValue) mode:\($0.mode.rawValue) soft:\($0.softThreshold) "
        + "full:\($0.fullThreshold) passthrough:\($0.passthrough)"
    }
    lines += profile.touchMappings.map { "touch:\($0.surface.rawValue) mode:\($0.mode.rawValue)" }
    lines += profile.bindings.map(binding)
    lines += profile.chords.map { chord in
      let sources = chord.sources.map(source).sorted().joined(separator: "+")
      return "chord \(sources) -> \(destination(chord.destination))"
    }
    lines += profile.sequences.map { sequence in
      let sources = sequence.sources.map(source).joined(separator: ",")
      return "sequence \(sources) within:\(sequence.windowMs)ms -> "
        + destination(sequence.destination)
    }
    lines += profile.layers.map { layer in
      "layer \(layer.name) \(layer.activationMode.rawValue):\(source(layer.activator)) "
        + "bindings:\(layer.bindings.count)"
    }
    return lines
  }
}
