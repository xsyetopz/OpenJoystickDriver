import Foundation
import OpenJoystickDriverKit

/// Reads and writes the vendor and product IDs the person types.
enum ProfileIdentifierInput {
  /// Returns the ID in `rawValue`, decimal or hexadecimal with a `0x` prefix, or nil when it is
  /// neither.
  static func parse(_ rawValue: String) -> UInt16? {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.lowercased().hasPrefix("0x") { return UInt16(value.dropFirst(2), radix: 16) }
    return UInt16(value, radix: 10)
  }

  /// Returns `value` as `0x` and four hexadecimal digits.
  static func formatted(_ value: UInt16) -> String { unsafe String(format: "0x%04X", value) }
}

/// Whether a profile applies to every app or to one app.
enum ProfileScopeKind: String, CaseIterable, Identifiable {
  /// The profile applies to every app.
  case global
  /// The profile applies to one app.
  case application

  /// The raw value, which identifies the kind.
  var id: String { rawValue }

  /// Creates the kind of an application scope.
  init(_ scope: RemappingApplicationScope) {
    switch scope {
    case .global: self = .global
    case .application: self = .application
    }
  }
}

/// A source the source pickers list, with its title and whether the controller supports it.
struct SourceOption: Hashable {
  /// The source.
  let source: RemappingSource
  /// The title in the picker.
  let title: String
  /// Whether the controller supports the source.
  let isSupported: Bool

  /// Returns the sources the controller supports, and `current` when it is not among them, as
  /// unsupported or supported by what `capabilities` says.
  ///
  /// - Parameters:
  ///   - current: The source to keep in the list.
  ///   - capabilities: What the controller has; nil means every source is supported.
  /// - Returns: The sources the controller supports, and `current` when it is not among them, as
  ///   unsupported or supported by what `capabilities` says.
  static func options(
    including current: RemappingSource? = nil,
    capabilities: ControllerProfileCapabilities? = nil
  ) -> [Self] {
    var options = all.filter {
      ProfileCapabilityPolicy.supports($0.source, capabilities: capabilities)
    }
    if let current, !options.contains(where: { $0.source == current }) {
      options.append(
        Self(
          source: current,
          title: RuntimePresentation.sourceLabel(current),
          isSupported: ProfileCapabilityPolicy.supports(current, capabilities: capabilities)
        )
      )
    }
    return options
  }

  /// Every source the pickers know: the buttons but Guide, the pad directions, the axes and their
  /// directions, the trigger stages, the lean directions, and the contact, swipes and 2 by 2 grid
  /// cells of each touch surface.
  static let all: [Self] = {
    let buttons: [RemappingSource] = Control.allCases.compactMap { button in
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
      .init(source: $0, title: RuntimePresentation.sourceLabel($0), isSupported: true)
    }
  }()
}
