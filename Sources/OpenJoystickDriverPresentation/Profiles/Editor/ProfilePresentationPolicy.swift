#if os(macOS)
  import CoreGraphics
  import Foundation
  import OpenJoystickDriverKit

  enum ProfileEditorSection: String, CaseIterable, Identifiable {
    case assignments
    case combinations
    case layers
    case controller

    var id: Self { self }

    var title: String {
      switch self {
      case .assignments: return OJDLocalized.string("common.assignments")
      case .combinations:
        return OJDLocalized.string("profiles.combinations")
      case .layers: return OJDLocalized.string("profiles.layers")
      case .controller: return OJDLocalized.string("common.controller")
      }
    }
  }

  enum ProfileEditorNavigationStyle: Equatable {
    case segmented
    case popUp
  }

  enum ProfileAssignmentRowLayout: Equatable {
    case inline
    case stacked
  }

  enum ProfilePresentationPolicy {
    static let sectionOrder = ProfileEditorSection.allCases
    static let defaultSection = ProfileEditorSection.assignments
    static let compactNavigationWidth: CGFloat = 620
    static let inlineAssignmentWidth: CGFloat = 680

    static func optionalEditorHeight(enabled: Bool, compact: CGFloat, expanded: CGFloat) -> CGFloat
    { enabled ? expanded : compact }

    static func navigationStyle(for width: CGFloat) -> ProfileEditorNavigationStyle {
      width < compactNavigationWidth ? .popUp : .segmented
    }

    static func assignmentRowLayout(for width: CGFloat) -> ProfileAssignmentRowLayout {
      width < inlineAssignmentWidth ? .stacked : .inline
    }
  }

  enum WorkspaceListDetailLayout: Equatable {
    case stacked
    case sideBySide
  }

  enum WorkspaceListDetailPolicy {
    static let minimumListWidth: CGFloat = 200
    static let idealListWidth: CGFloat = 220
    static let maximumListWidth: CGFloat = 240
    static let minimumDetailWidth: CGFloat = 600
    static let dividerWidth: CGFloat = 1
    static let compactListMaximumHeight: CGFloat = 200

    static func compactListHeight(itemCount: Int, availableHeight: CGFloat) -> CGFloat {
      let contentHeight = 52 + CGFloat(max(1, itemCount)) * 44
      return min(contentHeight, compactListMaximumHeight, availableHeight * 0.34)
    }

    static func layout(for width: CGFloat) -> WorkspaceListDetailLayout {
      width >= minimumListWidth + dividerWidth + minimumDetailWidth ? .sideBySide : .stacked
    }

    static func listWidth(for width: CGFloat) -> CGFloat {
      min(maximumListWidth, max(minimumListWidth, width - dividerWidth - minimumDetailWidth))
    }
  }

  enum ControllerDetailLayoutPolicy {
    static let twoColumnMinimumWidth: CGFloat = 560

    static func factColumnCount(for width: CGFloat) -> Int { width < twoColumnMinimumWidth ? 1 : 2 }
  }
#endif
