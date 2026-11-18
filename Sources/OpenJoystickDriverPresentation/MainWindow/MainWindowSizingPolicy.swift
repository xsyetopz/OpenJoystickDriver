#if canImport(AppKit)

  import AppKit

  /// The size limits of the main window and its three columns.
  enum MainWindowSizingPolicy {
    /// The minimum and maximum width of the sidebar.
    static let sidebarWidth = (minimum: CGFloat(170), maximum: CGFloat(260))
    /// The minimum and maximum width of the content list column.
    static let listWidth = (minimum: CGFloat(200), maximum: CGFloat(320))
    /// The minimum width of the detail column.
    static let minimumDetailWidth: CGFloat = 420
    /// The content size of a new main window.
    static let defaultContentSize = NSSize(width: 1_040, height: 700)
    /// The smallest content height that the window allows.
    static let minimumContentHeight: CGFloat = 560

    /// Returns the smallest content width that fits the columns that show: the sum of their
    /// minimum widths, with `listMinimum` as the list column's.
    static func minimumContentWidth(
      showsSidebar: Bool,
      showsList: Bool,
      listMinimum: CGFloat = listWidth.minimum
    ) -> CGFloat {
      (showsSidebar ? sidebarWidth.minimum : 0) + (showsList ? listMinimum : 0)
        + minimumDetailWidth
    }

    /// Returns the smallest content size that fits the columns that show.
    static func minimumContentSize(
      showsSidebar: Bool,
      showsList: Bool,
      listMinimum: CGFloat = listWidth.minimum
    ) -> NSSize {
      NSSize(
        width: minimumContentWidth(
          showsSidebar: showsSidebar,
          showsList: showsList,
          listMinimum: listMinimum
        ),
        height: minimumContentHeight
      )
    }

    /// Returns the smallest frame size of `window` whose content area is
    /// ``minimumContentSize(showsSidebar:showsList:listMinimum:)``.
    @MainActor
    static func minimumFrameSize(
      for window: NSWindow,
      showsSidebar: Bool,
      showsList: Bool,
      listMinimum: CGFloat = listWidth.minimum
    )
      -> NSSize
    {
      let content = minimumContentSize(
        showsSidebar: showsSidebar,
        showsList: showsList,
        listMinimum: listMinimum
      )
      return window.frameRect(forContentRect: NSRect(origin: .zero, size: content)).size
    }
  }

#endif
