import AppKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct MainWindowSizingTests {
  @Test
  func minimumWidthOfThreeColumnsSumOfTheirMinimums() {
    let width = MainWindowSizingPolicy.minimumContentWidth(showsSidebar: true, showsList: true)
    #expect(
      width
        == MainWindowSizingPolicy.sidebarWidth.minimum + MainWindowSizingPolicy.listWidth.minimum
        + MainWindowSizingPolicy.minimumDetailWidth
    )
    #expect(width == 790)
  }

  @Test
  func hiddenSidebarLeavesOutItsMinimum() {
    #expect(MainWindowSizingPolicy.minimumContentWidth(showsSidebar: false, showsList: true) == 620)
    #expect(
      MainWindowSizingPolicy.minimumContentWidth(showsSidebar: false, showsList: false) == 420
    )
  }

  @Test
  func areaWithoutListLeavesOutListMinimum() {
    #expect(MainWindowSizingPolicy.minimumContentWidth(showsSidebar: true, showsList: false) == 590)
  }

  @Test
  func minimumContentSizeKeepsHeightAndFitsDefault() {
    let size = MainWindowSizingPolicy.minimumContentSize(showsSidebar: true, showsList: true)
    #expect(size == NSSize(width: 790, height: 560))
    #expect(MainWindowSizingPolicy.defaultContentSize.width >= size.width)
  }

  @Test
  @MainActor
  func frameMinimumConvertsBackToContentMinimumOfShownColumns() {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: MainWindowSizingPolicy.defaultContentSize),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.toolbar = NSToolbar(identifier: "SizingPolicyTest")
    for (sidebar, list) in [(true, true), (false, true), (true, false)] {
      let frame = MainWindowSizingPolicy.minimumFrameSize(
        for: window,
        showsSidebar: sidebar,
        showsList: list
      )
      let content = window.contentRect(forFrameRect: NSRect(origin: .zero, size: frame)).size
      #expect(
        content == MainWindowSizingPolicy.minimumContentSize(showsSidebar: sidebar, showsList: list)
      )
    }
  }
}
