#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileMetadataSheet: View {
    let profile: RemappingProfile
    let onSave: (RemappingProfile) -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var name: String
    @State private var vendorID: String
    @State private var productID: String
    @State private var scopeKind: ProfileScopeKind
    @State private var bundleIdentifier: String
    @State private var errorMessage: String?

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
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 15) {
        Text(OJDLocalized.string("profiles.details", fallback: "Profile details")).font(
          .headline.weight(.semibold)
        )
        TextField(OJDLocalized.string("common.profileName", fallback: "Profile name"), text: $name)
        HStack(spacing: 12) {
          TextField(
            OJDLocalized.string("profiles.vendorID", fallback: "Vendor ID"),
            text: $vendorID
          )
          TextField(
            OJDLocalized.string("profiles.productID", fallback: "Product ID"),
            text: $productID
          )
        }
        Text(
          OJDLocalized.string(
            "profiles.identifierHint",
            fallback: "Use decimal or 0x-prefixed hexadecimal identifiers."
          )
        ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        Picker(OJDLocalized.string("profiles.target", fallback: "Target"), selection: $scopeKind) {
          Text(OJDLocalized.string("profiles.targetGlobal", fallback: "All applications")).tag(
            ProfileScopeKind.global
          )
          Text(OJDLocalized.string("profiles.targetApplication", fallback: "One application")).tag(
            ProfileScopeKind.application
          )
        }
        if scopeKind == .application {
          TextField(
            OJDLocalized.string("profiles.bundleIdentifier", fallback: "Bundle identifier"),
            text: $bundleIdentifier
          )
        }
        if let errorMessage {
          Text(errorMessage).font(.caption).foregroundColor(Color(NSColor.systemRed)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel", fallback: "Cancel")) { dismiss() }
          Button(OJDLocalized.string("common.apply", fallback: "Apply")) { save() }
        }
      }.padding(28).frame(width: 440)
    }

    private func save() {
      guard let vendorID = ProfileIdentifierInput.parse(vendorID),
        let productID = ProfileIdentifierInput.parse(productID)
      else {
        errorMessage = OJDLocalized.string(
          "profiles.invalidIdentifiers",
          fallback: "Enter valid 16-bit vendor and product identifiers."
        )
        return
      }
      let scope: RemappingApplicationScope
      switch scopeKind {
      case .global: scope = .global
      case .application: scope = .application(bundleIdentifier: bundleIdentifier)
      }
      let candidate = RemappingProfile(
        schemaVersion: profile.schemaVersion,
        id: profile.id,
        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
        device: RemappingDeviceScope(vendorID: vendorID, productID: productID),
        applicationScope: scope,
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

    private func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

  struct BindingBehaviorSheet: View {
    let binding: RemappingBinding
    let onSave: (RemappingTurbo?, RemappingLongHold?, RemappingDoubleTap?) -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var turboEnabled: Bool
    @State private var turboRate: Double
    @State private var turboDuty: Double
    @State private var longHoldEnabled: Bool
    @State private var longHoldDuration: Double
    @State private var longHoldDestination: RemappingDestination
    @State private var doubleTapEnabled: Bool
    @State private var doubleTapWindow: Double
    @State private var doubleTapDestination: RemappingDestination

    init(
      binding: RemappingBinding,
      onSave: @escaping (RemappingTurbo?, RemappingLongHold?, RemappingDoubleTap?) -> Void
    ) {
      self.binding = binding
      self.onSave = onSave
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

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(OJDLocalized.string("profiles.bindingBehavior", fallback: "Assignment behavior")).font(
          .headline.weight(.semibold)
        )
        Toggle(OJDLocalized.string("profiles.turbo", fallback: "Turbo"), isOn: $turboEnabled)
          .disabled(!binding.destination.acceptsTurbo || longHoldEnabled || doubleTapEnabled)
        if turboEnabled {
          valueSlider(
            title: OJDLocalized.string("profiles.turboRate", fallback: "Repeat rate"),
            value: $turboRate,
            range: RemappingTurbo.repeatRateHzRange,
            format: "%.0f Hz"
          )
          valueSlider(
            title: OJDLocalized.string("profiles.turboDuty", fallback: "Duty cycle"),
            value: $turboDuty,
            range: RemappingTurbo.dutyCycleRange,
            format: "%.0f%%",
            multiplier: 100
          )
        }
        Divider()
        Toggle(
          OJDLocalized.string("profiles.longHold", fallback: "Long hold"),
          isOn: $longHoldEnabled
        ).disabled(!supportsActivation || turboEnabled)
        if longHoldEnabled {
          valueSlider(
            title: OJDLocalized.string("profiles.holdDuration", fallback: "Hold duration"),
            value: $longHoldDuration,
            range: RemappingLongHold.durationRange,
            format: "%.0f ms"
          )
          destinationPicker(selection: $longHoldDestination)
        }
        Toggle(
          OJDLocalized.string("profiles.doubleTap", fallback: "Double tap"),
          isOn: $doubleTapEnabled
        ).disabled(!supportsActivation || turboEnabled)
        if doubleTapEnabled {
          valueSlider(
            title: OJDLocalized.string("profiles.tapWindow", fallback: "Tap window"),
            value: $doubleTapWindow,
            range: RemappingDoubleTap.windowRange,
            format: "%.0f ms"
          )
          destinationPicker(selection: $doubleTapDestination)
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel", fallback: "Cancel")) { dismiss() }
          Button(OJDLocalized.string("common.apply", fallback: "Apply")) {
            onSave(
              turboEnabled ? RemappingTurbo(repeatRateHz: turboRate, dutyCycle: turboDuty) : nil,
              longHoldEnabled
                ? RemappingLongHold(durationMs: longHoldDuration, destination: longHoldDestination)
                : nil,
              doubleTapEnabled
                ? RemappingDoubleTap(windowMs: doubleTapWindow, destination: doubleTapDestination)
                : nil
            )
            dismiss()
          }
        }
      }.padding(28).frame(width: 470)
    }

    private var supportsActivation: Bool {
      switch binding.source {
      case .button, .dpad: return !binding.destination.isContinuous
      case .axis, .axisDirection: return false
      }
    }

    private func valueSlider(
      title: String,
      value: Binding<Double>,
      range: ClosedRange<Double>,
      format: String,
      multiplier: Double = 1
    ) -> some View {
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(title)
          Spacer()
          Text(String(format: format, value.wrappedValue * multiplier)).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
        Slider(value: value, in: range)
      }
    }

    private func destinationPicker(selection: Binding<RemappingDestination>) -> some View {
      Picker(
        OJDLocalized.string("common.destination", fallback: "Destination"),
        selection: selection
      ) {
        ForEach(discreteDestinations(including: selection.wrappedValue), id: \.destination) {
          Text($0.title).tag($0.destination)
        }
      }
    }

    private func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

  enum ProfileCombinationKind {
    case chord
    case sequence
  }

  struct ProfileCombinationSheet: View {
    let kind: ProfileCombinationKind
    let onSave: ([RemappingSource], Double, RemappingDestination) -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var sources: [RemappingSource] = [.button(.south), .button(.east)]
    @State private var windowMs = 1_000.0
    @State private var destination: RemappingDestination = .keyboard(key: .space, modifiers: [])

    var body: some View {
      VStack(alignment: .leading, spacing: 15) {
        Text(title).font(.headline.weight(.semibold))
        Text(
          kind == .chord
            ? OJDLocalized.string(
              "profiles.chordHelp",
              fallback: "The destination fires while all selected controls are pressed."
            )
            : OJDLocalized.string(
              "profiles.sequenceHelp",
              fallback: "The destination fires when the controls are pressed in this order."
            )
        ).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
        ForEach(sources.indices, id: \.self) { index in
          HStack {
            Picker(
              OJDLocalized.formatted("profiles.controlNumber", fallback: "Control %d", index + 1),
              selection: sourceBinding(at: index)
            ) {
              ForEach(discreteSources, id: \.source) { option in
                Text(option.title).tag(option.source)
              }
            }
            if sources.count > 2 {
              Button(
                action: { sources.remove(at: index) },
                label: { OJDSystemSymbol(name: "minus.circle", fallback: "Remove") }
              ).buttonStyle(BorderlessButtonStyle()).ojdAccessibilityLabel(
                OJDLocalized.string("common.remove", fallback: "Remove")
              )
            }
          }
        }
        Button(OJDLocalized.string("profiles.addControl", fallback: "Add control")) {
          sources.append(nextSource)
        }.disabled(sources.count >= discreteSources.count)
        if kind == .sequence {
          valueSlider(
            title: OJDLocalized.string("profiles.sequenceWindow", fallback: "Completion window"),
            value: $windowMs,
            range: RemappingSequence.windowRange
          )
        }
        Picker(
          OJDLocalized.string("common.destination", fallback: "Destination"),
          selection: $destination
        ) {
          ForEach(discreteDestinations(including: destination), id: \.destination) { option in
            Text(option.title).tag(option.destination)
          }
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel", fallback: "Cancel")) { dismiss() }
          Button(OJDLocalized.string("common.add", fallback: "Add")) {
            onSave(sources, windowMs, destination)
            dismiss()
          }.disabled(Set(sources).count != sources.count)
        }
      }.padding(28).frame(width: 480)
    }

    private var title: String {
      switch kind {
      case .chord: return OJDLocalized.string("profiles.addChord", fallback: "Add chord")
      case .sequence: return OJDLocalized.string("profiles.addSequence", fallback: "Add sequence")
      }
    }

    private var nextSource: RemappingSource {
      discreteSources.first { !sources.contains($0.source) }?.source ?? .button(.south)
    }

    private func sourceBinding(at index: Int) -> Binding<RemappingSource> {
      Binding(get: { sources[index] }, set: { sources[index] = $0 })
    }

    private func valueSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>)
      -> some View
    {
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(title)
          Spacer()
          Text(String(format: "%.0f ms", value.wrappedValue)).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
        Slider(value: value, in: range)
      }
    }

    private func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

  struct ProfileLayerSheet: View {
    let onSave: (String, RemappingSource, RemappingLayerActivation) -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var name = ""
    @State private var activator: RemappingSource = .button(.leftShoulder)
    @State private var activationMode = RemappingLayerActivation.hold

    var body: some View {
      VStack(alignment: .leading, spacing: 15) {
        Text(OJDLocalized.string("profiles.addLayer", fallback: "Add layer")).font(
          .headline.weight(.semibold)
        )
        TextField(OJDLocalized.string("profiles.layerName", fallback: "Layer name"), text: $name)
        Picker(
          OJDLocalized.string("profiles.activator", fallback: "Activator"),
          selection: $activator
        ) {
          ForEach(discreteSources, id: \.source) { option in Text(option.title).tag(option.source) }
        }
        Picker(
          OJDLocalized.string("profiles.activationMode", fallback: "Activation"),
          selection: $activationMode
        ) {
          Text(OJDLocalized.string("profiles.hold", fallback: "Hold")).tag(
            RemappingLayerActivation.hold
          )
          Text(OJDLocalized.string("profiles.toggle", fallback: "Toggle")).tag(
            RemappingLayerActivation.toggle
          )
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel", fallback: "Cancel")) { dismiss() }
          Button(OJDLocalized.string("common.add", fallback: "Add")) {
            onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), activator, activationMode)
            dismiss()
          }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }.padding(28).frame(width: 430)
    }

    private func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

  struct ProfileLayerBindingSheet: View {
    let layer: RemappingLayer
    let onSave: (RemappingSource, RemappingDestination) -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var source: RemappingSource = .button(.south)
    @State private var destination: RemappingDestination = .keyboard(key: .space, modifiers: [])

    var body: some View {
      VStack(alignment: .leading, spacing: 15) {
        Text(
          OJDLocalized.formatted(
            "profiles.addLayerAssignment",
            fallback: "Add assignment to %@",
            layer.name
          )
        ).font(.headline.weight(.semibold))
        Picker(
          OJDLocalized.string("capture.controllerControl", fallback: "Controller control"),
          selection: sourceBinding
        ) {
          ForEach(SourceOption.options(including: source), id: \.source) { option in
            Text(option.title).tag(option.source)
          }
        }
        Picker(
          OJDLocalized.string("common.destination", fallback: "Destination"),
          selection: $destination
        ) {
          ForEach(DestinationOption.options(for: source, including: destination), id: \.destination)
          { option in Text(option.title).tag(option.destination) }
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel", fallback: "Cancel")) { dismiss() }
          Button(OJDLocalized.string("common.add", fallback: "Add")) {
            onSave(source, destination)
            dismiss()
          }
        }
      }.padding(28).frame(width: 470)
    }

    private var sourceBinding: Binding<RemappingSource> {
      Binding(
        get: { source },
        set: { newSource in
          source = newSource
          let options = DestinationOption.options(for: newSource, including: destination)
          if !options.contains(where: { $0.destination == destination }), let first = options.first
          {
            destination = first.destination
          }
        }
      )
    }

    private func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

  private var discreteSources: [SourceOption] {
    SourceOption.options().filter { option in
      switch option.source {
      case .axis: false
      case .axisDirection, .button, .dpad: true
      }
    }
  }

  private func discreteDestinations(including current: RemappingDestination) -> [DestinationOption]
  { DestinationOption.options(for: .button(.south), including: current) }

#endif
