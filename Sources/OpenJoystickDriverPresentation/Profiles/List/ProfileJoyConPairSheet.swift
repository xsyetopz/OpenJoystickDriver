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
        Text(OJDLocalized.string("profiles.pairJoyCons"))
          .font(.headline.weight(.semibold))
        Text(profile.name).font(.caption).foregroundColor(.secondary)
        Picker(
          OJDLocalized.string("profiles.joyConLeft"),
          selection: $leftRuntimeIdentifier
        ) {
          ForEach(Self.leftDevices(devices), id: \.runtimeIdentifier) { device in
            Text(device.name + " · " + device.runtimeIdentifier).tag(device.runtimeIdentifier)
          }
        }
        Picker(
          OJDLocalized.string("profiles.joyConRight"),
          selection: $rightRuntimeIdentifier
        ) {
          ForEach(Self.rightDevices(devices), id: \.runtimeIdentifier) { device in
            Text(device.name + " · " + device.runtimeIdentifier).tag(device.runtimeIdentifier)
          }
        }
        Text(
          OJDLocalized.string(
            "profiles.joyConPairSessionHint"
          )
        ).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel")) { dismiss() }
          Button(OJDLocalized.string("profiles.pair")) {
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
      devices.filter { JoyConHalf(vendorID: $0.vendorID, productID: $0.productID) == .left }
    }

    private static func rightDevices(
      _ devices: [ApplicationServiceDeviceDescription]
    ) -> [ApplicationServiceDeviceDescription] {
      devices.filter { JoyConHalf(vendorID: $0.vendorID, productID: $0.productID) == .right }
    }
  }
#endif
