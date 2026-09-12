#if canImport(AppKit) && canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileOutputPolicyView: View {
    let policy: RemappingOutputPolicy
    let onChange: (RemappingOutputPolicy) -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        Picker(
          OJDLocalized.string("profiles.virtualOutput", fallback: "Virtual gamepad"),
          selection: Binding(
            get: { policy.virtualGamepad },
            set: { value in
              onChange(RemappingOutputPolicy(
                  virtualGamepad: value,
                  physicalInput: policy.physicalInput
              ))
            }
          )
        ) {
          Text(OJDLocalized.string("profiles.virtualDisabled", fallback: "Disabled"))
            .tag(RemappingVirtualGamepadPolicy.disabled)
          Text(OJDLocalized.string("profiles.virtualMapped", fallback: "Mapped controls only"))
            .tag(RemappingVirtualGamepadPolicy.mapped)
          Text(OJDLocalized.string(
            "profiles.virtualPassthrough", fallback: "Include unmapped controls"
          ))
            .tag(RemappingVirtualGamepadPolicy.passthrough)
        }
        Toggle(
          OJDLocalized.string(
            "profiles.exclusiveInput", fallback: "Require exclusive physical input"
          ),
          isOn: Binding(
            get: { policy.requiresExclusiveInput },
            set: { value in
              onChange(RemappingOutputPolicy(
                  virtualGamepad: policy.virtualGamepad,
                  physicalInput: value ? .exclusive : .shared
              ))
            }
          )
        ).disabled(policy.virtualGamepad != .disabled)
      }
    }

  }
#endif
