import OpenJoystickDriverKit

extension ControllerDetailRow {
  /// Returns the hidden rows of the controller detail that hold a value other than their default.
  ///
  /// The default of the virtual gamepad kind is no override; the default of the stick dead zone is
  /// no user value, as ``StickDeadzoneSetting/canReset`` reads it.
  ///
  /// - Parameters:
  ///   - virtualGamepadOverride: The kind the user set for the controller, or nil.
  ///   - stickDeadzone: The stick dead zone of the controller's model, or nil while the record is
  ///     not loaded.
  /// - Returns: The hidden rows that hold a user value.
  static func changedHiddenRows(
    virtualGamepadOverride: VirtualHIDProfileID?,
    stickDeadzone: StickDeadzoneSetting?
  ) -> [ControllerDetailRow] {
    var rows: [ControllerDetailRow] = []
    if virtualGamepadOverride != nil { rows.append(.virtualGamepadKind) }
    if stickDeadzone?.canReset == true { rows.append(.stickDeadzone) }
    return rows
  }
}

extension ProfilesRow {
  /// Returns the hidden rows of the profile editor whose profile values differ from the defaults
  /// of a new profile.
  ///
  /// - Parameter profile: The profile.
  /// - Returns: The hidden rows that hold a non-default value, each once.
  static func changedHiddenRows(in profile: RemappingProfile) -> [ProfilesRow] {
    let scopes =
      [(profile.bindings, profile.chords, profile.sequences)]
      + profile.layers.map { ($0.bindings, $0.chords, $0.sequences) }
    let bindings = scopes.flatMap(\.0)
    var sources = scopes.flatMap(\.0).map(\.source)
    sources += scopes.flatMap(\.1).flatMap(\.sources)
    sources += scopes.flatMap(\.2).flatMap(\.sources)
    sources += profile.layers.map(\.activator)

    var rows: [ProfilesRow] = []
    if profile.outputPolicy != .systemInput { rows.append(.outputPolicy) }
    if bindings.contains(where: { $0.axisTuning.map { $0 != .default } ?? false }) {
      rows.append(.axisAdjustment)
    }
    if !profile.stickMappings.isEmpty || !profile.triggerMappings.isEmpty
      || !profile.touchMappings.isEmpty
    {
      rows.append(.analogModes)
    }
    if profile.pointerSpeed != nil { rows.append(.pointerSpeed) }
    if profile.motionTuning != .default || profile.gyroOutput != .default
      || profile.layers.contains(where: { $0.motionTuning != nil })
    {
      rows.append(.motion)
    }
    if sources.contains(where: \.isRegion) { rows.append(.regions) }
    return rows
  }
}

extension RemappingSource {
  /// Whether the source is a stick region, a trigger band or a touch-surface area.
  fileprivate var isRegion: Bool {
    switch self {
    case .stickRegion, .triggerBand, .touchArea: return true
    default: return false
    }
  }
}
