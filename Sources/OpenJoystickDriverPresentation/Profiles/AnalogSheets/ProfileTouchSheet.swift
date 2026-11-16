#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The sheet that edits the touch surface mappings of a profile, one surface at a time.
  struct ProfileTouchSheet: View {
    /// Receives the touch mappings that are enabled when the person chooses Save.
    let onSave: ([RemappingTouchMapping]) throws -> Void
    /// What the controller has, which decides the surfaces that can be selected.
    let capabilities: ControllerProfileCapabilities
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode
    /// The primary surface being edited.
    @State
    private var primary: ProfileTouchDraft
    /// The left surface being edited.
    @State
    private var left: ProfileTouchDraft
    /// The right surface being edited.
    @State
    private var right: ProfileTouchDraft
    /// The surface the fields show.
    @State
    private var selected: RemappingTouchSurface = .primary
    /// The message of the failed validation, or nil.
    @State
    private var errorMessage: String?

    /// Creates the sheet on the current touch mappings and selects the first mapped surface, or
    /// else the first surface the controller has.
    ///
    /// - Parameters:
    ///   - mappings: The touch mappings to edit.
    ///   - capabilities: What the controller has.
    ///   - onSave: Receives the validated mappings.
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

    /// The title, the surface picker, its fields and the buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.large) {
        Text(OJDLocalized.string("ui.profiles.touch.title")).font(
          .headline
        )
        Picker(
          OJDLocalized.string("ui.profiles.touch.surface"),
          selection: $selected
        ) {
          Text(OJDLocalized.string("ui.mapping.touchSurfacePrimary")).tag(
            RemappingTouchSurface.primary
          ).disabled(!canSelect(.primary))
          Text(OJDLocalized.string("ui.mapping.touchSurfaceLeft")).tag(
            RemappingTouchSurface.left
          ).disabled(!canSelect(.left))
          Text(OJDLocalized.string("ui.mapping.touchSurfaceRight")).tag(
            RemappingTouchSurface.right
          ).disabled(!canSelect(.right))
        }.help(OJDLocalized.string("ui.profiles.touch.surfaceHelp")).pickerStyle(
          SegmentedPickerStyle()
        )
        ScrollView { ProfileTouchFields(draft: selectedDraft).padding(.trailing, 8) }
        if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        HStack {
          Button(OJDLocalized.string("action.reset")) {
            resetSelected()
            errorMessage = nil
          }.help(OJDLocalized.string("ui.help.reset"))
          Spacer()
          Button(OJDLocalized.string("action.cancel")) {
            presentationMode.wrappedValue.dismiss()
          }.help(OJDLocalized.string("ui.help.cancelSheet"))
          Button(OJDLocalized.string("action.save")) { save() }.help(
            OJDLocalized.string("ui.help.save")
          )
        }
      }.ojdSheet(.regular).frame(
        height: ProfilePresentationPolicy.optionalEditorHeight(
          enabled: selectedDraft.wrappedValue.enabled,
          compact: 260,
          expanded: 500
        )
      )
    }

    /// The edit of the selected surface.
    private var selectedDraft: Binding<ProfileTouchDraft> {
      switch selected {
      case .primary: $primary
      case .left: $left
      case .right: $right
      }
    }

    /// Returns whether the person can select `surface`: the controller has it, or its mapping is
    /// enabled.
    private func canSelect(_ surface: RemappingTouchSurface) -> Bool {
      ProfileCapabilityPolicy.supports(.touchContact(surface), capabilities: capabilities)
        || [primary, left, right].contains { $0.surface == surface && $0.enabled }
    }

    /// Sets the selected surface to the defaults.
    private func resetSelected() {
      switch selected {
      case .primary: primary = ProfileTouchDraft(surface: .primary, mapping: nil)
      case .left: left = ProfileTouchDraft(surface: .left, mapping: nil)
      case .right: right = ProfileTouchDraft(surface: .right, mapping: nil)
      }
    }

    /// Validates all surfaces and passes the enabled mappings to ``onSave``.
    ///
    /// A failure shows in ``errorMessage`` and keeps the sheet open.
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

    /// Returns the edit of `surface` from its mapping in `mappings`, or the defaults.
    private static func draft(
      _ surface: RemappingTouchSurface,
      mappings: [RemappingTouchMapping]
    ) -> ProfileTouchDraft {
      ProfileTouchDraft(surface: surface, mapping: mappings.first { $0.surface == surface })
    }
  }
#endif
