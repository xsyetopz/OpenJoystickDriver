#if canImport(SwiftUI)

  import SwiftUI

  /// The spacing values views use between and around their content, in points.
  enum OJDSpacing {
    /// No space.
    static let none: CGFloat = 0
    /// The gap between a title and its own detail.
    static let xxSmall: CGFloat = 2
    /// The gap inside a tight group.
    static let xSmall: CGFloat = 4
    /// The gap between related controls.
    static let small: CGFloat = 8
    /// The gap between rows of a form.
    static let medium: CGFloat = 12
    /// The gap between sections.
    static let large: CGFloat = 16
    /// The gap around the content of a sheet.
    static let xLarge: CGFloat = 24

    /// The padding around the content of every sheet.
    static let sheetPadding = xLarge

    /// Every value of the scale, smallest first.
    static let scale = [none, xxSmall, xSmall, small, medium, large, xLarge]
  }

  /// The three widths a sheet has, in points.
  enum OJDSheetWidth: CGFloat, CaseIterable {
    /// A confirmation or a form of a few fields.
    case compact = 420
    /// A form with several sections.
    case regular = 480
    /// A form with a table of rows.
    case wide = 520
  }

  extension View {
    /// Pads the sheet's content by the sheet padding and fixes its width to `width`.
    func ojdSheet(_ width: OJDSheetWidth) -> some View {
      padding(OJDSpacing.sheetPadding).frame(width: width.rawValue)
    }
  }

#endif
