import Foundation

/// The tour of the main window, which Help > Tour of the Main Window shows.
///
/// It has one step per `MainWindowArea`, in sidebar order, and moves between them with `next()` and
/// `back()`.
struct MainWindowTour: Equatable, Sendable {
  /// One step of the tour: the area it explains.
  struct Step: Equatable, Sendable {
    /// The area this step is about.
    let area: MainWindowArea

    /// The localization key of the step's title, which is the title of its area.
    var titleKey: String { area.titleKey }

    /// The localization key of the sentence that says what the area is for.
    var summaryKey: String { "ui.tour.\(area.rawValue).summary" }
  }

  /// What a person chooses at a step.
  enum Choice: Equatable, Sendable {
    /// Go to the next step.
    case next
    /// Go to the previous step.
    case back
    /// End the tour.
    case done
  }

  /// The steps, one per area in sidebar order.
  let steps: [Step] = MainWindowArea.allCases.map { Step(area: $0) }

  /// The index of the step in view.
  private(set) var index = 0

  /// The step in view.
  var current: Step { steps[index] }

  /// Whether no step comes before the one in view.
  var isFirst: Bool { index == 0 }

  /// Whether no step comes after the one in view.
  var isLast: Bool { index == steps.count - 1 }

  /// The choices the step in view offers, in button order: Next unless it is the last step, Back
  /// unless it is the first, and Done always.
  var choices: [Choice] {
    var result: [Choice] = []
    if !isLast { result.append(.next) }
    if !isFirst { result.append(.back) }
    result.append(.done)
    return result
  }

  /// Moves to the next step.
  ///
  /// It stays on the last step.
  mutating func next() {
    if !isLast { index += 1 }
  }

  /// Moves to the previous step.
  ///
  /// It stays on the first step.
  mutating func back() {
    if !isFirst { index -= 1 }
  }
}
