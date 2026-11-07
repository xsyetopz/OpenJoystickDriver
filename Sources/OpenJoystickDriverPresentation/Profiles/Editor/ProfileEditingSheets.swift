#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The sheet that edits the details of a profile: name, vendor and product ID, target app and
  /// Joy-Con pair.
  struct ProfileMetadataSheet: View {
    /// The profile being edited.
    let profile: RemappingProfile
    /// Receives the edited profile when the person chooses Apply.
    let onSave: (RemappingProfile) -> Void
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    var presentationMode
    /// The name of the profile.
    @State
    private var name: String
    /// The vendor ID, as typed.
    @State
    private var vendorID: String
    /// The product ID, as typed.
    @State
    private var productID: String
    /// Whether the profile applies to every app or to one app.
    @State
    private var scopeKind: ProfileScopeKind
    /// The identifier of the app when the profile applies to one app.
    @State
    private var appID: String
    /// Whether the profile pairs two Joy-Con controllers.
    @State
    private var joyConPairEnabled: Bool
    /// The Joy-Con half whose gyro the pair uses, or none.
    @State
    private var joyConGyroSelection: RemappingJoyConGyroSelection
    /// The message of the failed validation, or nil.
    @State
    private var errorMessage: String?

    /// Creates the sheet on the details of `profile`.
    ///
    /// - Parameters:
    ///   - profile: The profile to edit.
    ///   - onSave: Receives the edited profile.
    init(profile: RemappingProfile, onSave: @escaping (RemappingProfile) -> Void) {
      self.profile = profile
      self.onSave = onSave
      _name = State(initialValue: profile.name)
      _vendorID = State(initialValue: ProfileIdentifierInput.formatted(profile.device.vendorID))
      _productID = State(initialValue: ProfileIdentifierInput.formatted(profile.device.productID))
      _scopeKind = State(initialValue: ProfileScopeKind(profile.applicationScope))
      let appID: String
      if case .application(let value) = profile.applicationScope {
        appID = value
      } else {
        appID = ""
      }
      _appID = State(initialValue: appID)
      _joyConPairEnabled = State(initialValue: profile.joyConPair != nil)
      _joyConGyroSelection = State(initialValue: profile.joyConPair?.gyroSelection ?? .right)
    }

    /// The details form and its Cancel and Apply buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: 15) {
        Text(OJDLocalized.string("ui.profiles.details")).font(
          .headline.weight(.semibold)
        )
        TextField(OJDLocalized.string("term.profileName"), text: $name)
        HStack(spacing: 12) {
          TextField(
            OJDLocalized.string("ui.profiles.vendorID"),
            text: $vendorID
          )
          TextField(
            OJDLocalized.string("ui.profiles.productID"),
            text: $productID
          )
        }
        Text(
          OJDLocalized.string(
            "ui.profiles.identifierHint"
          )
        ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        Picker(OJDLocalized.string("ui.profiles.target"), selection: $scopeKind) {
          Text(OJDLocalized.string("ui.profiles.targetGlobal")).tag(
            ProfileScopeKind.global
          )
          Text(OJDLocalized.string("ui.profiles.targetApplication")).tag(
            ProfileScopeKind.application
          )
        }
        if scopeKind == .application {
          TextField(
            OJDLocalized.string("ui.profiles.appID"),
            text: $appID
          )
        }
        Toggle(
          OJDLocalized.string("ui.profiles.joyConPair"),
          isOn: $joyConPairEnabled
        )
        if joyConPairEnabled {
          Picker(
            OJDLocalized.string("ui.profiles.joyConGyro"),
            selection: $joyConGyroSelection
          ) {
            Text(OJDLocalized.string("status.disabled")).tag(
              RemappingJoyConGyroSelection.disabled
            )
            Text(OJDLocalized.string("ui.profiles.joyConLeft")).tag(
              RemappingJoyConGyroSelection.left
            )
            Text(OJDLocalized.string("ui.profiles.joyConRight")).tag(
              RemappingJoyConGyroSelection.right
            )
          }
        }
        if let errorMessage {
          Text(errorMessage).font(.caption).foregroundColor(Color(NSColor.systemRed)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) { dismiss() }
          Button(OJDLocalized.string("action.apply")) { save() }
        }
      }.padding(28).frame(width: 440)
    }

    /// Validates the fields and passes the edited profile to ``onSave``.
    ///
    /// A failure shows in ``errorMessage`` and keeps the sheet open.
    private func save() {
      guard let vendorID = ProfileIdentifierInput.parse(vendorID),
        let productID = ProfileIdentifierInput.parse(productID)
      else {
        errorMessage = OJDLocalized.string(
          "ui.profiles.invalidIdentifiers"
        )
        return
      }
      let scope: RemappingApplicationScope
      switch scopeKind {
      case .global: scope = .global
      case .application: scope = .application(appID: appID)
      }
      let candidate = RemappingProfile(
        id: profile.id,
        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
        device: RemappingDeviceScope(vendorID: vendorID, productID: productID),
        applicationScope: scope,
        outputPolicy: profile.outputPolicy,
        motionTuning: profile.motionTuning,
        gyroOutput: profile.gyroOutput,
        joyConPair: joyConPairEnabled
          ? RemappingJoyConPairSettings(gyroSelection: joyConGyroSelection) : nil,
        stickMappings: profile.stickMappings,
        triggerMappings: profile.triggerMappings,
        touchMappings: profile.touchMappings,
        bindings: profile.bindings,
        chords: profile.chords,
        sequences: profile.sequences,
        layers: profile.layers,
        macros: profile.macros
      )
      do {
        try candidate.validate()
        onSave(candidate)
        dismiss()
      } catch { errorMessage = RuntimePresentation.userFacingError(error) }
    }

    /// Dismisses the sheet.
    func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

  /// The sheet that edits how an assignment acts: its behavior, turbo, long hold, tap counts and
  /// additional actions.
  struct BindingBehaviorSheet: View {
    /// The assignment being edited.
    let binding: RemappingBinding
    /// Receives the behavior settings when the person chooses Apply.
    let onSave: SaveAction
    /// Whether the sheet shows the additional actions.
    let showsAdditionalActions: Bool
    /// What the controller has, or nil when it is not known.
    let capabilities: ControllerProfileCapabilities?
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    var presentationMode
    /// The additional actions.
    @State
    var additionalActions: [RemappingAction]
    /// The behavior.
    @State
    var behavior: RemappingBindingBehavior
    /// The pulse duration in milliseconds.
    @State
    var pulseDurationMs: Double
    /// Whether turbo is on.
    @State
    var turboEnabled: Bool
    /// The turbo repeat rate in hertz.
    @State
    var turboRate: Double
    /// The turbo duty cycle.
    @State
    var turboDuty: Double
    /// Whether long hold is on.
    @State
    var longHoldEnabled: Bool
    /// The long hold duration in milliseconds.
    @State
    var longHoldDuration: Double
    /// The destination of the long hold.
    @State
    var longHoldDestination: RemappingDestination
    /// The turbo delay before the first repeat in milliseconds.
    @State
    var turboDelay: Double
    /// Whether turbo stops after a number of repeats.
    @State
    var turboLimitEnabled: Bool
    /// The number of repeats after which turbo stops.
    @State
    var turboMax: Double
    /// The tap-count entries.
    @State
    var multiTapEntries: [RemappingMultiTap]

    /// Creates the sheet on the settings of `binding`.
    ///
    /// Turbo starts at 12 Hz with a duty cycle of 0.5, a long hold at 500 ms and a new tap-count
    /// entry at 300 ms, each with the Space key as its destination.
    ///
    /// - Parameters:
    ///   - binding: The assignment to edit.
    ///   - showsAdditionalActions: Whether the sheet shows the additional actions.
    ///   - capabilities: What the controller has, or nil when it is not known.
    ///   - onSave: Receives the behavior settings.
    init(
      binding: RemappingBinding,
      showsAdditionalActions: Bool = true,
      capabilities: ControllerProfileCapabilities? = nil,
      onSave: @escaping SaveAction
    ) {
      self.binding = binding
      self.onSave = onSave
      self.showsAdditionalActions = showsAdditionalActions
      self.capabilities = capabilities
      _additionalActions = State(initialValue: binding.additionalActions)
      _behavior = State(initialValue: binding.behavior)
      _pulseDurationMs = State(initialValue: binding.pulseDurationMs)
      _turboEnabled = State(initialValue: binding.turbo != nil)
      _turboRate = State(initialValue: binding.turbo?.repeatRateHz ?? 12)
      _turboDuty = State(initialValue: binding.turbo?.dutyCycle ?? 0.5)
      _longHoldEnabled = State(initialValue: binding.longHold != nil)
      _longHoldDuration = State(initialValue: binding.longHold?.durationMs ?? 500)
      _longHoldDestination = State(
        initialValue: binding.longHold?.destination ?? .keyboard(key: .space, modifiers: [])
      )
      _turboDelay = State(initialValue: binding.turbo?.initialDelayMs ?? 0)
      _turboLimitEnabled = State(initialValue: binding.turbo?.maxRepeats != nil)
      _turboMax = State(initialValue: Double(binding.turbo?.maxRepeats ?? 10))
      _multiTapEntries = State(initialValue: binding.multiTap)
    }
  }

#endif
