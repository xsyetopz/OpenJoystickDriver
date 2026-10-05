#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileStickSheet: View {
    let onSave: ([RemappingStickMapping]) throws -> Void
    @Environment(\.presentationMode)
    private var presentationMode
    @State
    private var left: ProfileStickDraft
    @State
    private var right: ProfileStickDraft
    @State
    private var selected: RemappingStickSource = .left
    @State
    private var errorMessage: String?

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

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(OJDLocalized.string("profiles.stick.title")).font(.headline)
        Picker(
          OJDLocalized.string("profiles.stick.source"),
          selection: $selected
        ) {
          Text(OJDLocalized.string("profiles.gyro.leftStick")).tag(
            RemappingStickSource.left
          )
          Text(OJDLocalized.string("profiles.gyro.rightStick")).tag(
            RemappingStickSource.right
          )
        }.pickerStyle(SegmentedPickerStyle())
        ScrollView {
          ProfileStickFields(draft: selected == .left ? $left : $right).padding(.trailing, 8)
        }
        if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        HStack {
          Button(OJDLocalized.string("common.reset")) {
            if selected == .left {
              left = ProfileStickDraft(source: .left, mapping: nil)
            } else {
              right = ProfileStickDraft(source: .right, mapping: nil)
            }
            errorMessage = nil
          }
          Spacer()
          Button(OJDLocalized.string("common.cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("common.save")) {
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
      }.padding(28).frame(
        width: 500,
        height: ProfilePresentationPolicy.optionalEditorHeight(
          enabled: selected == .left ? left.enabled : right.enabled,
          compact: 260,
          expanded: 600
        )
      )
    }
  }
#endif
