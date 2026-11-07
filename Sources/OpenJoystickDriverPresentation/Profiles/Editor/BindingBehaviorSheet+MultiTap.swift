#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension BindingBehaviorSheet {
    /// The tap-count entries, the button that adds one, and the delay they add to the base
    /// destination.
    var multiTapSection: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(OJDLocalized.string("ui.profiles.multiTap")).font(.subheadline.weight(.semibold))
          Spacer()
          Button(OJDLocalized.string("ui.profiles.addMultiTap")) {
            multiTapEntries = MultiTapEntries.adding(
              to: multiTapEntries,
              destination: .keyboard(key: .space, modifiers: [])
            )
          }.disabled(
            !supportsActivation || turboEnabled || behavior != .hold
              || MultiTapEntries.unusedCounts(in: multiTapEntries).isEmpty
          )
        }
        ForEach(multiTapEntries, id: \.count) { entry in
          multiTapRow(entry)
        }
        if !multiTapEntries.isEmpty {
          Text(
            OJDLocalized.formatted(
              "ui.profiles.tapDelay",
              String(format: "%.0f ms", multiTapEntries.longestWindowMs)
            )
          ).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
      }
    }

    /// The fields of one tap-count entry.
    private func multiTapRow(_ entry: RemappingMultiTap) -> some View {
      let count = entry.count
      let update = { (changed: RemappingMultiTap) in
        multiTapEntries = MultiTapEntries.replacing(
          count: count, with: changed, in: multiTapEntries)
      }
      return VStack(alignment: .leading, spacing: 8) {
        HStack {
          Picker(
            OJDLocalized.string("ui.profiles.tapCount"),
            selection: Binding(
              get: { count },
              set: {
                update(
                  RemappingMultiTap(
                    count: $0, windowMs: entry.windowMs, destination: entry.destination))
              }
            )
          ) {
            ForEach(
              (MultiTapEntries.unusedCounts(in: multiTapEntries) + [count]).sorted(), id: \.self
            ) { Text("\($0)").tag($0) }
          }
          Button(OJDLocalized.string("action.remove")) {
            multiTapEntries = MultiTapEntries.removing(count: count, from: multiTapEntries)
          }
        }
        valueSlider(
          title: OJDLocalized.string("ui.profiles.tapWindow"),
          value: Binding(
            get: { entry.windowMs },
            set: {
              update(
                RemappingMultiTap(count: count, windowMs: $0, destination: entry.destination))
            }
          ),
          range: RemappingMultiTap.windowRange,
          format: "%.0f ms"
        )
        destinationPicker(
          selection: Binding(
            get: { entry.destination },
            set: {
              update(RemappingMultiTap(count: count, windowMs: entry.windowMs, destination: $0))
            }
          )
        )
      }
    }
  }

#endif
