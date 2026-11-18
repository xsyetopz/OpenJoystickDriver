import OpenJoystickDriverKit

/// What the Input Test live view draws for one controller: the fixed clusters plus one drawing for
/// each other control its record or HID descriptor declares, grouped by kind.
struct InputTestControlLayout: Equatable {
  /// The declared buttons with no cluster of their own, in `Control` order: Capture, Microphone,
  /// the touchpad click, paddles, auxiliary buttons, stick and grip touches, and trackpad clicks
  /// and touches.
  let extraButtons: [Control]
  /// Whether the layout draws a pointer cluster for the declared pointer axes and tracking.
  let hasPointer: Bool
  /// The touch surfaces the layout draws, in display order.
  let touchSurfaces: [ControllerTouchSurface]
  /// The controls the layout draws.
  let drawnControls: Set<Control>

  /// The controls the fixed clusters draw: the face, shoulder, trigger, system, stick-click, D-pad
  /// and stick-axis controls.
  private static let clusterControls = InputTestButtonPresentation.drawnControls
    .union(Control.dpad).union(Control.stickAxes)

  /// The controls of the pointer cluster.
  private static let pointerControls: Set<Control> = [.pointerX, .pointerY, .pointerTracking]

  /// Creates the layout of a controller that declares `capabilities`.
  ///
  /// - Parameter capabilities: The controls and sensors the controller declares.
  init(capabilities: ControllerCapabilities) {
    let declared = capabilities.controls
    extraButtons = Control.allCases.filter {
      declared.contains($0) && !Self.clusterControls.contains($0)
        && !Self.pointerControls.contains($0)
    }
    hasPointer = !declared.isDisjoint(with: Self.pointerControls)
    if capabilities.touchContactCount == 0 {
      touchSurfaces = []
    } else if declared.contains(.leftTrackpadTouch) || declared.contains(.rightTrackpadTouch) {
      touchSurfaces = [.left, .right]
    } else {
      touchSurfaces = [.primary]
    }
    drawnControls = Self.clusterControls.union(extraButtons)
      .union(hasPointer ? Self.pointerControls : [])
  }

  /// Returns the buttons of the extra section for `state`: the declared ones, then any other
  /// pressed control that no drawing covers, in `Control` order.
  ///
  /// - Parameter state: The latest input of the controller.
  /// - Returns: The buttons of the extra section.
  func extraButtons(for state: ControllerState) -> [Control] {
    Control.allCases.filter {
      extraButtons.contains($0) || (state.pressed.contains($0) && !drawnControls.contains($0))
    }
  }

  /// Returns the surfaces to draw for `state`: the declared ones, then any other surface that
  /// reported a frame.
  ///
  /// - Parameter state: The latest input of the controller.
  /// - Returns: The surfaces to draw.
  func touchSurfaces(for state: ControllerState) -> [ControllerTouchSurface] {
    let reported = [ControllerTouchSurface.primary, .left, .right].filter { surface in
      !touchSurfaces.contains(surface) && state.touch.contains { $0.surface == surface }
    }
    return touchSurfaces + reported
  }
}
