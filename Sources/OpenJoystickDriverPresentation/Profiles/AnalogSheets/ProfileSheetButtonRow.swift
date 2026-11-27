#if os(macOS)
  import SwiftUI

  /// The Reset, Cancel and Save buttons of an analog profile sheet.
  ///
  /// Optional buttons sit between Reset and Cancel. Escape chooses Cancel, which dismisses the
  /// sheet, and Return chooses Save.
  struct ProfileSheetButtonRow<Extra: View>: View {
    /// Restores the defaults of the edited fields.
    let reset: () -> Void
    /// Validates and saves the edit.
    let save: () -> Void
    /// The buttons after Reset.
    private let extra: Extra
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - reset: Restores the defaults of the edited fields.
    ///   - save: Validates and saves the edit.
    ///   - extra: The buttons after Reset.
    init(
      reset: @escaping () -> Void,
      save: @escaping () -> Void,
      @ViewBuilder extra: () -> Extra
    ) {
      self.reset = reset
      self.save = save
      self.extra = extra()
    }

    /// Reset and the extra buttons on the leading side, Cancel and Save on the trailing side.
    var body: some View {
      HStack {
        Button(OJDLocalized.string("action.reset"), action: reset).help(
          OJDLocalized.string("ui.help.reset")
        )
        extra
        Spacer()
        Button(OJDLocalized.string("action.cancel")) {
          presentationMode.wrappedValue.dismiss()
        }.keyboardShortcut(.cancelAction).help(OJDLocalized.string("ui.help.cancelSheet"))
        Button(OJDLocalized.string("action.save"), action: save).keyboardShortcut(.defaultAction)
          .help(OJDLocalized.string("ui.help.save"))
      }
    }
  }

  extension ProfileSheetButtonRow where Extra == EmptyView {
    /// Creates the row with Reset, Cancel and Save only.
    ///
    /// - Parameters:
    ///   - reset: Restores the defaults of the edited fields.
    ///   - save: Validates and saves the edit.
    init(reset: @escaping () -> Void, save: @escaping () -> Void) {
      self.init(reset: reset, save: save) { EmptyView() }
    }
  }
#endif
