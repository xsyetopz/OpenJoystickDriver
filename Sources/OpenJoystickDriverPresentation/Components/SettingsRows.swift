#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The large title of a page, with an optional line of secondary text under it.
  struct PageHeader: View {
    /// The title text.
    let title: String
    /// The secondary text, or nil for none.
    let subtitle: String?

    /// Creates the header with a title and an optional subtitle.
    init(title: String, subtitle: String? = nil) {
      self.title = title
      self.subtitle = subtitle
    }

    /// The title with the subtitle, when there is one.
    var body: some View {
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.largeTitle.weight(.semibold))
        if let subtitle {
          Text(subtitle).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
      }
    }
  }

#endif
