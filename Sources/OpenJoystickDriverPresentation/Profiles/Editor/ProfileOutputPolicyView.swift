#if canImport(AppKit) && canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileOutputPolicyView: View {
    let policy: RemappingOutputPolicy
    let onChange: (RemappingOutputPolicy) -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        Picker(
          OJDLocalized.string("profiles.virtualOutput"),
          selection: Binding(
            get: { policy.virtualGamepad },
            set: { value in
              onChange(
                RemappingOutputPolicy(virtualGamepad: value, physicalInput: policy.physicalInput)
              )
            }
          )
        ) {
          Text(OJDLocalized.string("profiles.virtualDisabled")).tag(
            RemappingVirtualGamepadPolicy.disabled
          )
          Text(OJDLocalized.string("profiles.virtualMapped")).tag(
            RemappingVirtualGamepadPolicy.mapped
          )
          Text(
            OJDLocalized.string(
              "profiles.virtualPassthrough"
            )
          ).tag(RemappingVirtualGamepadPolicy.passthrough)
        }
        Toggle(
          OJDLocalized.string(
            "profiles.exclusiveInput"
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

  }
#endif
