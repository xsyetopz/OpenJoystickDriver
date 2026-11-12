import OpenJoystickDriverKit

/// Which virtual gamepad kinds the Virtual HID profile pop-up offers for a controller, and what it
/// says about the kind in force.
enum VirtualHIDProfileKinds {
  /// Returns the kinds the service accepts as an override for `device`: those that profile
  /// selection takes for the controller's declared controls.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The kinds the service accepts as an override for `device`.
  static func accepted(for device: ApplicationServiceDeviceDescription) -> [VirtualHIDProfileID] {
    VirtualHIDProfileID.allCases.filter { kind in
      var input = ServingInput(serving: device, override: kind)
      input.outputEnabled = true
      return ServingPolicy.decision(input).selection?.source == .override
    }
  }

  /// Returns the kinds the pop-up lists: those the service accepts, and the stored override when
  /// the controller cannot use it, so that the pop-up can show what is stored.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The kinds the pop-up lists.
  static func offered(for device: ApplicationServiceDeviceDescription) -> [VirtualHIDProfileID] {
    let accepted = accepted(for: device)
    guard let stored = device.virtualHIDProfile?.override, !accepted.contains(stored) else {
      return accepted
    }
    return accepted + [stored]
  }

  /// Returns the title of a kind's option in the pop-up: the phrase for what reads the kind, and in
  /// Advanced the identifier beside it.
  ///
  /// - Parameters:
  ///   - kind: The kind.
  ///   - level: The interface level.
  /// - Returns: The title of the option.
  static func optionTitle(for kind: VirtualHIDProfileID, level: InterfaceLevel) -> String {
    let phrase = OJDLocalized.string(phraseKey(for: kind))
    guard level == .advanced else { return phrase }
    return OJDLocalized.formatted("ui.virtualProfile.kind.withIdentifier", phrase, kind.rawValue)
  }

  private static func phraseKey(for kind: VirtualHIDProfileID) -> String {
    switch kind {
    case .sdlCompatible: return "ui.virtualProfile.kind.sdlCompatible"
    case .gameControllerCompatible:
      return "platform.macos.ui.virtualProfile.kind.gameControllerCompatible"
    case .generic: return "ui.virtualProfile.kind.generic"
    }
  }

  /// Returns the line that names the kind in force and the stored kind when they differ; nil when
  /// they are the same or nothing is stored.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The line that names the kind in force and the stored kind, or nil.
  static func inForceText(for device: ApplicationServiceDeviceDescription) -> String? {
    guard let status = device.virtualHIDProfile, let stored = status.override,
      status.profile != stored
    else { return nil }
    return OJDLocalized.formatted(
      "ui.virtualProfile.inForce",
      status.profile?.identity.productName ?? OJDLocalized.string("ui.virtualProfile.none"),
      stored.identity.productName
    )
  }
}
