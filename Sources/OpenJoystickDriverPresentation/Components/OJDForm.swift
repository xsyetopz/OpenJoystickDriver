#if canImport(SwiftUI)

  import AppKit
  import SwiftUI

  extension View {
    /// The grouped form look on macOS 13 and later; macOS 12 shows the plain form, which does not
    /// scroll by itself and so sits in a scroll view.
    ///
    /// Every content form of the main window goes through this.
    @ViewBuilder
    func ojdGroupedForm() -> some View {
      if #available(macOS 13, *) {
        formStyle(.grouped)
      } else {
        ScrollView { self.padding() }
      }
    }
  }

  /// A label and its content as one form row: `LabeledContent` on macOS 13 and later, a label and
  /// trailing content on macOS 12.
  struct OJDLabeledRow<Content: View>: View {
    /// The label.
    let label: String
    /// The content, which sits at the trailing edge.
    let content: Content

    /// Creates the row with a label and its content.
    init(_ label: String, @ViewBuilder content: () -> Content) {
      self.label = label
      self.content = content()
    }

    /// The label and the content in a row; the system labeled content from macOS 13.
    var body: some View {
      if #available(macOS 13, *) {
        LabeledContent(label) { content }
      } else {
        HStack(alignment: .firstTextBaseline) {
          Text(label)
          Spacer(minLength: 8)
          content.multilineTextAlignment(.trailing)
        }
      }
    }
  }

  /// A label and its value as one form row.
  ///
  /// A missing value shows the "None" of ``OJDValue``.
  struct OJDLabeledValue: View {
    /// The label.
    let label: String
    /// The value.
    let value: OJDValue

    /// Creates the row from a label and a value.
    init(_ label: String, _ value: OJDValue) {
      self.label = label
      self.value = value
    }

    /// Creates the row from a label and an optional string, which is missing when it is nil or
    /// empty.
    init(_ label: String, _ value: String?) { self.init(label, OJDValue(value)) }

    /// The label with the text of the value in a secondary color.
    var body: some View {
      OJDLabeledRow(label) {
        OJDValueText(value: value).foregroundColor(Color(NSColor.secondaryLabelColor))
          .textSelection(.enabled)
      }
    }
  }

#endif
