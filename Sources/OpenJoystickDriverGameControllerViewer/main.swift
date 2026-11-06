import AppKit
import GameController
import SwiftUI

// Shows every input element that Apple's GameController framework reports for each connected
// controller, with its current value, and prints each change as one JSON line on standard output.
// It reads controllers only through GameController, so what it shows is what GameController games
// receive. It turns off the Home and Share system gestures, which macOS otherwise keeps for itself.

/// One change of one element, printed as a JSON line.
struct ElementChange: Encodable {
  /// The time of the change in milliseconds since 1970.
  let time: Int
  /// The controller name.
  let controller: String
  /// The element name.
  let element: String
  /// Whether a button is pressed; nil for other elements.
  let pressed: Bool?
  /// The value of a button or an axis; nil for other elements.
  let value: Float?
  /// The horizontal value of a direction pad; nil for other elements.
  let x: Float?
  /// The vertical value of a direction pad; nil for other elements.
  let y: Float?
}

/// The value of an element as the window shows it and the JSON line carries it.
func change(of element: GCControllerElement, on controller: String) -> ElementChange? {
  let name = element.localizedName ?? element.aliases.min() ?? "Element"
  let time = Int(Date().timeIntervalSince1970 * 1000)
  switch element {
  case let button as GCControllerButtonInput:
    return ElementChange(
      time: time,
      controller: controller,
      element: name,
      pressed: button.isPressed,
      value: button.value,
      x: nil,
      y: nil
    )
  case let axis as GCControllerAxisInput:
    return ElementChange(
      time: time,
      controller: controller,
      element: name,
      pressed: nil,
      value: axis.value,
      x: nil,
      y: nil
    )
  case let pad as GCControllerDirectionPad:
    return ElementChange(
      time: time,
      controller: controller,
      element: name,
      pressed: nil,
      value: nil,
      x: pad.xAxis.value,
      y: pad.yAxis.value
    )
  default:
    return nil
  }
}

/// The value text of an element.
///
/// Adding zero turns -0 into 0.
func describe(_ change: ElementChange) -> String {
  if let x = change.x, let y = change.y {
    return String(format: "x %+.2f  y %+.2f", x + 0, y + 0)
  }
  let pressed = change.pressed == true ? "  pressed" : ""
  return String(format: "%.2f%@", (change.value ?? 0) + 0, pressed)
}

/// The controls of a controller in layout order: face buttons, shoulders, the system buttons,
/// the stick clicks, the D-pad, the sticks, then paddles.
@MainActor
func layoutOrder(of controller: GCController) -> [GCControllerElement] {
  guard let pad = controller.extendedGamepad else { return [] }
  var elements: [GCControllerElement?] = [
    pad.buttonA, pad.buttonB, pad.buttonX, pad.buttonY, pad.leftShoulder, pad.rightShoulder,
    pad.leftTrigger, pad.rightTrigger, pad.buttonOptions, pad.buttonMenu, pad.buttonHome,
  ]
  if let xbox = pad as? GCXboxGamepad {
    elements += [xbox.buttonShare]
  }
  elements += [pad.leftThumbstickButton, pad.rightThumbstickButton, pad.dpad]
  elements += [pad.leftThumbstick, pad.rightThumbstick]
  if let xbox = pad as? GCXboxGamepad {
    elements += [xbox.paddleButton1, xbox.paddleButton2, xbox.paddleButton3, xbox.paddleButton4]
  }
  return elements.compactMap { $0 }
}

/// One connected controller: its controls in layout order, and every other element that
/// GameController lists, such as the directions of a D-pad and the raw axes.
struct ControllerRow: Identifiable {
  /// The identity of the controller object.
  let id: ObjectIdentifier
  /// The controller name.
  let name: String
  /// The controls in layout order.
  let controls: [ElementChange]
  /// Every other element that GameController lists.
  let others: [ElementChange]
}

/// The state that the window shows: the controllers and which of their groups are open.
@MainActor
final class ViewerModel: ObservableObject {
  /// The connected controllers.
  @Published
  var controllers: [ControllerRow] = []
  /// The controllers whose control list is closed.
  @Published
  var collapsed: Set<ObjectIdentifier> = []
  /// The controllers whose list of other elements is open.
  @Published
  var othersShown: Set<ObjectIdentifier> = []

  /// Whether `id` is in `set`, as a binding that adds or removes it.
  func member(
    _ id: ObjectIdentifier,
    of set: ReferenceWritableKeyPath<ViewerModel, Set<ObjectIdentifier>>,
    inverted: Bool
  ) -> Binding<Bool> {
    Binding(
      get: { self[keyPath: set].contains(id) != inverted },
      set: { value in
        if value != inverted {
          self[keyPath: set].insert(id)
        } else {
          self[keyPath: set].remove(id)
        }
      }
    )
  }
}

