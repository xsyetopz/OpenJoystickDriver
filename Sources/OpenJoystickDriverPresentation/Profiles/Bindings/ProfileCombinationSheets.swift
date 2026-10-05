#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI
  enum ProfileCombinationKind {
    case chord
    case sequence
  }

  struct ProfileCombinationSheet: View {
    let kind: ProfileCombinationKind
    let capabilities: ControllerProfileCapabilities
    typealias SaveAction = ([RemappingSource], RemappingChordMode, Double, RemappingDestination) ->
      Void
    let onSave: SaveAction
    @Environment(\.presentationMode)
    private var presentationMode
    @State
    private var sources: [RemappingSource]
    @State
    private var chordMode: RemappingChordMode
    @State
    private var windowMs: Double
    @State
    private var destination: RemappingDestination

    init(
      kind: ProfileCombinationKind,
      capabilities: ControllerProfileCapabilities,
      onSave: @escaping SaveAction
    ) {
      self.kind = kind
      self.capabilities = capabilities
      self.onSave = onSave
      _sources = State(initialValue: [.button(.south), .button(.east)])
      _chordMode = State(initialValue: .modifier)
      _windowMs = State(initialValue: kind == .chord ? 50 : 1_000)
      _destination = State(initialValue: .keyboard(key: .space, modifiers: []))
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 15) {
        Text(title).font(.headline.weight(.semibold))
        Text(
          kind == .chord
            ? OJDLocalized.string(
              "profiles.chordHelp"
            )
            : OJDLocalized.string(
              "profiles.sequenceHelp"
            )
        ).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
        ForEach(sources.indices, id: \.self) { index in
          HStack {
            Picker(
              OJDLocalized.formatted("profiles.controlNumber", index + 1),
              selection: sourceBinding(at: index)
            ) {
              ForEach(discreteSources(capabilities: capabilities), id: \.source) { option in
                Text(option.title).tag(option.source).disabled(!option.isSupported)
              }
            }
            if sources.count > 2 {
              Button(
                action: { sources.remove(at: index) },
                label: {
                  OJDSystemSymbol(
                    name: "minus.circle",
                    fallback: OJDLocalized.string("common.remove")
                  )
                }
              ).buttonStyle(BorderlessButtonStyle()).ojdAccessibilityLabel(
                OJDLocalized.string("common.remove")
              )
            }
          }
        }
        Button(OJDLocalized.string("profiles.addControl")) {
          sources.append(nextSource)
        }.disabled(sources.count >= discreteSources(capabilities: capabilities).count)
        if kind == .chord {
          Picker(
            OJDLocalized.string("profiles.chordMode"),
            selection: $chordMode
          ) {
            Text(OJDLocalized.string("profiles.chordModeModifier")).tag(
              RemappingChordMode.modifier
            )
            Text(OJDLocalized.string("profiles.chordModeSimultaneous"))
              .tag(RemappingChordMode.simultaneous)
          }
          if chordMode == .simultaneous {
            valueSlider(
              title: OJDLocalized.string("profiles.chordWindow"),
              value: $windowMs,
              range: RemappingChord.windowRange
            )
          }
        } else {
          valueSlider(
            title: OJDLocalized.string("profiles.sequenceWindow"),
            value: $windowMs,
            range: RemappingSequence.windowRange
          )
        }
        Picker(
          OJDLocalized.string("common.destination"),
          selection: $destination
        ) {
          ForEach(
            discreteDestinations(including: destination, capabilities: capabilities),
            id: \.destination
          ) { option in Text(option.title).tag(option.destination).disabled(!option.isSupported) }
        }
        PhysicalOutputDestinationFields(destination: $destination)
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel")) { dismiss() }
          Button(OJDLocalized.string("common.add")) {
            let window = kind == .chord && chordMode == .modifier ? 50 : windowMs
            onSave(sources, chordMode, window, destination)
            dismiss()
          }.disabled(
            Set(sources).count != sources.count
              || !ProfileCapabilityPolicy.supports(destination, capabilities: capabilities)
          )
        }
      }.padding(28).frame(width: 480)
    }

    private var title: String {
      switch kind {
      case .chord: return OJDLocalized.string("profiles.addChord")
      case .sequence: return OJDLocalized.string("profiles.addSequence")
      }
    }

    private var nextSource: RemappingSource {
      discreteSources(capabilities: capabilities).first { !sources.contains($0.source) }?.source
        ?? .button(.south)
    }

    private func sourceBinding(at index: Int) -> Binding<RemappingSource> {
      Binding(get: { sources[index] }, set: { sources[index] = $0 })
    }

    private func valueSlider(
      title: String,
      value: Binding<Double>,
      range: ClosedRange<Double>
    ) -> some View {
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(title)
          Spacer()
          Text(String(format: "%.0f ms", value.wrappedValue)).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
        Slider(value: value, in: range).ojdAccessibilityLabel(title)
      }
    }

    private func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

  struct ProfileLayerSheet: View {
    let capabilities: ControllerProfileCapabilities
    let onSave: (String, RemappingSource, RemappingLayerActivation) -> Void
    @Environment(\.presentationMode)
    private var presentationMode
    @State
    private var name = ""
    @State
    private var activator: RemappingSource = .button(.leftShoulder)
    @State
    private var activationMode = RemappingLayerActivation.hold

    var body: some View {
      ProfileSheetScaffold(title: OJDLocalized.string("profiles.addLayer")) {
        TextField(OJDLocalized.string("profiles.layerName"), text: $name)
        Picker(
          OJDLocalized.string("profiles.activator"),
          selection: $activator
        ) {
          ForEach(discreteSources(capabilities: capabilities), id: \.source) { option in
            Text(option.title).tag(option.source).disabled(!option.isSupported)
          }
        }
        Picker(
          OJDLocalized.string("profiles.activationMode"),
          selection: $activationMode
        ) {
          Text(OJDLocalized.string("profiles.hold")).tag(
            RemappingLayerActivation.hold
          )
          Text(OJDLocalized.string("profiles.toggle")).tag(
            RemappingLayerActivation.toggle
          )
        }
      } footer: {
        Spacer()
        Button(OJDLocalized.string("common.cancel")) { dismiss() }
        Button(OJDLocalized.string("common.add")) {
          onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), activator, activationMode)
          dismiss()
        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }

    private func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

  struct ProfileLayerBindingSheet: View {
    let layer: RemappingLayer
    let capabilities: ControllerProfileCapabilities
    let onSave: (RemappingSource, RemappingDestination) -> Void
    @Environment(\.presentationMode)
    private var presentationMode
    @State
    private var source: RemappingSource = .button(.south)
    @State
    private var destination: RemappingDestination = .keyboard(key: .space, modifiers: [])

    var body: some View {
      ProfileSheetScaffold(
        title: OJDLocalized.formatted(
          "profiles.addLayerAssignment",
          layer.name
        )
      ) {
        Picker(
          OJDLocalized.string("capture.controllerControl"),
          selection: sourceBinding
        ) {
          ForEach(SourceOption.options(including: source, capabilities: capabilities), id: \.source)
          { option in Text(option.title).tag(option.source).disabled(!option.isSupported) }
        }
        Picker(
          OJDLocalized.string("common.destination"),
          selection: $destination
        ) {
          ForEach(
            DestinationOption.options(
              for: source,
              including: destination,
              capabilities: capabilities
            ),
            id: \.destination
          ) { option in Text(option.title).tag(option.destination).disabled(!option.isSupported) }
        }
        PhysicalOutputDestinationFields(destination: $destination)
      } footer: {
        Spacer()
        Button(OJDLocalized.string("common.cancel")) { dismiss() }
        Button(OJDLocalized.string("common.add")) {
          onSave(source, destination)
          dismiss()
        }.disabled(
          !ProfileCapabilityPolicy.supports(source, capabilities: capabilities)
            || !ProfileCapabilityPolicy.supports(destination, capabilities: capabilities)
        )
      }
    }

    private var sourceBinding: Binding<RemappingSource> {
      Binding(
        get: { source },
        set: { newSource in
          source = newSource
          let options = DestinationOption.options(
            for: newSource,
            including: destination,
            capabilities: capabilities
          )
          if !options.contains(where: { $0.destination == destination }), let first = options.first
          {
            destination = first.destination
          }
        }
      )
    }

    private func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

  private func discreteSources(capabilities: ControllerProfileCapabilities) -> [SourceOption] {
    SourceOption.options(capabilities: capabilities).filter { option in
      switch option.source {
      case .axis: false
      case .axisDirection, .triggerStage, .motionLean, .button, .dpad, .touchContact, .touchGrid,
        .touchSwipe:
        true
      }
    }
  }

  func discreteDestinations(including current: RemappingDestination) -> [DestinationOption] {
    DestinationOption.options(for: .button(.south), including: current)
  }

  func discreteDestinations(
    including current: RemappingDestination,
    capabilities: ControllerProfileCapabilities
  ) -> [DestinationOption] {
    DestinationOption.options(for: .button(.south), including: current, capabilities: capabilities)
  }

#endif
