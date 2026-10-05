#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileTouchSheet: View {
    let onSave: ([RemappingTouchMapping]) throws -> Void
    let capabilities: ControllerProfileCapabilities
    @Environment(\.presentationMode)
    private var presentationMode
    @State
    private var primary: ProfileTouchDraft
    @State
    private var left: ProfileTouchDraft
    @State
    private var right: ProfileTouchDraft
    @State
    private var selected: RemappingTouchSurface = .primary
    @State
    private var errorMessage: String?

    init(
      mappings: [RemappingTouchMapping],
      capabilities: ControllerProfileCapabilities,
      onSave: @escaping ([RemappingTouchMapping]) throws -> Void
    ) {
      self.onSave = onSave
      self.capabilities = capabilities
      _primary = State(initialValue: Self.draft(.primary, mappings: mappings))
      _left = State(initialValue: Self.draft(.left, mappings: mappings))
      _right = State(initialValue: Self.draft(.right, mappings: mappings))
      let available = RemappingTouchSurface.allCases.first {
        ProfileCapabilityPolicy.supports(.touchContact($0), capabilities: capabilities)
      }
      _selected = State(initialValue: mappings.first?.surface ?? available ?? .primary)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(OJDLocalized.string("profiles.touch.title")).font(
          .headline
        )
        Picker(
          OJDLocalized.string("profiles.touch.surface"),
          selection: $selected
        ) {
          Text(OJDLocalized.string("mapping.touchSurfacePrimary")).tag(
            RemappingTouchSurface.primary
          ).disabled(!canSelect(.primary))
          Text(OJDLocalized.string("mapping.touchSurfaceLeft")).tag(
            RemappingTouchSurface.left
          ).disabled(!canSelect(.left))
          Text(OJDLocalized.string("mapping.touchSurfaceRight")).tag(
            RemappingTouchSurface.right
          ).disabled(!canSelect(.right))
        }.pickerStyle(SegmentedPickerStyle())
        ScrollView { ProfileTouchFields(draft: selectedDraft).padding(.trailing, 8) }
        if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        HStack {
          Button(OJDLocalized.string("common.reset")) {
            resetSelected()
            errorMessage = nil
          }
          Spacer()
          Button(OJDLocalized.string("common.cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("common.save")) { save() }
        }
      }.padding(28).frame(
        width: 500,
        height: ProfilePresentationPolicy.optionalEditorHeight(
          enabled: selectedDraft.wrappedValue.enabled,
          compact: 260,
          expanded: 500
        )
      )
    }

    private var selectedDraft: Binding<ProfileTouchDraft> {
      switch selected {
      case .primary: $primary
      case .left: $left
      case .right: $right
      }
    }

    private func canSelect(_ surface: RemappingTouchSurface) -> Bool {
      ProfileCapabilityPolicy.supports(.touchContact(surface), capabilities: capabilities)
        || [primary, left, right].contains { $0.surface == surface && $0.enabled }
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
      _ surface: RemappingTouchSurface,
      mappings: [RemappingTouchMapping]
    ) -> ProfileTouchDraft {
      ProfileTouchDraft(surface: surface, mapping: mappings.first { $0.surface == surface })
    }
  }
#endif
