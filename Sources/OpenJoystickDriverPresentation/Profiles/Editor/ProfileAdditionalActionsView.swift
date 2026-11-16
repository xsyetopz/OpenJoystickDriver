#if canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The list of additional actions of an assignment: a destination, Behavior, Move Up, Move Down
  /// and Remove for each, and Add Action.
  struct ProfileAdditionalActionsView: View {
    /// The source of the assignment, which decides the destinations that fit.
    let source: RemappingSource
    /// What the controller has, or nil when it is not known.
    let capabilities: ControllerProfileCapabilities?
    /// The additional actions being edited.
    @Binding
    var actions: [RemappingAction]
    /// The action whose behavior the sheet edits, or nil.
    @State
    private var editing: RemappingAction?

    /// The additional actions and the Add Action button.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.small) {
        Text(OJDLocalized.string("ui.profiles.additionalActions"))
          .font(.headline)
        ScrollView {
          VStack(alignment: .leading, spacing: OJDSpacing.medium) {
            ForEach(actions) { action in
              VStack(alignment: .leading, spacing: OJDSpacing.xSmall) {
                Picker(
                  OJDLocalized.string("term.destination"),
                  selection: destinationBinding(action)
                ) {
                  ForEach(
                    DestinationOption.options(
                      for: source,
                      including: action.destination,
                      capabilities: capabilities
                    ),
                    id: \.destination
                  ) { Text($0.title).tag($0.destination).disabled(!$0.isSupported) }
                }.help(OJDLocalized.string("ui.capture.destinationHelp"))
                PhysicalOutputDestinationFields(destination: destinationBinding(action))
                HStack {
                  Button(
                    OJDLocalized.string("ui.profiles.bindingBehavior")
                  ) { editing = action }.help(OJDLocalized.string("ui.profiles.behaviorHelp"))
                  Button(OJDLocalized.string("ui.profiles.moveUp")) {
                    move(action, by: -1)
                  }.disabled(actions.first?.id == action.id)
                    .help(OJDLocalized.string("ui.profiles.moveActionUpHelp"))
                  Button(OJDLocalized.string("ui.profiles.moveDown")) {
                    move(action, by: 1)
                  }.disabled(actions.last?.id == action.id)
                    .help(OJDLocalized.string("ui.profiles.moveActionDownHelp"))
                  Button(OJDLocalized.string("action.remove")) {
                    actions.removeAll { $0.id == action.id }
                  }.help(OJDLocalized.string("ui.profiles.removeActionHelp"))
                }
              }
            }
          }
        }.frame(height: actions.isEmpty ? 0 : 170)
        let firstDestination = DestinationOption.options(for: source, capabilities: capabilities)
          .first?.destination
        Button(OJDLocalized.string("ui.profiles.addAction")) {
          if let firstDestination { actions.append(RemappingAction(destination: firstDestination)) }
        }.disabled(
          firstDestination == nil || actions.count >= RemappingProfile.maximumBindingCount - 1
        ).help(OJDLocalized.string("ui.profiles.addActionHelp"))
      }.sheet(item: $editing) { action in
        BindingBehaviorSheet(
          binding: RemappingBinding(
            id: action.id,
            source: source,
            destination: action.destination,
            behavior: action.behavior,
            pulseDurationMs: action.pulseDurationMs,
            turbo: action.turbo,
            longHold: action.longHold,
            multiTap: action.multiTap
          ),
          showsAdditionalActions: false,
          capabilities: capabilities
        ) { behavior, duration, turbo, hold, tap, _, _ in
          replace(
            RemappingAction(
              id: action.id,
              destination: action.destination,
              behavior: behavior,
              pulseDurationMs: behavior == .pulse
                ? duration : RemappingBinding.defaultPulseDurationMs,
              turbo: turbo,
              longHold: hold,
              multiTap: tap
            )
          )
        }
      }
    }

    /// Returns a binding that sets the destination of `action`.
    private func destinationBinding(_ action: RemappingAction) -> Binding<RemappingDestination> {
      Binding(
        get: { action.destination },
        set: { destination in
          replace(
            RemappingAction(
              id: action.id,
              destination: destination,
              behavior: action.behavior,
              pulseDurationMs: action.pulseDurationMs,
              turbo: action.turbo,
              longHold: action.longHold,
              multiTap: action.multiTap
            )
          )
        }
      )
    }

    /// Replaces the action that has the identifier of `action`.
    private func replace(_ action: RemappingAction) {
      guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
      actions[index] = action
    }

    /// Moves `action` by `offset` places; a move off either end changes nothing.
    private func move(_ action: RemappingAction, by offset: Int) {
      guard let index = actions.firstIndex(where: { $0.id == action.id }),
        actions.indices.contains(index + offset)
      else { return }
      actions.swapAt(index, index + offset)
    }
  }
#endif
