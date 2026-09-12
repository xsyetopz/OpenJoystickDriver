#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileTouchSheet: View {
    let onSave: ([RemappingTouchMapping]) throws -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var primary: ProfileTouchDraft
    @State private var left: ProfileTouchDraft
    @State private var right: ProfileTouchDraft
    @State private var selected: RemappingTouchSurface = .primary
    @State private var errorMessage: String?

    init(
      mappings: [RemappingTouchMapping],
      onSave: @escaping ([RemappingTouchMapping]) throws -> Void
    ) {
      self.onSave = onSave
      _primary = State(initialValue: Self.draft(.primary, mappings: mappings))
      _left = State(initialValue: Self.draft(.left, mappings: mappings))
      _right = State(initialValue: Self.draft(.right, mappings: mappings))
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(OJDLocalized.string("profiles.touch.title", fallback: "Touch mappings"))
          .font(.headline)
        Picker(
          OJDLocalized.string("profiles.touch.surface", fallback: "Surface"), selection: $selected
        ) {
          Text(OJDLocalized.string("mapping.touchSurfacePrimary", fallback: "Primary surface"))
            .tag(RemappingTouchSurface.primary)
          Text(OJDLocalized.string("mapping.touchSurfaceLeft", fallback: "Left surface"))
            .tag(RemappingTouchSurface.left)
          Text(OJDLocalized.string("mapping.touchSurfaceRight", fallback: "Right surface"))
            .tag(RemappingTouchSurface.right)
        }.pickerStyle(SegmentedPickerStyle())
        ScrollView { ProfileTouchFields(draft: selectedDraft).padding(.trailing, 8) }
        if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        HStack {
          Button(OJDLocalized.string("common.reset", fallback: "Reset")) {
            resetSelected()
            errorMessage = nil
          }
          Spacer()
          Button(OJDLocalized.string("common.cancel", fallback: "Cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("common.save", fallback: "Save")) { save() }
        }
      }.padding(28).frame(width: 500, height: 500)
    }

    private var selectedDraft: Binding<ProfileTouchDraft> {
      switch selected {
      case .primary: $primary
      case .left: $left
      case .right: $right
      }
    }

    private func resetSelected() {
      switch selected {
      case .primary: primary = ProfileTouchDraft(surface: .primary, mapping: nil)
      case .left: left = ProfileTouchDraft(surface: .left, mapping: nil)
      case .right: right = ProfileTouchDraft(surface: .right, mapping: nil)
      }
    }

    private func save() {
      do {
        let separator = Locale.current.decimalSeparator ?? "."
        let mappings = try [primary, left, right].compactMap {
          try $0.validatedMapping(decimalSeparator: separator)
        }
        try onSave(mappings)
        presentationMode.wrappedValue.dismiss()
      } catch { errorMessage = RuntimePresentation.userFacingError(error) }
    }

    private static func draft(
      _ surface: RemappingTouchSurface, mappings: [RemappingTouchMapping]
    ) -> ProfileTouchDraft {
      ProfileTouchDraft(surface: surface, mapping: mappings.first { $0.surface == surface })
    }
  }
#endif