/// A group whose whole title toggles it, not only its arrow.
struct ElementGroup<Footer: View>: View {
  /// The title of the group.
  let title: String
  /// The elements of the group.
  let elements: [ElementChange]
  /// Whether the group is open.
  let expanded: Binding<Bool>
  /// Whether the title is bold.
  let bold: Bool
  /// The content that follows the elements.
  @ViewBuilder
  let footer: () -> Footer

  /// The disclosure group with one row per element.
  var body: some View {
    DisclosureGroup(isExpanded: expanded) {
      ForEach(elements, id: \.element) { element in
        HStack {
          Text(element.element)
          Spacer()
          Text(describe(element)).foregroundColor(
            element.pressed == true ? .accentColor : .secondary
          )
        }
        .font(.system(.body, design: .monospaced))
      }
      footer()
    } label: {
      Text(title).fontWeight(bold ? .bold : .regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { expanded.wrappedValue.toggle() }
    }
  }
}

/// The window content: one group per controller, or a hint when none is connected.
struct ViewerView: View {
  /// The state that the view shows.
  @ObservedObject
  var model: ViewerModel

  /// The list of controllers, or a hint when none is connected.
  var body: some View {
    if model.controllers.isEmpty {
      Text("No controller. Connect one.").frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      List(model.controllers) { controller in
        ElementGroup(
          title: controller.name,
          elements: controller.controls,
          expanded: model.member(controller.id, of: \.collapsed, inverted: true),
          bold: true
        ) {
          ElementGroup(
            title: "Other elements",
            elements: controller.others,
            expanded: model.member(controller.id, of: \.othersShown, inverted: false),
            bold: false
          ) { EmptyView() }
        }
      }
    }
  }
}

/// The application delegate: opens the window, attaches the connected controllers and prints
/// each change.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// The state that the window shows.
  private let model = ViewerModel()
  /// The window of the viewer.
  private var window: NSWindow?
  /// The observers of the controller connection notifications.
  private var observers: [NSObjectProtocol] = []
  /// The encoder of the JSON lines.
  private let encoder = JSONEncoder()

  /// Opens the window and starts to follow the controllers.
  func applicationDidFinishLaunching(_ notification: Notification) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "GameController Input Viewer"
    window.contentView = NSHostingView(rootView: ViewerView(model: model))
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApp.activate(ignoringOtherApps: true)

    // Notifications and GameController handlers all run on the main queue.
    GCController.shouldMonitorBackgroundEvents = true
    // GameController posts a notification for each change; the handler reads the current list.
    observers = [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect].map {
      NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { self.attachControllers() }
      }
    }
    attachControllers()
  }

  /// Ends the viewer when the window closes.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  /// Attaches every connected controller and refreshes the element list.
  private func attachControllers() {
    for controller in GCController.controllers() {
      let name = "\(controller.vendorName ?? "Controller") (\(controller.productCategory))"
      let profile = controller.physicalInputProfile
      for element in profile.allElements {
        if element.isBoundToSystemGesture { element.preferredSystemGestureState = .disabled }
        let report = { MainActor.assumeIsolated { self.report(element, on: name) } }
        switch element {
        case let button as GCControllerButtonInput:
          button.valueChangedHandler = { _, _, _ in report() }
        case let axis as GCControllerAxisInput:
          axis.valueChangedHandler = { _, _ in report() }
        case let pad as GCControllerDirectionPad:
          pad.valueChangedHandler = { _, _, _ in report() }
        default:
          break
        }
      }
    }
    redraw()
  }

  /// Prints the element's value as a JSON line and refreshes the list.
  private func report(_ element: GCControllerElement, on controller: String) {
    guard let change = change(of: element, on: controller) else { return }
    if let line = try? encoder.encode(change) {
      FileHandle.standardOutput.write(line + Data("\n".utf8))
    }
    redraw()
  }

  /// Refreshes the shown controllers from the controllers that are connected.
  private func redraw() {
    model.controllers = GCController.controllers().map { controller in
      let name = "\(controller.vendorName ?? "Controller") (\(controller.productCategory))"
      let ordered = layoutOrder(of: controller)
      let others = controller.physicalInputProfile.allElements
        .filter { element in !ordered.contains { $0 === element } }
        .compactMap { change(of: $0, on: name) }
        .sorted { $0.element < $1.element }
      return ControllerRow(
        id: ObjectIdentifier(controller),
        name: name,
        controls: ordered.compactMap { change(of: $0, on: name) },
        others: others
      )
    }
  }
}

/// The shared application.
let app = NSApplication.shared
/// The delegate of the application.
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
