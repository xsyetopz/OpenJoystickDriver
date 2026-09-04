import Foundation
import OpenJoystickDriverKit

enum MappingProfileEditor {
  static func replacingBinding(
    in profile: RemappingProfile,
    source: RemappingSource,
    destination: RemappingDestination,
    options: MappingOptions
  ) throws -> RemappingProfile {
    let (axisTuning, turbo, longHold, doubleTap) = try resolvedBindingOptions(
      source: source,
      destination: destination,
      options: options
    )
    let existingID = profile.bindings.first { $0.source == source }?.id
    let replacement = RemappingBinding(
      id: existingID ?? UUID(),
      source: source,
      destination: destination,
      axisTuning: axisTuning,
      turbo: turbo,
      longHold: longHold,
      doubleTap: doubleTap
    )
    let bindings = profile.bindings.filter { $0.source != source } + [replacement]
    return try copyAndValidate(copy(profile, bindings: bindings))
  }

  static func removingBinding(from profile: RemappingProfile, source: RemappingSource) throws
    -> RemappingProfile
  {
    guard profile.bindings.contains(where: { $0.source == source }) else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.binding_missing",
          "No binding exists for the requested source."
        )
      )
    }
    return copy(profile, bindings: profile.bindings.filter { $0.source != source })
  }

  static func addingChord(
    in profile: RemappingProfile,
    sources: [RemappingSource],
    destination: RemappingDestination
  ) throws -> RemappingProfile {
    try copyAndValidate(
      copy(
        profile,
        chords: profile.chords + [RemappingChord(sources: Set(sources), destination: destination)]
      )
    )
  }

  static func removingChord(from profile: RemappingProfile, chordID: UUID) throws
    -> RemappingProfile
  {
    guard profile.chords.contains(where: { $0.id == chordID }) else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format(
          "cli.mapping.chord_missing",
          "No chord exists with ID %@.",
          chordID.uuidString
        )
      )
    }
    return try copyAndValidate(copy(profile, chords: profile.chords.filter { $0.id != chordID }))
  }

  static func addingSequence(
    in profile: RemappingProfile,
    sources: [RemappingSource],
    windowMs: Double,
    destination: RemappingDestination
  ) throws -> RemappingProfile {
    try copyAndValidate(
      copy(
        profile,
        sequences: profile.sequences + [
          RemappingSequence(sources: sources, windowMs: windowMs, destination: destination)
        ]
      )
    )
  }

  static func removingSequence(from profile: RemappingProfile, sequenceID: UUID) throws
    -> RemappingProfile
  {
    guard profile.sequences.contains(where: { $0.id == sequenceID }) else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format(
          "cli.mapping.sequence_missing",
          "No sequence exists with ID %@.",
          sequenceID.uuidString
        )
      )
    }
    return try copyAndValidate(
      copy(profile, sequences: profile.sequences.filter { $0.id != sequenceID })
    )
  }

  static func creatingLayer(
    in profile: RemappingProfile,
    name: String,
    activator: RemappingSource,
    mode: RemappingLayerActivation
  ) throws -> RemappingProfile {
    try copyAndValidate(
      copy(
        profile,
        layers: profile.layers + [
          RemappingLayer(name: name, activationMode: mode, activator: activator)
        ]
      )
    )
  }

  static func deletingLayer(from profile: RemappingProfile, layerID: UUID) throws
    -> RemappingProfile
  {
    guard profile.layers.contains(where: { $0.id == layerID }) else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format(
          "cli.mapping.layer_missing",
          "No layer exists with ID %@.",
          layerID.uuidString
        )
      )
    }
    return try copyAndValidate(copy(profile, layers: profile.layers.filter { $0.id != layerID }))
  }

  private static func replacingLayer(
    _ profile: RemappingProfile,
    layerID: UUID,
    bindings: [RemappingBinding]? = nil
  ) throws -> RemappingProfile {
    guard let layerIndex = profile.layers.firstIndex(where: { $0.id == layerID }) else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format(
          "cli.mapping.layer_missing",
          "No layer exists with ID %@.",
          layerID.uuidString
        )
      )
    }
    var layers = profile.layers
    let old = layers[layerIndex]
    layers[layerIndex] = RemappingLayer(
      id: old.id,
      name: old.name,
      activationMode: old.activationMode,
      activator: old.activator,
      bindings: bindings ?? old.bindings,
      chords: old.chords,
      sequences: old.sequences
    )
    return try copyAndValidate(copy(profile, layers: layers))
  }

  static func bindingInLayer(
    in profile: RemappingProfile,
    layerID: UUID,
    source: RemappingSource,
    destination: RemappingDestination,
    options: MappingOptions
  ) throws -> RemappingProfile {
    let (axisTuning, turbo, longHold, doubleTap) = try resolvedBindingOptions(
      source: source,
      destination: destination,
      options: options
    )
    let binding = RemappingBinding(
      source: source,
      destination: destination,
      axisTuning: axisTuning,
      turbo: turbo,
      longHold: longHold,
      doubleTap: doubleTap
    )
    guard let layer = profile.layers.first(where: { $0.id == layerID }) else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format(
          "cli.mapping.layer_missing",
          "No layer exists with ID %@.",
          layerID.uuidString
        )
      )
    }
    let bindings = layer.bindings.filter { $0.source != source } + [binding]
    return try replacingLayer(profile, layerID: layerID, bindings: bindings)
  }

  static func unbindingInLayer(
    from profile: RemappingProfile,
    layerID: UUID,
    source: RemappingSource
  ) throws -> RemappingProfile {
    guard let layer = profile.layers.first(where: { $0.id == layerID }) else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format(
          "cli.mapping.layer_missing",
          "No layer exists with ID %@.",
          layerID.uuidString
        )
      )
    }
    let bindings = layer.bindings.filter { $0.source != source }
    return try replacingLayer(profile, layerID: layerID, bindings: bindings)
  }

  static func updating(_ profile: RemappingProfile, options: MappingOptions) throws
    -> RemappingProfile
  {
    let vendorID =
      try options["--vid"].map { try MappingSyntax.identifier($0, option: "--vid") }
      ?? profile.device.vendorID
    let productID =
      try options["--pid"].map { try MappingSyntax.identifier($0, option: "--pid") }
      ?? profile.device.productID
    let scope = try applicationScope(options, defaultValue: profile.applicationScope)
    let updated = RemappingProfile(
      id: profile.id,
      name: options["--name"] ?? profile.name,
      device: RemappingDeviceScope(vendorID: vendorID, productID: productID),
      applicationScope: scope,
      bindings: profile.bindings,
      chords: profile.chords,
      sequences: profile.sequences,
      layers: profile.layers
    )
    try updated.validate()
    return updated
  }

  static func applicationScope(
    _ options: MappingOptions,
    defaultValue: RemappingApplicationScope? = nil
  ) throws -> RemappingApplicationScope {
    let bundleID = options["--target-app"]
    let global = options.contains("--global")
    guard bundleID == nil || !global else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.scope_conflict",
          "Pass only one of --target-app or --global."
        )
      )
    }
    if let bundleID { return .application(bundleIdentifier: bundleID) }
    if global { return .global }
    guard let defaultValue else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text("cli.mapping.scope_required", "Pass one of --target-app or --global.")
      )
    }
    return defaultValue
  }

  private static func resolvedBindingOptions(
    source: RemappingSource,
    destination: RemappingDestination,
    options: MappingOptions
  ) throws -> (RemappingAxisTuning?, RemappingTurbo?, RemappingLongHold?, RemappingDoubleTap?) {
    (
      try tuning(source: source, options: options),
      try turbo(destination: destination, options: options), try longHold(options: options),
      try doubleTap(options: options)
    )
  }

  private static func tuning(source: RemappingSource, options: MappingOptions) throws
    -> RemappingAxisTuning?
  {
    let tuningOptions = [
      "--deadzone", "--gain", "--invert", "--response-curve", "--digital-threshold"
    ]
    let supplied = tuningOptions.contains(where: options.contains)
    let isAxis =
      switch source {
      case .axis, .axisDirection: true
      default: false
      }
    guard isAxis || !supplied else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.axis_options_source",
          "Axis options require an axis source."
        )
      )
    }
    guard isAxis else { return nil }
    return RemappingAxisTuning(
      deadzone: try number(options["--deadzone"], option: "--deadzone", fallback: 0.1),
      gain: try number(options["--gain"], option: "--gain", fallback: 1),
      inverted: options.contains("--invert"),
      responseCurve: try curve(options["--response-curve"]),
      digitalActivationThreshold: try number(
        options["--digital-threshold"],
        option: "--digital-threshold",
        fallback: 0.5
      )
    )
  }

  private static func turbo(destination: RemappingDestination, options: MappingOptions) throws
    -> RemappingTurbo?
  {
    let rate = options["--turbo-rate"]
    let duty = options["--turbo-duty"]
    guard rate != nil || duty != nil else { return nil }
    guard let rate, let duty else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.turbo_pair",
          "--turbo-rate and --turbo-duty must be supplied together."
        )
      )
    }
    guard destination.acceptsTurbo else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.turbo_unsupported",
          "Turbo is not supported for pointer movement or scrolling."
        )
      )
    }
    return RemappingTurbo(
      repeatRateHz: try MappingSyntax.finiteDouble(rate, option: "--turbo-rate"),
      dutyCycle: try MappingSyntax.finiteDouble(duty, option: "--turbo-duty")
    )
  }

  private static func longHold(options: MappingOptions) throws -> RemappingLongHold? {
    guard let raw = options["--long-hold"] else { return nil }
    let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(
      String.init
    )
    guard parts.count == 2 else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.long_hold_format",
          "--long-hold expects <ms>:<target>, e.g. --long-hold 500:key:b"
        )
      )
    }
    let duration = try MappingSyntax.finiteDouble(parts[0], option: "--long-hold duration")
    let destination = try MappingSyntax.destination(parts[1])
    return RemappingLongHold(durationMs: duration, destination: destination)
  }

  private static func doubleTap(options: MappingOptions) throws -> RemappingDoubleTap? {
    guard let raw = options["--double-tap"] else { return nil }
    let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(
      String.init
    )
    guard parts.count == 2 else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.double_tap_format",
          "--double-tap expects <ms>:<target>, e.g. --double-tap 300:key:c"
        )
      )
    }
    let window = try MappingSyntax.finiteDouble(parts[0], option: "--double-tap window")
    let destination = try MappingSyntax.destination(parts[1])
    return RemappingDoubleTap(windowMs: window, destination: destination)
  }

  private static func number(_ raw: String?, option: String, fallback: Double) throws -> Double {
    guard let raw else { return fallback }
    return try MappingSyntax.finiteDouble(raw, option: option)
  }

  private static func curve(_ raw: String?) throws -> RemappingResponseCurve {
    guard let raw else { return .linear }
    guard let value = RemappingResponseCurve(rawValue: raw) else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format("cli.mapping.curve_unknown", "Unknown response curve '%@'.", raw)
      )
    }
    return value
  }

  private static func copy(
    _ profile: RemappingProfile,
    bindings: [RemappingBinding]? = nil,
    chords: [RemappingChord]? = nil,
    sequences: [RemappingSequence]? = nil,
    layers: [RemappingLayer]? = nil
  ) -> RemappingProfile {
    RemappingProfile(
      schemaVersion: profile.schemaVersion,
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
      bindings: bindings ?? profile.bindings,
      chords: chords ?? profile.chords,
      sequences: sequences ?? profile.sequences,
      layers: layers ?? profile.layers
    )
  }

  private static func copyAndValidate(_ profile: RemappingProfile) throws -> RemappingProfile {
    try profile.validate()
    return profile
  }
}
