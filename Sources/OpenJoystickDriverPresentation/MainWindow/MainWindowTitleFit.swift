#if canImport(AppKit)

  import AppKit

  /// Keeps the window title and subtitle inside the list column.
  ///
  /// AppKit draws them right after the sidebar toggle whatever the column widths, so with the
  /// sidebar hidden they would run past a narrow list column.
  enum MainWindowTitleFit {
    /// The space between the end of the title or subtitle and the list column's divider.
    static let margin: CGFloat = 12

    /// The trailing edges, in window coordinates, of the title and subtitle that `window` draws.
    @MainActor
    static func textEdges(of window: NSWindow) -> [CGFloat] {
      guard let titlebar = unsafe window.standardWindowButton(.closeButton)?.superview?.superview
      else {
        return []
      }
      let texts = Set([window.title, window.subtitle].filter { !$0.isEmpty })
      return fields(in: titlebar).filter { texts.contains($0.stringValue) }.map {
        $0.convert($0.bounds, to: nil).maxX
      }
    }

    @MainActor
    private static func fields(in view: NSView) -> [NSTextField] {
      view.subviews.flatMap { subview in
        ((subview as? NSTextField).map { [$0] } ?? []) + fields(in: subview)
      }
    }

    /// Widens the minimum of `list` so the title and subtitle of `window` end inside it.
    ///
    /// Returns whether the minimum changed.
    @MainActor
    static func fit(_ list: NSSplitViewItem, in window: NSWindow) -> Bool {
      guard !list.isCollapsed else { return false }
      window.layoutIfNeeded()
      guard let edge = textEdges(of: window).max() else { return false }
      let listStart = list.viewController.view.convert(NSPoint.zero, to: nil).x
      let minimum = max(MainWindowSizingPolicy.listWidth.minimum, edge - listStart + margin)
      guard minimum != list.minimumThickness else { return false }
      list.maximumThickness = max(MainWindowSizingPolicy.listWidth.maximum, minimum)
      list.minimumThickness = minimum
      return true
    }
  }

#endif
