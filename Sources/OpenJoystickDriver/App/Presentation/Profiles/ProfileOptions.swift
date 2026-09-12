import Foundation
import OpenJoystickDriverKit

enum ProfileIdentifierInput {
  static func parse(_ rawValue: String) -> UInt16? {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.lowercased().hasPrefix("0x") { return UInt16(value.dropFirst(2), radix: 16) }
    return UInt16(value, radix: 10)
  }

  static func formatted(_ value: UInt16) -> String { String(format: "0x%04X", value) }
}

enum ProfileScopeKind: String, CaseIterable, Identifiable {
  case global
  case application

  var id: String { rawValue }

  init(_ scope: RemappingApplicationScope) {
    switch scope {
    case .global: self = .global
    case .application: self = .application
    }
  }
}

struct SourceOption: Hashable {
  let source: RemappingSource
  let title: String

  static func options(including current: RemappingSource? = nil) -> [Self] {
    var options = all
    if let current, !options.contains(where: { $0.source == current }) {
      options.append(Self(source: current, title: RuntimePresentation.sourceLabel(current)))
    }
    return options
  }

  static let all: [Self] = {
    let buttons: [RemappingSource] = RemappingButton.allCases.compactMap { button in
      guard button != .guide else { return nil }
      return .button(button)
    }
    let dpad: [RemappingSource] = RemappingDpadDirection.allCases.map { .dpad($0) }
    let axes: [RemappingSource] = RemappingAxis.allCases.flatMap { axis in
      [.axis(axis), .axisDirection(axis, .negative), .axisDirection(axis, .positive)]
    }
    let triggerStages: [RemappingSource] = RemappingTriggerSource.allCases.flatMap { trigger in
      RemappingTriggerStage.allCases.map { .triggerStage(trigger, $0) }
    }
    let motionLean = RemappingMotionLeanDirection.allCases.map(RemappingSource.motionLean)
    let touches: [RemappingSource] = RemappingTouchSurface.allCases.flatMap { surface in
      let contact: [RemappingSource] = [.touchContact(surface)]
      let swipes = RemappingTouchSwipeDirection.allCases.map {
        RemappingSource.touchSwipe(RemappingTouchSwipeSource(surface: surface, direction: $0))
      }
      let grid = (0..<2).flatMap { row in
        (0..<2).map { column in
          RemappingSource.touchGrid(
            RemappingTouchGridSource(
              surface: surface,
              columns: 2,
              rows: 2,
              column: column,
              row: row
            )
          )
        }
      }
      return contact + swipes + grid
    }
    return (buttons + dpad + axes + triggerStages + motionLean + touches).map {
      .init(source: $0, title: RuntimePresentation.sourceLabel($0))
    }
  }()
}
