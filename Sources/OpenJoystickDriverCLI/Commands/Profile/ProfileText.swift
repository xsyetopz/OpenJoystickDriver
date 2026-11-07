import Foundation
import OpenJoystickDriverKit

/// Profile values as the text that `binding set` accepts and `profile show` prints.
enum ProfileText {
  /// The command-line spelling of an enumerated word: its lowercase kebab-case form.
  private static func word<Value: RawRepresentable>(_ value: Value) -> String
  where Value.RawValue == String { CommandLineName.kebab(value.rawValue) }

  /// The app scope: `global` or `app:BUNDLE-ID`.
  static func scope(_ scope: RemappingApplicationScope) -> String {
    switch scope {
    case .global: "global"
    case .application(let appID): "app:\(appID)"
    }
  }

  /// The binding source in its `SOURCE` form.
  static func source(_ source: RemappingSource) -> String {
    switch source {
    case .button(let value): "button:\(word(value))"
    case .dpad(let value): "dpad:\(word(value))"
    case .axis(let value): "axis:\(word(value))"
    case .axisDirection(let axis, let direction): "axis:\(word(axis)):\(word(direction))"
    case .triggerStage(let trigger, let stage): "trigger:\(word(trigger)):\(word(stage))"
    case .motionLean(let direction): "motion:lean:\(word(direction))"
    case .touchContact(let surface): "touch:\(word(surface)):contact"
    case .touchGrid(let grid):
      "touch:\(word(grid.surface)):grid:\(grid.columns):\(grid.rows):\(grid.column):\(grid.row)"
    case .touchSwipe(let swipe):
      "touch:\(word(swipe.surface)):swipe:\(word(swipe.direction)):\(swipe.minimumDistance)"
    case .stickRegion(let region):
      "stick-region:\(word(region.stick)):\(region.innerRadius)-\(region.outerRadius)"
        + (region.fromDegrees.flatMap { from in region.toDegrees.map { ":\(from)-\($0)" } } ?? "")
    case .triggerBand(let band): "trigger-band:\(word(band.trigger)):\(band.from)-\(band.to)"
    case .touchArea(let area):
      "touch:\(word(area.surface)):area:\(area.x):\(area.y):\(area.width):\(area.height)"
    }
  }

  /// The binding target in its `TARGET` form; a macro and a layer show their names from `macros`
  /// and `layers`.
  static func destination(
    _ destination: RemappingDestination,
    macros: [RemappingMacro] = [],
    layers: [RemappingLayer] = []
  ) -> String {
    switch destination {
    case .gamepadAxis(let axis): return "gamepad:axis:\(word(axis))"
    case .gamepadDpad(let direction): return "gamepad:dpad:\(word(direction))"
    case .gamepadButton(let button): return "gamepad:button:\(word(button))"
    case .keyboard(let key, let modifiers):
      let suffix =
        modifiers.isEmpty
        ? "" : ":mods=" + modifiers.map(word).sorted().joined(separator: ",")
      return "key:\(word(key))\(suffix)"
    case .mouseButton(let value): return "mouse:\(word(value))"
    case .mouseMovement(let value): return "move:\(word(value))"
    case .scroll(let value): return "scroll:\(word(value))"
    case .physical(let output): return physicalOutput(output)
    case .macro(let id): return "macro:\(macros.first { $0.id == id }?.name ?? id.uuidString)"
    case .profileSwitch(.profile(let id)): return "profile:switch:\(id.uuidString)"
    case .profileSwitch(let target):
      return "profile:switch:\(target == .next ? "next" : "previous")"
    case .layerSet(let layer, let mode):
      return "layer:\(layers.first { $0.id == layer }?.name ?? layer.uuidString):\(word(mode))"
    case .pause(let mode): return "pause:\(word(mode))"
    case .systemKey(let key): return "system-key:\(word(key))"
    case .systemAction(let action): return "system:\(word(action))"
    case .openApplication(let identifier): return "open-app:\(identifier)"
    case .openURL(let url): return "open-url:\(url)"
    case .runShortcut(let name): return "shortcut:\(name)"
    case .typeText(let text): return "text:\(text)"
    case .speak(let text, _): return "speak:\(text)"
    }
  }

  /// The physical output in its `physical:...` target form.
  private static func physicalOutput(_ output: RemappingPhysicalOutput) -> String {
    switch output {
    case .rumble(let motor, let intensity): return "physical:rumble:\(word(motor)):\(intensity)"
    case .playerIndicator(let indicator): return "physical:player:\(indicator.rawValue)"
    case .color(let color): return "physical:color:\(color.red):\(color.green):\(color.blue)"
    case .brightness(let intensity): return "physical:brightness:\(intensity)"
    case .adaptiveTrigger(let trigger, let effect):
      switch effect.kind {
      case .off: return "physical:adaptive:\(word(trigger)):off"
      case .resistance:
        return "physical:adaptive:\(word(trigger)):resistance:"
          + "\(effect.startPosition):\(effect.strength)"
      }
    }
  }

  /// One binding as `SOURCE -> TARGET`, followed by its behavior and alternate targets.
  static func binding(
    _ binding: RemappingBinding,
    macros: [RemappingMacro] = [],
    layers: [RemappingLayer] = []
  ) -> String {
    var line =
      "\(source(binding.source)) -> \(destination(binding.destination, macros: macros, layers: layers))"
    if binding.behavior != .hold { line += "  behavior:\(word(binding.behavior))" }
    if binding.behavior == .pulse { line += "  pulse:\(binding.pulseDurationMs)ms" }
    if let turbo = binding.turbo {
      line += "  turbo:\(turbo.repeatRateHz)Hz/\(turbo.dutyCycle)"
      if turbo.initialDelayMs != 0 { line += " delay:\(turbo.initialDelayMs)ms" }
      if let cap = turbo.maxRepeats { line += " max:\(cap)" }
    }
    if let longHold = binding.longHold {
      line += "  long-hold:\(longHold.durationMs)ms -> \(destination(longHold.destination))"
    }
    for tap in binding.multiTap.sorted(by: { $0.count < $1.count }) {
      line += "  multi-tap:\(tap.count)x\(tap.windowMs)ms -> \(destination(tap.destination))"
    }
    if !binding.multiTap.isEmpty {
      line += "  tap-delay:\(binding.multiTap.longestWindowMs)ms"
    }
    if !binding.additionalActions.isEmpty { line += "  actions:\(binding.additionalActions.count)" }
    return line
  }

  /// Everything in the profile other than its header, one item per line.
  static func details(_ profile: RemappingProfile) -> [String] {
    var lines = [
      "output virtual-gamepad:\(word(profile.outputPolicy.virtualGamepad)) "
        + "physical-input:\(word(profile.outputPolicy.physicalInput))"
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
      "stick:\(word($0.source)) mode:\($0.mode.rawValue) passthrough:\($0.passthrough)"
    }
    lines += profile.triggerMappings.map {
      "trigger:\(word($0.source)) mode:\(word($0.mode)) soft:\($0.softThreshold) "
        + "full:\($0.fullThreshold) passthrough:\($0.passthrough)"
    }
    lines += profile.touchMappings.map { "touch:\(word($0.surface)) mode:\($0.mode.rawValue)" }
    lines += profile.bindings.map { binding($0, macros: profile.macros, layers: profile.layers) }
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
      "layer \(layer.name) \(word(layer.activationMode)):\(source(layer.activator)) "
        + "bindings:\(layer.bindings.count)"
    }
    return lines
  }
}
