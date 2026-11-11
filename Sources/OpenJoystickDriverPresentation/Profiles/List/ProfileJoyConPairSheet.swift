#if canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The sheet that pairs two connected Joy-Con controllers for a profile: a picker of the left
  /// and one of the right half.
  struct ProfileJoyConPairSheet: View {
    /// The profile to pair the Joy-Con controllers for.
    let profile: RemappingProfile
    /// The connected controllers, of which the pickers list the Joy-Con halves.
    let devices: [ApplicationServiceDeviceDescription]
    /// Receives the session tokens of the left and the right half when the person chooses Pair.
    let onPair: (ControllerSessionToken, ControllerSessionToken) -> Void
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode
    /// The session token of the left half, or nil when none is connected.
    @State
    private var leftSessionToken: ControllerSessionToken?
    /// The session token of the right half, or nil when none is connected.
    @State
    private var rightSessionToken: ControllerSessionToken?

    /// Creates the sheet with the first left and the first right half selected.
    ///
    /// - Parameters:
    ///   - profile: The profile to pair the Joy-Con controllers for.
    ///   - devices: The connected controllers.
    ///   - onPair: Receives the session tokens of the left and the right half.
    init(
      profile: RemappingProfile,
      devices: [ApplicationServiceDeviceDescription],
      onPair: @escaping (ControllerSessionToken, ControllerSessionToken) -> Void
    ) {
      self.profile = profile
      self.devices = devices
      self.onPair = onPair
      _leftSessionToken = State(initialValue: Self.leftDevices(devices).first?.sessionToken)
      _rightSessionToken = State(initialValue: Self.rightDevices(devices).first?.sessionToken)
    }

    /// The sheet's title, the two pickers, the hint about sessions, and the Cancel and Pair
    /// buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(OJDLocalized.string("ui.profiles.pairJoyCons"))
          .font(.headline.weight(.semibold))
        Text(profile.name).font(.caption).foregroundColor(.secondary)
        Picker(
          OJDLocalized.string("ui.profiles.joyConLeft"),
          selection: $leftSessionToken
        ) {
          ForEach(Self.leftDevices(devices), id: \.sessionToken) { device in
            Text(device.name + " · " + device.sessionToken.rawValue)
              .tag(Optional(device.sessionToken))
          }
        }
        Picker(
          OJDLocalized.string("ui.profiles.joyConRight"),
          selection: $rightSessionToken
        ) {
          ForEach(Self.rightDevices(devices), id: \.sessionToken) { device in
            Text(device.name + " · " + device.sessionToken.rawValue)
              .tag(Optional(device.sessionToken))
          }
        }
        Text(
          OJDLocalized.string(
            "ui.profiles.joyConPairSessionHint"
          )
        ).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) { dismiss() }
          Button(OJDLocalized.string("ui.profiles.pair")) {
            if let leftSessionToken, let rightSessionToken {
              onPair(leftSessionToken, rightSessionToken)
            }
            dismiss()
          }.disabled(leftSessionToken == nil || rightSessionToken == nil)
        }
      }.padding(28).frame(width: 480)
    }

    /// Dismisses the sheet.
    private func dismiss() { presentationMode.wrappedValue.dismiss() }

    /// Returns the left Joy-Con halves among `devices`.
    private static func leftDevices(
      _ devices: [ApplicationServiceDeviceDescription]
    ) -> [ApplicationServiceDeviceDescription] {
      devices.filter { JoyConHalf(vendorID: $0.vendorID, productID: $0.productID) == .left }
    }

    /// Returns the right Joy-Con halves among `devices`.
    private static func rightDevices(
      _ devices: [ApplicationServiceDeviceDescription]
    ) -> [ApplicationServiceDeviceDescription] {
      devices.filter { JoyConHalf(vendorID: $0.vendorID, productID: $0.productID) == .right }
    }
  }
#endif
