#if canImport(SwiftUI)

  import AppKit
  import SwiftUI

  /// The layout shared by the profile sheets: a title, optional help text, the content, an
  /// optional error and a row of footer buttons.
  struct ProfileSheetScaffold<Content: View, Footer: View>: View {
    /// The title.
    let title: String
    /// The help text, or nil.
    let help: String?
    /// The error text, or nil.
    let error: String?
    /// The content.
    private let content: Content
    /// The footer buttons.
    private let footer: Footer

    /// Creates the scaffold.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - help: The help text, or nil.
    ///   - error: The error text, or nil.
    ///   - content: The content.
    ///   - footer: The footer buttons.
    init(
      title: String,
      help: String? = nil,
      error: String? = nil,
      @ViewBuilder content: () -> Content,
      @ViewBuilder footer: () -> Footer
    ) {
      self.title = title
      self.help = help
      self.error = error
      self.content = content()
      self.footer = footer()
    }

    /// The scaffold.
    var body: some View {
      VStack(alignment: .leading, spacing: 15) {
        Text(title).font(.headline.weight(.semibold))
        if let help {
          Text(help).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        content
        if let error {
          Text(error).font(.body).foregroundColor(Color(NSColor.systemRed)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        HStack(spacing: 10) { footer }
      }.padding(28).frame(minWidth: 390, idealWidth: 440, maxWidth: 520)
    }
  }

#endif
