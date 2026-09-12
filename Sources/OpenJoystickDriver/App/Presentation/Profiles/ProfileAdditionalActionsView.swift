#if canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileAdditionalActionsView: View {
    let source: RemappingSource
    @Binding var actions: [RemappingAction]
    @State private var editing: RemappingAction?

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(OJDLocalized.string("profiles.additionalActions", fallback: "Additional actions"))
          .font(.headline)
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(actions) { action in
              VStack(alignment: .leading, spacing: 5) {
                Picker(
                  OJDLocalized.string("common.destination", fallback: "Destination"),
                  selection: destinationBinding(action)
                ) {
                  ForEach(
                    DestinationOption.options(for: source, including: action.destination),
                    id: \.destination
                  ) {
                    Text($0.title).tag($0.destination)
                  }
                }
                PhysicalOutputDestinationFields(destination: destinationBinding(action))
                HStack {
                  Button(
                    OJDLocalized.string("profiles.bindingBehavior", fallback: "Assignment behavior")
                  ) {
                    editing = action
                  }
                  Button(OJDLocalized.string("profiles.moveUp", fallback: "Move up")) {
                    move(action, by: -1)
                  }.disabled(actions.first?.id == action.id)
                  Button(OJDLocalized.string("profiles.moveDown", fallback: "Move down")) {
                    move(action, by: 1)
                  }.disabled(actions.last?.id == action.id)
                  Button(OJDLocalized.string("common.remove", fallback: "Remove")) {
                    actions.removeAll { $0.id == action.id }
                  }
                }
              }
            }
          }
        }.frame(height: actions.isEmpty ? 0 : 170)
        Button(OJDLocalized.string("profiles.addAction", fallback: "Add action")) {
          guard let destination = DestinationOption.options(for: source).first?.destination else {
            return
          }
          actions.append(RemappingAction(destination: destination))
        }.disabled(actions.count >= RemappingProfile.maximumBindingCount - 1)
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
            doubleTap: action.doubleTap
          ),
          showsAdditionalActions: false
        ) { behavior, duration, turbo, hold, tap, _ in
          replace(RemappingAction(
            id: action.id,
            destination: action.destination,
            behavior: behavior,
            pulseDurationMs: behavior == .pulse
              ? duration : RemappingBinding.defaultPulseDurationMs,
            turbo: turbo,
            longHold: hold,
            doubleTap: tap
          ))
        }
      }
    }

    private func destinationBinding(_ action: RemappingAction) -> Binding<RemappingDestination> {
      Binding(get: { action.destination }, set: { destination in
        replace(RemappingAction(
          id: action.id,
          destination: destination,
          behavior: action.behavior,
          pulseDurationMs: action.pulseDurationMs,
          turbo: action.turbo,
          longHold: action.longHold,
          doubleTap: action.doubleTap
        ))
      })
    }

    private func replace(_ action: RemappingAction) {
      guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
      actions[index] = action
    }

    private func move(_ action: RemappingAction, by offset: Int) {
      guard let index = actions.firstIndex(where: { $0.id == action.id }),
        actions.indices.contains(index + offset)
      else { return }
      actions.swapAt(index, index + offset)
    }
  }
#endif
