#if canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileJoyConPairSheet: View {
    let profile: RemappingProfile
    let devices: [ApplicationServiceDeviceDescription]
    let onPair: (String, String) -> Void
    @Environment(\.presentationMode)
    private var presentationMode
    @State
    private var leftRuntimeIdentifier: String
    @State
    private var rightRuntimeIdentifier: String

    init(
      profile: RemappingProfile,
      devices: [ApplicationServiceDeviceDescription],
      onPair: @escaping (String, String) -> Void
    ) {
      self.profile = profile
      self.devices = devices
      self.onPair = onPair
      _leftRuntimeIdentifier = State(
        initialValue: Self.leftDevices(devices).first?.runtimeIdentifier ?? ""
      )
      _rightRuntimeIdentifier = State(
        initialValue: Self.rightDevices(devices).first?.runtimeIdentifier ?? ""
      )
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(OJDLocalized.string("profiles.pairJoyCons", fallback: "Pair connected Joy-Cons..."))
          .font(.headline.weight(.semibold))
        Text(profile.name).font(.caption).foregroundColor(.secondary)
        Picker(
          OJDLocalized.string("profiles.joyConLeft", fallback: "Left Joy-Con"),
          selection: $leftRuntimeIdentifier
        ) {
          ForEach(Self.leftDevices(devices), id: \.runtimeIdentifier) { device in
            Text(device.name + " · " + device.runtimeIdentifier).tag(device.runtimeIdentifier)
          }
        }
        Picker(
          OJDLocalized.string("profiles.joyConRight", fallback: "Right Joy-Con"),
          selection: $rightRuntimeIdentifier
        ) {
          ForEach(Self.rightDevices(devices), id: \.runtimeIdentifier) { device in
            Text(device.name + " · " + device.runtimeIdentifier).tag(device.runtimeIdentifier)
          }
        }
        Text(
          OJDLocalized.string(
            "profiles.joyConPairSessionHint",
            fallback: "Pairing uses these exact controllers for the current app session."
          )
        ).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel", fallback: "Cancel")) { dismiss() }
          Button(OJDLocalized.string("profiles.pair", fallback: "Pair")) {
            onPair(leftRuntimeIdentifier, rightRuntimeIdentifier)
            dismiss()
          }.disabled(leftRuntimeIdentifier.isEmpty || rightRuntimeIdentifier.isEmpty)
        }
      }.padding(28).frame(width: 480)
    }

    private func dismiss() { presentationMode.wrappedValue.dismiss() }

    private static func leftDevices(
      _ devices: [ApplicationServiceDeviceDescription]
    ) -> [ApplicationServiceDeviceDescription] {
      devices.filter { $0.vendorID == 0x057E && $0.productID == 0x2006 }
    }

    private static func rightDevices(
      _ devices: [ApplicationServiceDeviceDescription]
    ) -> [ApplicationServiceDeviceDescription] {
      devices.filter { $0.vendorID == 0x057E && $0.productID == 0x2007 }
    }
  }
#endif
