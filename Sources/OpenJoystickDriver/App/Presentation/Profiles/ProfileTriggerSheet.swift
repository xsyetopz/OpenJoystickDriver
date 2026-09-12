#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileTriggerSheet: View {
    let onSave: ([RemappingTriggerMapping]) throws -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var left: ProfileTriggerDraft
    @State private var right: ProfileTriggerDraft
    @State private var selected: RemappingTriggerSource = .left
    @State private var errorMessage: String?

    init(
      mappings: [RemappingTriggerMapping],
      onSave: @escaping ([RemappingTriggerMapping]) throws -> Void
    ) {
      self.onSave = onSave
      _left = State(initialValue: ProfileTriggerDraft(
        source: .left, mapping: mappings.first { $0.source == .left }
      ))
      _right = State(initialValue: ProfileTriggerDraft(
        source: .right, mapping: mappings.first { $0.source == .right }
      ))
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(OJDLocalized.string("profiles.trigger.title", fallback: "Trigger stages"))
          .font(.headline)
        Picker(
          OJDLocalized.string("profiles.trigger.source", fallback: "Trigger"), selection: $selected
        ) {
          Text(OJDLocalized.string("profiles.trigger.left", fallback: "Left trigger"))
            .tag(RemappingTriggerSource.left)
          Text(OJDLocalized.string("profiles.trigger.right", fallback: "Right trigger"))
            .tag(RemappingTriggerSource.right)
        }.pickerStyle(SegmentedPickerStyle())
        ScrollView {
          ProfileTriggerFields(draft: selected == .left ? $left : $right).padding(.trailing, 8)
        }
        if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        HStack {
          Button(OJDLocalized.string("common.reset", fallback: "Reset")) {
            if selected == .left {
              left = ProfileTriggerDraft(source: .left, mapping: nil)
            } else {
              right = ProfileTriggerDraft(source: .right, mapping: nil)
            }
            errorMessage = nil
          }
          Spacer()
          Button(OJDLocalized.string("common.cancel", fallback: "Cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("common.save", fallback: "Save")) {
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
      }.padding(28).frame(width: 500, height: 560)
    }
  }
#endif
