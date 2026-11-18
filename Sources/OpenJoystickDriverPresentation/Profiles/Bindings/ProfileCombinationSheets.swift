#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI
  /// What a combination sheet adds.
  enum ProfileCombinationKind {
    /// A chord: controls pressed together.
    case chord
    /// A sequence: controls pressed one after the other.
    case sequence
  }

  /// The sheet that adds a chord or a sequence: its controls, its time window and its
  /// destination.
  struct ProfileCombinationSheet: View {
    /// Whether the sheet adds a chord or a sequence.
    let kind: ProfileCombinationKind
    /// What the controller has, which marks unsupported sources and destinations.
    let capabilities: ControllerProfileCapabilities
    /// Receives the sources, chord mode, window in milliseconds and destination.
    typealias SaveAction = ([RemappingSource], RemappingChordMode, Double, RemappingDestination) ->
      Void
    /// Receives the combination when the person chooses Add.
    let onSave: SaveAction
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode
    /// The controls of the combination.
    @State
    private var sources: [RemappingSource]
    /// How a chord counts as pressed.
    @State
    private var chordMode: RemappingChordMode
    /// The time window in milliseconds.
    @State
    private var windowMs: Double
    /// The destination of the combination.
    @State
    private var destination: RemappingDestination

    /// Creates the sheet with two controls, a modifier chord and a window of 50 ms for a chord or
    /// 1000 ms for a sequence.
    ///
    /// - Parameters:
    ///   - kind: Whether the sheet adds a chord or a sequence.
    ///   - capabilities: What the controller has.
    ///   - onSave: Receives the combination.
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

    /// The control pickers, the timing, the destination and the Cancel and Add buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.large) {
        Text(title).font(.headline.weight(.semibold))
        Text(
          kind == .chord
            ? OJDLocalized.string(
              "ui.profiles.chordHelp"
            )
            : OJDLocalized.string(
              "ui.profiles.sequenceHelp"
            )
        ).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
        ForEach(sources.indices, id: \.self) { index in
          HStack {
            Picker(
              OJDLocalized.formatted("ui.profiles.controlNumber", index + 1),
              selection: sourceBinding(at: index)
            ) {
              ForEach(discreteSources(capabilities: capabilities), id: \.source) { option in
                Text(option.title).tag(option.source).disabled(!option.isSupported)
              }
            }.help(OJDLocalized.string("ui.profiles.combinationControlHelp"))
            if sources.count > 2 {
              Button(
                action: { sources.remove(at: index) },
                label: {
                  OJDSystemSymbol(
                    name: "minus.circle",
                    fallback: OJDLocalized.string("action.remove")
                  )
                }
              ).buttonStyle(BorderlessButtonStyle()).ojdAccessibilityLabel(
                OJDLocalized.string("action.remove")
              ).help(OJDLocalized.string("ui.profiles.removeControlHelp"))
            }
          }
        }
        Button(OJDLocalized.string("ui.profiles.addControl")) {
          sources.append(nextSource)
        }.disabled(sources.count >= discreteSources(capabilities: capabilities).count)
          .help(OJDLocalized.string("ui.profiles.addControlHelp"))
        if kind == .chord {
          Picker(
            OJDLocalized.string("ui.profiles.chordMode"),
            selection: $chordMode
          ) {
            Text(OJDLocalized.string("ui.profiles.chordModeModifier")).tag(
              RemappingChordMode.modifier
            )
            Text(OJDLocalized.string("ui.profiles.chordModeSimultaneous"))
              .tag(RemappingChordMode.simultaneous)
          }.help(OJDLocalized.string("ui.profiles.chordModeHelp"))
          if chordMode == .simultaneous {
            valueSlider(
              title: OJDLocalized.string("ui.profiles.chordWindow"),
              help: OJDLocalized.string("ui.profiles.chordWindowHelp"),
              value: $windowMs,
              range: RemappingChord.windowRange
            )
          }
        } else {
          valueSlider(
            title: OJDLocalized.string("ui.profiles.sequenceWindow"),
            help: OJDLocalized.string("ui.profiles.sequenceWindowHelp"),
            value: $windowMs,
            range: RemappingSequence.windowRange
          )
        }
        Picker(
          OJDLocalized.string("term.destination"),
          selection: $destination
        ) {
          ForEach(
            discreteDestinations(including: destination, capabilities: capabilities),
            id: \.destination
          ) { option in Text(option.title).tag(option.destination).disabled(!option.isSupported) }
        }.help(OJDLocalized.string("ui.capture.destinationHelp"))
        PhysicalOutputDestinationFields(destination: $destination)
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) { dismiss() }.help(
            OJDLocalized.string("ui.help.cancelSheet")
          )
          Button(OJDLocalized.string("action.add")) {
            let window = kind == .chord && chordMode == .modifier ? 50 : windowMs
            onSave(sources, chordMode, window, destination)
            dismiss()
          }.disabled(
            Set(sources).count != sources.count
              || !ProfileCapabilityPolicy.supports(destination, capabilities: capabilities)
          ).help(OJDLocalized.string("ui.profiles.addCombinationHelp"))
        }
      }.ojdSheet(.regular)
    }

    /// The title of the sheet.
    private var title: String {
      switch kind {
      case .chord: return OJDLocalized.string("ui.profiles.addChord")
      case .sequence: return OJDLocalized.string("ui.profiles.addSequence")
      }
    }

    /// The first control that the combination does not hold yet.
    private var nextSource: RemappingSource {
      discreteSources(capabilities: capabilities).first { !sources.contains($0.source) }?.source
        ?? .button(.south)
    }

    /// Returns a binding to the control at `index`.
    private func sourceBinding(at index: Int) -> Binding<RemappingSource> {
      Binding(get: { sources[index] }, set: { sources[index] = $0 })
    }

    /// A slider for `value` in milliseconds, with `title` and the value beside it.
    private func valueSlider(
      title: String,
      help: String,
      value: Binding<Double>,
      range: ClosedRange<Double>
    ) -> some View {
      VStack(alignment: .leading, spacing: OJDSpacing.xSmall) {
        HStack {
          Text(title)
          Spacer()
          Text(unsafe String(format: "%.0f ms", value.wrappedValue)).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
        Slider(value: value, in: range).ojdAccessibilityLabel(title).help(help)
      }
    }

    /// Dismisses the sheet.
    private func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

  /// The sheet that adds a layer: its name, the control that activates it and how.
  struct ProfileLayerSheet: View {
    /// What the controller has, which marks unsupported sources.
    let capabilities: ControllerProfileCapabilities
    /// Receives the name, activator and activation mode when the person chooses Add.
    let onSave: (String, RemappingSource, RemappingLayerActivation) -> Void
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode
    /// The name of the layer.
    @State
    private var name = ""
    /// The control that activates the layer.
    @State
    private var activator: RemappingSource = .button(.leftShoulder)
    /// Whether the layer is active while the activator is held or after it is toggled.
    @State
    private var activationMode = RemappingLayerActivation.hold

    /// The layer name, activator and activation mode with the Cancel and Add buttons.
    var body: some View {
      ProfileSheetScaffold(title: OJDLocalized.string("ui.profiles.addLayer")) {
        TextField(OJDLocalized.string("ui.profiles.layerName"), text: $name)
          .ojdAccessibilityLabel(OJDLocalized.string("ui.profiles.layerName"))
          .help(OJDLocalized.string("ui.profiles.layerNameHelp"))
        Picker(
          OJDLocalized.string("ui.profiles.activator"),
          selection: $activator
        ) {
          ForEach(discreteSources(capabilities: capabilities), id: \.source) { option in
            Text(option.title).tag(option.source).disabled(!option.isSupported)
          }
        }.help(OJDLocalized.string("ui.profiles.activatorHelp"))
        Picker(
          OJDLocalized.string("ui.profiles.activationMode"),
          selection: $activationMode
        ) {
          Text(OJDLocalized.string("ui.profiles.hold")).tag(
            RemappingLayerActivation.hold
          )
          Text(OJDLocalized.string("ui.profiles.toggle")).tag(
            RemappingLayerActivation.toggle
          )
        }.help(OJDLocalized.string("ui.profiles.activationModeHelp"))
      } footer: {
        Spacer()
        Button(OJDLocalized.string("action.cancel")) { dismiss() }.help(
          OJDLocalized.string("ui.help.cancelSheet")
        )
        Button(OJDLocalized.string("action.add")) {
          onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), activator, activationMode)
          dismiss()
        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .help(OJDLocalized.string("ui.profiles.addLayerHelp"))
      }
    }

    /// Dismisses the sheet.
    private func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

  /// The sheet that adds an assignment to a layer.
  struct ProfileLayerBindingSheet: View {
    /// The layer that receives the assignment.
    let layer: RemappingLayer
    /// What the controller has, which marks unsupported sources and destinations.
    let capabilities: ControllerProfileCapabilities
    /// Receives the source and destination when the person chooses Add.
    let onSave: (RemappingSource, RemappingDestination) -> Void
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode
    /// The source of the assignment.
    @State
    private var source: RemappingSource = .button(.south)
    /// The destination of the assignment.
    @State
    private var destination: RemappingDestination = .keyboard(key: .space, modifiers: [])

    /// The source and destination pickers with the Cancel and Add buttons.
    var body: some View {
      ProfileSheetScaffold(
        title: OJDLocalized.formatted(
          "ui.profiles.addLayerAssignment",
          layer.name
        )
      ) {
        Picker(
          OJDLocalized.string("ui.capture.controllerControl"),
          selection: sourceBinding
        ) {
          ForEach(SourceOption.options(including: source, capabilities: capabilities), id: \.source)
          { option in Text(option.title).tag(option.source).disabled(!option.isSupported) }
        }.help(OJDLocalized.string("ui.capture.controlHelp"))
        Picker(
          OJDLocalized.string("term.destination"),
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
        }.help(OJDLocalized.string("ui.capture.destinationHelp"))
        PhysicalOutputDestinationFields(destination: $destination)
      } footer: {
        Spacer()
        Button(OJDLocalized.string("action.cancel")) { dismiss() }.help(
          OJDLocalized.string("ui.help.cancelSheet")
        )
        Button(OJDLocalized.string("action.add")) {
          onSave(source, destination)
          dismiss()
        }.disabled(
          !ProfileCapabilityPolicy.supports(source, capabilities: capabilities)
            || !ProfileCapabilityPolicy.supports(destination, capabilities: capabilities)
        ).help(OJDLocalized.string("ui.capture.addHelp"))
      }
    }

    /// The source picker's binding; choosing a source keeps the destination when it still fits
    /// the source, and else takes the first destination that does.
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

    /// Dismisses the sheet.
    private func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

  /// Returns the sources that a chord, sequence or layer can use: every source except an axis.
  private func discreteSources(capabilities: ControllerProfileCapabilities) -> [SourceOption] {
    SourceOption.options(capabilities: capabilities).filter { option in
      switch option.source {
      case .axis: false
      case .axisDirection, .triggerStage, .motionLean, .button, .dpad, .touchContact, .touchGrid,
        .touchSwipe, .stickRegion, .triggerBand, .touchArea:
        true
      }
    }
  }

  /// Returns the destinations of a discrete source, including `current`.
  func discreteDestinations(including current: RemappingDestination) -> [DestinationOption] {
    DestinationOption.options(for: .button(.south), including: current)
  }

  /// Returns the destinations of a discrete source that fit `capabilities`, including
  /// `current`.
  func discreteDestinations(
    including current: RemappingDestination,
    capabilities: ControllerProfileCapabilities
  ) -> [DestinationOption] {
    DestinationOption.options(for: .button(.south), including: current, capabilities: capabilities)
  }

#endif
