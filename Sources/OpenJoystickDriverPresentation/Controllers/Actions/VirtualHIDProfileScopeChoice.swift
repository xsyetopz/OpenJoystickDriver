import OpenJoystickDriverKit

/// Whose virtual HID profile an override changes, as `ojd virtual set` and `reset` choose it
/// with `--unit`: every controller of the model, or only the one controller by its unit ID.
enum VirtualHIDProfileScopeChoice: Hashable, CaseIterable {
  /// Every controller of the model.
  case model
  /// Only the one controller, by its unit ID.
  case unit

  /// The scope the service stores the override in.
  var scope: VirtualHIDProfileOverrideScope {
    switch self {
    case .model: .model
    case .unit: .unit
    }
  }

  /// The localization key of the choice's title.
  var titleKey: String {
    switch self {
    case .model: "ui.controllers.virtual.scope.model"
    case .unit: "ui.controllers.virtual.scope.unit"
    }
  }

  /// Creates the choice of the service's `scope`.
  ///
  /// - Parameter scope: The scope of an override.
  init(_ scope: VirtualHIDProfileOverrideScope) {
    self = scope == .unit ? .unit : .model
  }

  /// Returns the choices for `device`.
  ///
  /// The unit scope needs a unit ID, which the service refuses to resolve for a controller that
  /// reports no location.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The choices for `device`.
  static func offered(for device: ApplicationServiceDeviceDescription) -> [Self] {
    device.portKey == nil ? [.model] : [.model, .unit]
  }

  /// Returns the scope of the stored override when one exists, else the model.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The scope of the stored override when one exists, else the model.
  static func initial(for device: ApplicationServiceDeviceDescription) -> Self {
    guard device.portKey != nil, let stored = device.virtualHIDProfile?.overrideScope else {
      return .model
    }
    return Self(stored)
  }
}

/// What choosing a profile in a scope does, given the override the controller reports.
///
/// The report names only the override in effect, which is its unit's when one exists, else its
/// model's.
enum VirtualHIDProfileOverrideDecision: Equatable {
  /// The scope already holds this choice.
  case unchanged
  /// Store the profile in the scope, or clear the scope's override for Automatic.
  case send
  /// Automatic in a scope that holds no override: the override in effect belongs to the other
  /// scope, and clearing this scope would change nothing.
  case otherScopeHolds(VirtualHIDProfileScopeChoice)

  /// Returns what choosing `profile` in `scope` does for `device`.
  ///
  /// - Parameters:
  ///   - profile: The profile chosen, or nil for Automatic.
  ///   - scope: The scope the person chose.
  ///   - device: The controller.
  /// - Returns: What choosing `profile` in `scope` does for `device`.
  static func decide(
    profile: VirtualHIDProfileID?,
    scope: VirtualHIDProfileScopeChoice,
    for device: ApplicationServiceDeviceDescription
  ) -> Self {
    guard let effective = device.virtualHIDProfile?.override else {
      return profile == nil ? .unchanged : .send
    }
    let holder = currentScope(for: device) ?? .model
    guard let profile else { return holder == scope ? .send : .otherScopeHolds(holder) }
    return profile == effective && holder == scope ? .unchanged : .send
  }

  /// Returns the scope of the override in effect; nil when the controller selects automatically.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The scope of the override in effect; nil when the controller selects automatically.
  static func currentScope(
    for device: ApplicationServiceDeviceDescription
  ) -> VirtualHIDProfileScopeChoice? {
    guard let status = device.virtualHIDProfile, status.override != nil else { return nil }
    return VirtualHIDProfileScopeChoice(status.overrideScope ?? .model)
  }
}
