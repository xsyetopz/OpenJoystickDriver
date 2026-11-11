#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The sheet that edits the left and right trigger mappings of a profile, one trigger at a time.
  struct ProfileTriggerSheet: View {
    /// Receives the trigger mappings that are enabled when the person chooses Save.
    let onSave: ([RemappingTriggerMapping]) throws -> Void
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode
    /// The left trigger being edited.
    @State
    private var left: ProfileTriggerDraft
    /// The right trigger being edited.
    @State
    private var right: ProfileTriggerDraft
    /// The trigger the fields show.
    @State
    private var selected: RemappingTriggerSource = .left
    /// The message of the failed validation, or nil.
    @State
    private var errorMessage: String?

    /// Creates the sheet on the current trigger mappings.
    ///
    /// - Parameters:
    ///   - mappings: The trigger mappings to edit.
    ///   - onSave: Receives the validated mappings.
    init(
      mappings: [RemappingTriggerMapping],
      onSave: @escaping ([RemappingTriggerMapping]) throws -> Void
    ) {
      self.onSave = onSave
      _left = State(
        initialValue: ProfileTriggerDraft(
          source: .left,
          mapping: mappings.first { $0.source == .left }
        )
      )
      _right = State(
        initialValue: ProfileTriggerDraft(
          source: .right,
          mapping: mappings.first { $0.source == .right }
        )
      )
    }

    /// The title, the trigger picker, its fields and the buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.large) {
        Text(OJDLocalized.string("ui.profiles.trigger.title")).font(
          .headline
        )
        Picker(
          OJDLocalized.string("ui.profiles.trigger.source"),
          selection: $selected
        ) {
          Text(OJDLocalized.string("ui.profiles.trigger.left")).tag(
            RemappingTriggerSource.left
          )
          Text(OJDLocalized.string("ui.profiles.trigger.right")).tag(
            RemappingTriggerSource.right
          )
        }.pickerStyle(SegmentedPickerStyle())
        ScrollView {
          ProfileTriggerFields(draft: selected == .left ? $left : $right).padding(.trailing, 8)
        }
        if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        HStack {
          Button(OJDLocalized.string("action.reset")) {
            if selected == .left {
              left = ProfileTriggerDraft(source: .left, mapping: nil)
            } else {
              right = ProfileTriggerDraft(source: .right, mapping: nil)
            }
            errorMessage = nil
          }
          Spacer()
          Button(OJDLocalized.string("action.cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("action.save")) {
            do {
              let separator = Locale.current.decimalSeparator ?? "."
              let mappings = try [left, right].compactMap {
                try $0.validatedMapping(decimalSeparator: separator)
              }
              try onSave(mappings)
              presentationMode.wrappedValue.dismiss()
            } catch { errorMessage = RuntimePresentation.userFacingError(error) }
          }
        }
      }.ojdSheet(.regular).frame(
        height: ProfilePresentationPolicy.optionalEditorHeight(
          enabled: selected == .left ? left.enabled : right.enabled,
          compact: 260,
          expanded: 560
        )
      )
    }
  }
#endif
