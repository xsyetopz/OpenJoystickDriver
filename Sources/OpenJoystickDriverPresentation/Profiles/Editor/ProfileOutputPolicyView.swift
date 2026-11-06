#if canImport(AppKit) && canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The pickers of the profile's output policy: the virtual output, and whether the profile takes
  /// the controller's input exclusively.
  struct ProfileOutputPolicyView: View {
    /// The policy being edited.
    let policy: RemappingOutputPolicy
    /// Receives the policy when the person changes it.
    let onChange: (RemappingOutputPolicy) -> Void

    /// The virtual output picker and the exclusive input toggle.
    var body: some View {
      Group {
        Picker(
          OJDLocalized.string("ui.profiles.virtualOutput"),
          selection: Binding(
            get: { policy.virtualGamepad },
            set: { value in onChange(Self.policy(selecting: value, from: policy)) }
          )
        ) {
          Text(OJDLocalized.string("ui.profiles.virtualDisabled")).tag(
            RemappingVirtualGamepadPolicy.disabled
          )
          Text(OJDLocalized.string("ui.profiles.virtualMapped")).tag(
            RemappingVirtualGamepadPolicy.mapped
          )
          Text(
            OJDLocalized.string(
              "ui.profiles.virtualPassthrough"
            )
          ).tag(RemappingVirtualGamepadPolicy.passthrough)
        }
        Toggle(
          OJDLocalized.string(
            "ui.profiles.exclusiveInput"
          ),
          isOn: Binding(
            get: { policy.requiresExclusiveInput },
            set: { value in
              onChange(
                RemappingOutputPolicy(
                  virtualGamepad: policy.virtualGamepad,
                  physicalInput: value ? .exclusive : .shared
                )
              )
            }
          )
        ).disabled(policy.virtualGamepad != .disabled)
      }
    }

    /// Returns the policy after the virtual output changes.
    ///
    /// The exclusive input toggle applies only while the virtual output is disabled; with any other
    /// virtual output it is off and shows exclusive input as on, because a virtual output always
    /// takes exclusive input. Any other virtual output therefore returns the physical input to the
    /// default of `ojd profile create`, shared, so an earlier choice that the toggle does not show
    /// is not kept.
    ///
    /// - Parameters:
    ///   - virtualGamepad: The virtual output the person chose.
    ///   - policy: The policy before the change.
    /// - Returns: The policy after the virtual output changes.
    static func policy(
      selecting virtualGamepad: RemappingVirtualGamepadPolicy,
      from policy: RemappingOutputPolicy
    ) -> RemappingOutputPolicy {
      RemappingOutputPolicy(
        virtualGamepad: virtualGamepad,
        physicalInput: virtualGamepad == .disabled ? policy.physicalInput : .shared
      )
    }
  }
#endif
