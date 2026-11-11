#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The sheet that edits the pointer speed of a profile.
  struct ProfilePointerSpeedSheet: View {
    /// What the controller has, which decides the drivers that can be saved.
    let capabilities: ControllerProfileCapabilities
    /// Reads the latest input state of the profile's controller, or nil when there is none.
    let liveState: () async -> ControllerState?
    /// Receives the pointer speed, or nil when it is off, when the person chooses Save.
    let onSave: (RemappingPointerSpeed?) throws -> Void
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode
    /// The pointer speed being edited.
    @State
    private var draft: ProfilePointerSpeedDraft
    /// The latest input state of the controller, or nil.
    @State
    private var state: ControllerState?
    /// The message of the failed validation, or nil.
    @State
    private var errorMessage: String?

    /// Creates the sheet on the current pointer speed.
    ///
    /// - Parameters:
    ///   - speed: The pointer speed to edit, or nil when the profile has none.
    ///   - capabilities: What the controller has.
    ///   - liveState: Reads the latest input state of the controller.
    ///   - onSave: Receives the validated pointer speed.
    init(
      speed: RemappingPointerSpeed?,
      capabilities: ControllerProfileCapabilities,
      liveState: @escaping () async -> ControllerState?,
      onSave: @escaping (RemappingPointerSpeed?) throws -> Void
    ) {
      self.capabilities = capabilities
      self.liveState = liveState
      self.onSave = onSave
      _draft = State(initialValue: ProfilePointerSpeedDraft(speed: speed))
    }

    /// The title, the fields, the current scale and the buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.large) {
        Text(label("title")).font(.headline)
        Toggle(label("enabled"), isOn: $draft.enabled)
        if draft.enabled {
          Picker(label("driver"), selection: $draft.driverType) {
            Text(label("driverTrigger")).tag(RemappingPointerSpeedDriver.Kind.trigger)
            Text(label("driverStickDepth")).tag(RemappingPointerSpeedDriver.Kind.stickDepth)
          }
          Picker(label("side"), selection: $draft.side) {
            Text(label("sideLeft")).tag(RemappingStickSource.left)
            Text(label("sideRight")).tag(RemappingStickSource.right)
          }
          field("minScale", $draft.minScale)
          field("maxScale", $draft.maxScale)
          Picker(OJDLocalized.string("ui.capture.responseCurve"), selection: $draft.curve) {
            ForEach(RemappingResponseCurve.allCases, id: \.self) { Text($0.label).tag($0) }
          }
          if let scale = liveScale {
            Text(OJDLocalized.formatted("ui.profiles.pointerSpeed.live", scale))
          }
        }
        if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("action.save")) { save() }
        }
      }.ojdSheet(.compact).task {
        while !Task.isCancelled {
          state = await liveState()
          try? await Task.sleep(nanoseconds: 200_000_000)
        }
      }
    }

    /// The scale the draft gives the latest input state, as text, or nil while either is missing.
    private var liveScale: String? {
      guard let state, let speed = try? draft.validatedSpeed(decimalSeparator: separator)
      else { return nil }
      return unsafe String(format: "%.2f", speed.scale(for: state))
    }

    /// The decimal separator the person types.
    private var separator: String { Locale.current.decimalSeparator ?? "." }

    /// Validates the draft and passes it to ``onSave``.
    ///
    /// A failure shows in ``errorMessage`` and keeps the sheet open.
    private func save() {
      do {
        let speed = try draft.validatedSpeed(decimalSeparator: separator)
        if let speed, !speed.isSupported(by: capabilities) {
          throw RemappingValidationError.unsupportedPointerSpeedDriver
        }
        try onSave(speed)
        presentationMode.wrappedValue.dismiss()
      } catch { errorMessage = RuntimePresentation.userFacingError(error) }
    }

    /// A labeled text field for the scale called `key`.
    private func field(_ key: String, _ value: Binding<String>) -> some View {
      VStack(alignment: .leading, spacing: OJDSpacing.xSmall) {
        Text(label(key))
        TextField(label(key), text: value).textFieldStyle(RoundedBorderTextFieldStyle())
      }
    }

    /// Returns the text of the pointer speed key called `key`.
    private func label(_ key: String) -> String {
      OJDLocalized.string("ui.profiles.pointerSpeed." + key)
    }
  }
#endif
