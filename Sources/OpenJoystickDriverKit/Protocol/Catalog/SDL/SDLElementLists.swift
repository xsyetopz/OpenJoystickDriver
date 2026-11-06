import Foundation

/// The three lists SDL's IOKit joystick backend builds from a device's elements, which the
/// `a#`, `h#.#` and `b#` indexes of an SDL_GameControllerDB line point into.
///
/// Each list is sorted ascending by usage number alone, across pages. Elements with one usage keep
/// arrival order, and an element that repeats a cookie already in the list is dropped.
struct SDLElementLists: Equatable, Sendable {
  /// Generic Desktop X, Y, Z, Rx, Ry, Rz, Slider, Dial and Wheel, then Simulation Rudder,
  /// Throttle, Accelerator and Brake.
  let axes: [HIDElementDescription]
  /// Generic Desktop Hat Switch.
  let hats: [HIDElementDescription]
  /// The Button page, the Consumer page, then Generic Desktop D-pad, Start, Select and System Main
  /// Menu.
  let buttons: [HIDElementDescription]

  /// The list an element belongs to.
  private enum Kind {
    /// An element of ``axes``.
    case axis
    /// An element of ``hats``.
    case hat
    /// An element of ``buttons``.
    case button
  }

  /// Builds the lists from `elements`, in any order.
  init(elements: [HIDElementDescription]) {
    var lists: [Kind: [HIDElementDescription]] = [:]
    var cookies: [Kind: Set<UInt32>] = [:]
    for element in elements.sorted(by: { $0.arrivalOrder < $1.arrivalOrder }) {
      guard let kind = Self.kind(of: element),
        cookies[kind, default: []].insert(element.cookie).inserted
      else { continue }
      lists[kind, default: []].append(element)
    }
    func sorted(_ kind: Kind) -> [HIDElementDescription] {
      lists[kind, default: []].sorted { ($0.usage, $0.arrivalOrder) < ($1.usage, $1.arrivalOrder) }
    }
    axes = sorted(.axis)
    hats = sorted(.hat)
    buttons = sorted(.button)
  }

  /// The list of `element`, or nil for an element SDL ignores.
  private static func kind(of element: HIDElementDescription) -> Kind? {
    switch (element.usagePage, element.usage) {
    case (0x01, 0x30...0x38), (0x02, 0xBA), (0x02, 0xBB), (0x02, 0xC4), (0x02, 0xC5): .axis
    case (0x01, 0x39): .hat
    case (0x09, _), (0x0C, _), (0x01, 0x90...0x93), (0x01, 0x3D), (0x01, 0x3E), (0x01, 0x85):
      .button
    default: nil
    }
  }
}
