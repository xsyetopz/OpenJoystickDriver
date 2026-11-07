#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The sheet that adds a macro or edits one: its name, steps, repeat and stop rules.
  struct MacroEditorSheet: View {
    /// What the controller has, which marks unsupported destinations.
    let capabilities: ControllerProfileCapabilities
    /// Receives the macro when the person chooses Apply.
    let onSave: (RemappingMacro) -> Void
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode
    /// The macro being edited.
    @State
    private var draft: MacroDraft

    /// Creates the sheet on `macro`, or on a new macro when nil.
    init(
      macro: RemappingMacro?,
      capabilities: ControllerProfileCapabilities,
      onSave: @escaping (RemappingMacro) -> Void
    ) {
      self.capabilities = capabilities
      self.onSave = onSave
      _draft = State(initialValue: MacroDraft(macro))
    }

    /// The fields, the steps and the Cancel and Apply buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        TextField(OJDLocalized.string("ui.macros.name"), text: $draft.name)
        HStack {
          Text(OJDLocalized.string("ui.macros.steps")).font(.headline)
          Spacer()
          Menu(OJDLocalized.string("ui.macros.addStep")) {
            ForEach(MacroStepKind.allCases) { kind in
              Button(kind.title) { draft.addStep(kind) }
            }
          }.fixedSize()
        }
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(draft.steps.indices, id: \.self) { index in stepRow(index) }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minHeight: 140, maxHeight: 280)
        Divider()
        Picker(OJDLocalized.string("ui.macros.repeat"), selection: repeatsUntilRelease) {
          Text(OJDLocalized.string("ui.macros.repeatCounted")).tag(false)
          Text(OJDLocalized.string("ui.macros.repeatWhileHeld")).tag(true)
        }
        if case .count(let count) = draft.repeatMode {
          Stepper(
            value: Binding(get: { count }, set: { draft.repeatMode = .count($0) }),
            in: RemappingMacro.repeatCountRange
          ) {
            HStack {
              Text(OJDLocalized.string("ui.macros.repeatTimes"))
              Spacer()
              Text(String(count)).foregroundColor(Color(NSColor.secondaryLabelColor))
            }
          }
        }
        Picker(OJDLocalized.string("ui.macros.whileRunning"), selection: $draft.whileRunning) {
          Text(OJDLocalized.string("ui.macros.whileRunningIgnore"))
            .tag(RemappingMacroWhileRunning.ignore)
          Text(OJDLocalized.string("ui.macros.whileRunningRestart"))
            .tag(RemappingMacroWhileRunning.restart)
        }
        Toggle(OJDLocalized.string("ui.macros.interruptOnRelease"), isOn: $draft.interruptOnRelease)
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) { dismiss() }
          Button(OJDLocalized.string("action.apply")) {
            onSave(draft.macro)
            dismiss()
          }.disabled(draft.macro.name.isEmpty)
        }
      }.padding(28).frame(width: 520)
    }

    /// Whether the macro repeats until the source is released.
    private var repeatsUntilRelease: Binding<Bool> {
      Binding(
        get: { draft.repeatMode == .whileHeld },
        set: { draft.repeatMode = $0 ? .whileHeld : .count(1) }
      )
    }

    /// The row of the step at `index`: its fields and the move and remove buttons.
    private func stepRow(_ index: Int) -> some View {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 6) { stepFields(index) }
        Spacer(minLength: 8)
        OJDCompactSymbolButton(
          symbolName: "arrow.up",
          label: OJDLocalized.string("ui.macros.moveUp")
        ) { draft.moveStep(at: index, by: -1) }.disabled(index == 0)
        OJDCompactSymbolButton(
          symbolName: "arrow.down",
          label: OJDLocalized.string("ui.macros.moveDown")
        ) { draft.moveStep(at: index, by: 1) }.disabled(index == draft.steps.count - 1)
        OJDCompactSymbolButton(
          symbolName: "minus.circle",
          label: OJDLocalized.string("ui.macros.removeStep")
        ) { draft.removeStep(at: index) }
      }
    }

    /// The fields of the step at `index`, by its kind.
    @ViewBuilder
    private func stepFields(_ index: Int) -> some View {
      switch draft.steps[index] {
      case .tap(let destination):
        destinationPicker(MacroStepKind.tap.title, destination) { draft.steps[index] = .tap($0) }
      case .press(let destination):
        destinationPicker(MacroStepKind.press.title, destination) {
          draft.steps[index] = .press($0)
        }
      case .release(let destination):
        destinationPicker(MacroStepKind.release.title, destination) {
          draft.steps[index] = .release($0)
        }
      case .chord(let destinations, let holdMs):
        ForEach(destinations.indices, id: \.self) { slot in
          HStack {
            destinationPicker(MacroStepKind.chord.title, destinations[slot]) {
              var changed = destinations
              changed[slot] = $0
              draft.steps[index] = .chord(destinations: changed, holdMs: holdMs)
            }
            if destinations.count > 1 {
              OJDCompactSymbolButton(
                symbolName: "minus.circle",
                label: OJDLocalized.string("action.remove")
              ) {
                var changed = destinations
                changed.remove(at: slot)
                draft.steps[index] = .chord(destinations: changed, holdMs: holdMs)
              }
            }
          }
        }
        Button(OJDLocalized.string("ui.macros.addChordKey")) {
          draft.steps[index] = .chord(
            destinations: destinations + [.keyboard(key: .space, modifiers: [])],
            holdMs: holdMs
          )
        }
        delaySlider(OJDLocalized.string("ui.macros.holdTime"), holdMs) {
          draft.steps[index] = .chord(destinations: destinations, holdMs: $0)
        }
      case .wait(let durationMs):
        delaySlider(MacroStepKind.wait.title, durationMs) {
          draft.steps[index] = .wait(durationMs: $0)
        }
      }
    }

    /// A picker titled `title` of the destinations a step can press.
    private func destinationPicker(
      _ title: String,
      _ destination: RemappingDestination,
      set: @escaping (RemappingDestination) -> Void
    ) -> some View {
      Picker(title, selection: Binding(get: { destination }, set: set)) {
        ForEach(stepDestinations(including: destination), id: \.destination) { option in
          Text(option.title).tag(option.destination).disabled(!option.isSupported)
        }
      }
    }

    /// A slider of a time in milliseconds, with the value beside the title.
    private func delaySlider(
      _ title: String,
      _ value: Double,
      set: @escaping (Double) -> Void
    ) -> some View {
      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text(title)
          Spacer()
          Text(String(format: "%.0f ms", value)).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
        Slider(
          value: Binding(get: { value }, set: set),
          in: RemappingMacro.delayMsRange,
          step: 10
        ).ojdAccessibilityLabel(title)
      }
    }

    /// The destinations a step can press, including `current`.
    private func stepDestinations(including current: RemappingDestination) -> [DestinationOption] {
      DestinationOption.options(
        for: .button(.south),
        including: current,
        capabilities: capabilities
      ).filter {
        switch $0.destination {
        case .keyboard, .mouseButton, .gamepadButton, .gamepadDpad: true
        case .mouseMovement, .scroll, .gamepadAxis, .physical, .macro, .profileSwitch, .layerSet,
          .pause:
          false
        }
      }
    }

    /// Dismisses the sheet.
    private func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

#endif
