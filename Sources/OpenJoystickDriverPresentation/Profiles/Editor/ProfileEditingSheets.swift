#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileMetadataSheet: View {
    let profile: RemappingProfile
    let onSave: (RemappingProfile) -> Void
    @Environment(\.presentationMode)
    var presentationMode
    @State
    private var name: String
    @State
    private var vendorID: String
    @State
    private var productID: String
    @State
    private var scopeKind: ProfileScopeKind
    @State
    private var bundleIdentifier: String
    @State
    private var joyConPairEnabled: Bool
    @State
    private var joyConGyroSelection: RemappingJoyConGyroSelection
    @State
    private var errorMessage: String?

    init(profile: RemappingProfile, onSave: @escaping (RemappingProfile) -> Void) {
      self.profile = profile
      self.onSave = onSave
      _name = State(initialValue: profile.name)
      _vendorID = State(initialValue: ProfileIdentifierInput.formatted(profile.device.vendorID))
      _productID = State(initialValue: ProfileIdentifierInput.formatted(profile.device.productID))
      _scopeKind = State(initialValue: ProfileScopeKind(profile.applicationScope))
      let bundleIdentifier: String
      if case .application(let value) = profile.applicationScope {
        bundleIdentifier = value
      } else {
        bundleIdentifier = ""
      }
      _bundleIdentifier = State(initialValue: bundleIdentifier)
      _joyConPairEnabled = State(initialValue: profile.joyConPair != nil)
      _joyConGyroSelection = State(initialValue: profile.joyConPair?.gyroSelection ?? .right)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 15) {
        Text(OJDLocalized.string("profiles.details")).font(
          .headline.weight(.semibold)
        )
        TextField(OJDLocalized.string("common.profileName"), text: $name)
        HStack(spacing: 12) {
          TextField(
            OJDLocalized.string("profiles.vendorID"),
            text: $vendorID
          )
          TextField(
            OJDLocalized.string("profiles.productID"),
            text: $productID
          )
        }
        Text(
          OJDLocalized.string(
            "profiles.identifierHint"
          )
        ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        Picker(OJDLocalized.string("profiles.target"), selection: $scopeKind) {
          Text(OJDLocalized.string("profiles.targetGlobal")).tag(
            ProfileScopeKind.global
          )
          Text(OJDLocalized.string("profiles.targetApplication")).tag(
            ProfileScopeKind.application
          )
        }
        if scopeKind == .application {
          TextField(
            OJDLocalized.string("profiles.bundleIdentifier"),
            text: $bundleIdentifier
          )
        }
        Toggle(
          OJDLocalized.string("profiles.joyConPair"),
          isOn: $joyConPairEnabled
        )
        if joyConPairEnabled {
          Picker(
            OJDLocalized.string("profiles.joyConGyro"),
            selection: $joyConGyroSelection
          ) {
            Text(OJDLocalized.string("common.disabled")).tag(
              RemappingJoyConGyroSelection.disabled
            )
            Text(OJDLocalized.string("profiles.joyConLeft")).tag(
              RemappingJoyConGyroSelection.left
            )
            Text(OJDLocalized.string("profiles.joyConRight")).tag(
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
          Button(OJDLocalized.string("common.cancel")) { dismiss() }
          Button(OJDLocalized.string("common.apply")) { save() }
        }
      }.padding(28).frame(width: 440)
    }

    private func save() {
      guard let vendorID = ProfileIdentifierInput.parse(vendorID),
        let productID = ProfileIdentifierInput.parse(productID)
      else {
        errorMessage = OJDLocalized.string(
          "profiles.invalidIdentifiers"
        )
        return
      }
      let scope: RemappingApplicationScope
      switch scopeKind {
      case .global: scope = .global
      case .application: scope = .application(bundleIdentifier: bundleIdentifier)
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
        layers: profile.layers
      )
      do {
        try candidate.validate()
        onSave(candidate)
        dismiss()
      } catch { errorMessage = RuntimePresentation.userFacingError(error) }
    }

    func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

  struct BindingBehaviorSheet: View {
    let binding: RemappingBinding
    let onSave: SaveAction
    let showsAdditionalActions: Bool
    let capabilities: ControllerProfileCapabilities?
    @Environment(\.presentationMode)
    var presentationMode
    @State
    var additionalActions: [RemappingAction]
    @State
    var behavior: RemappingBindingBehavior
    @State
    var pulseDurationMs: Double
    @State
    var turboEnabled: Bool
    @State
    var turboRate: Double
    @State
    var turboDuty: Double
    @State
    var longHoldEnabled: Bool
    @State
    var longHoldDuration: Double
    @State
    var longHoldDestination: RemappingDestination
    @State
    var doubleTapEnabled: Bool
    @State
    var doubleTapWindow: Double
    @State
    var doubleTapDestination: RemappingDestination

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
      _doubleTapEnabled = State(initialValue: binding.doubleTap != nil)
      _doubleTapWindow = State(initialValue: binding.doubleTap?.windowMs ?? 300)
      _doubleTapDestination = State(
        initialValue: binding.doubleTap?.destination ?? .keyboard(key: .space, modifiers: [])
      )
    }
  }

#endif
