#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The sheet that edits the left and right stick mappings of a profile, one stick at a time.
  struct ProfileStickSheet: View {
    /// Receives the stick mappings that are enabled when the person chooses Save.
    let onSave: ([RemappingStickMapping]) throws -> Void
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode
    /// The left stick being edited.
    @State
    private var left: ProfileStickDraft
    /// The right stick being edited.
    @State
    private var right: ProfileStickDraft
    /// The stick the fields show.
    @State
    private var selected: RemappingStickSource = .left
    /// The message of the failed validation, or nil.
    @State
    private var errorMessage: String?

    /// Creates the sheet on the current stick mappings.
    ///
    /// - Parameters:
    ///   - mappings: The stick mappings to edit.
    ///   - onSave: Receives the validated mappings.
    init(
      mappings: [RemappingStickMapping],
      onSave: @escaping ([RemappingStickMapping]) throws -> Void
    ) {
      self.onSave = onSave
      _left = State(
        initialValue: ProfileStickDraft(
          source: .left,
          mapping: mappings.first { $0.source == .left }
        )
      )
      _right = State(
        initialValue: ProfileStickDraft(
          source: .right,
          mapping: mappings.first { $0.source == .right }
        )
      )
    }

    /// The title, the left or right stick picker, its fields, an error if any, and the buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.large) {
        Text(OJDLocalized.string("ui.profiles.stick.title")).font(.headline)
        Picker(
          OJDLocalized.string("ui.profiles.stick.source"),
          selection: $selected
        ) {
          Text(OJDLocalized.string("ui.profiles.gyro.leftStick")).tag(
            RemappingStickSource.left
          )
          Text(OJDLocalized.string("ui.profiles.gyro.rightStick")).tag(
            RemappingStickSource.right
          )
        }.help(OJDLocalized.string("ui.profiles.stick.sourceHelp")).pickerStyle(
          SegmentedPickerStyle()
        )
        ScrollView {
          ProfileStickFields(draft: selected == .left ? $left : $right).padding(.trailing, 8)
        }
        if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        HStack {
          Button(OJDLocalized.string("action.reset")) {
            if selected == .left {
              left = ProfileStickDraft(source: .left, mapping: nil)
            } else {
              right = ProfileStickDraft(source: .right, mapping: nil)
            }
            errorMessage = nil
          }.help(OJDLocalized.string("ui.help.reset"))
          Spacer()
          Button(OJDLocalized.string("action.cancel")) {
            presentationMode.wrappedValue.dismiss()
          }.help(OJDLocalized.string("ui.help.cancel"))
          Button(OJDLocalized.string("action.save")) {
            do {
              let separator = Locale.current.decimalSeparator ?? "."
              let mappings = try [left, right].compactMap {
                try $0.validatedMapping(decimalSeparator: separator)
              }
              try onSave(mappings)
              presentationMode.wrappedValue.dismiss()
            } catch { errorMessage = RuntimePresentation.userFacingError(error) }
          }.help(OJDLocalized.string("ui.help.save"))
        }
      }.ojdSheet(.regular).frame(
        height: ProfilePresentationPolicy.optionalEditorHeight(
          enabled: selected == .left ? left.enabled : right.enabled,
          compact: 260,
          expanded: 600
        )
      )
    }
  }
#endif
