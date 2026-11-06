#if os(macOS)
  import CoreGraphics
  import Foundation
  import OpenJoystickDriverKit

  /// The sections of the profile editor.
  enum ProfileEditorSection: String, CaseIterable, Identifiable {
    /// The assignments of the profile.
    case assignments
    /// The chords and sequences.
    case combinations
    /// The layers.
    case layers
    /// The controller's details, output policy and settings.
    case controller

    /// The section itself.
    var id: Self { self }

    /// The title in the section picker.
    var title: String {
      switch self {
      case .assignments: return OJDLocalized.string("term.assignments")
      case .combinations:
        return OJDLocalized.string("ui.profiles.combinations")
      case .layers: return OJDLocalized.string("ui.profiles.layers")
      case .controller: return OJDLocalized.string("term.controller")
      }
    }
  }

  /// How the editor shows the section picker.
  enum ProfileEditorNavigationStyle: Equatable {
    /// A segmented control.
    case segmented
    /// A pop-up menu.
    case popUp
  }

  /// How an assignment row lays out its pickers.
  enum ProfileAssignmentRowLayout: Equatable {
    /// The pickers sit side by side.
    case inline
    /// The pickers sit one above the other.
    case stacked
  }

  /// The sizes and orders of the profile editor.
  enum ProfilePresentationPolicy {
    /// The sections in the order the picker lists them.
    static let sectionOrder = ProfileEditorSection.allCases
    /// The section the editor opens on.
    static let defaultSection = ProfileEditorSection.assignments
    /// The width below which the section picker is a pop-up menu.
    static let compactNavigationWidth: CGFloat = 620
    /// The width below which the pickers of an assignment sit one above the other.
    static let inlineAssignmentWidth: CGFloat = 680

    /// Returns the height of a sheet whose fields show only when its setting is enabled.
    ///
    /// - Parameters:
    ///   - enabled: Whether the setting is enabled.
    ///   - compact: The height when disabled.
    ///   - expanded: The height when enabled.
    /// - Returns: The height of a sheet whose fields show only when its setting is enabled.
    static func optionalEditorHeight(enabled: Bool, compact: CGFloat, expanded: CGFloat) -> CGFloat
    { enabled ? expanded : compact }

    /// Returns the section picker style for an editor of `width`.
    static func navigationStyle(for width: CGFloat) -> ProfileEditorNavigationStyle {
      width < compactNavigationWidth ? .popUp : .segmented
    }

    /// Returns the assignment row layout for an editor of `width`.
    static func assignmentRowLayout(for width: CGFloat) -> ProfileAssignmentRowLayout {
      width < inlineAssignmentWidth ? .stacked : .inline
    }
  }

#endif
