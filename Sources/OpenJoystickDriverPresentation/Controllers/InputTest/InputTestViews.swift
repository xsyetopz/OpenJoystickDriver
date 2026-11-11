#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The sections of the Input Test form, in display order.
  enum InputTestSection: Int, CaseIterable, Equatable {
    /// The live input of the controller.
    case liveInput
    /// The motion calibration.
    case motion
    /// The rumble test.
    case rumble
    /// The player indicator, color and brightness.
    case lighting
  }

  /// The Input Test window's form.
  struct InputTestView: View {
    /// The state of the window.
    @ObservedObject
    var model: InputTestViewModel
    /// The model of the app's view of the service.
    let runtimeViewModel: RuntimeViewModel
  }

  /// A group of output controls that redraws when the output settings change.
  struct InputTestOutputControlsView<Content: View>: View {
    /// The values of the output controls.
    @ObservedObject
    var settings: InputTestOutputSettings
    /// The controls.
    @ViewBuilder
    let content: () -> Content

    /// The controls.
    var body: some View { content() }
  }

  /// A color well that edits an `NSColor`.
  struct OJDPhysicalColorWell: NSViewRepresentable {
    /// The color.
    @Binding
    var color: NSColor

    /// Creates the coordinator that writes the chosen color back.
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// Creates the color well.
    func makeNSView(context: Context) -> NSColorWell {
      let well = NSColorWell()
      well.target = context.coordinator
      well.action = #selector(Coordinator.changed(_:))
      return well
    }

    /// Shows the color in the well and gives the coordinator the current binding.
    func updateNSView(_ well: NSColorWell, context: Context) {
      context.coordinator.parent = self
      well.color = color
    }

    /// The target of the color well's action.
    final class Coordinator: NSObject {
      /// The color well that the coordinator reports for.
      var parent: OJDPhysicalColorWell

      /// Creates the coordinator.
      init(parent: OJDPhysicalColorWell) { self.parent = parent }

      /// Writes the color of the well to the binding.
      @MainActor
      @objc
      func changed(_ sender: NSColorWell) { parent.color = sender.color }
    }
  }

#endif
