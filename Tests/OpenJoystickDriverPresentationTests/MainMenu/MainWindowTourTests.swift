import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct MainWindowTourTests {
  @Test
  func hasOneStepPerAreaInSidebarOrder() {
    #expect(MainWindowTour().steps.map(\.area) == MainWindowArea.allCases)
  }

  @Test
  func eachStepNamesItsAreaTitleAndSummary() {
    for step in MainWindowTour().steps {
      #expect(step.titleKey == step.area.titleKey)
      #expect(step.summaryKey == "ui.tour.\(step.area.rawValue).summary")
    }
  }

  @Test
  func walksForwardAndBackAndStopsAtEnds() {
    var tour = MainWindowTour()
    tour.back()
    #expect(tour.isFirst)
    for _ in 0..<10 { tour.next() }
    #expect(tour.isLast)
    #expect(tour.current.area == MainWindowArea.allCases.last)
    tour.back()
    #expect(tour.current.area == MainWindowArea.allCases[MainWindowArea.allCases.count - 2])
  }

  @Test
  func offersNextBackAndDoneWhereTheyApply() {
    var tour = MainWindowTour()
    #expect(tour.choices == [.next, .done])
    tour.next()
    #expect(tour.choices == [.next, .back, .done])
    for _ in 0..<10 { tour.next() }
    #expect(tour.choices == [.back, .done])
  }

  @Test
  func helpMenuHoldsTour() throws {
    let help = try #require(MainMenuModel.sections.first { $0.id == "help" })
    let item = try #require(help.items.first { $0.action == .showMainWindowTour })
    #expect(item.titleKey == "ui.menu.help.mainWindowTour")
  }
}
