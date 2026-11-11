#if canImport(SwiftUI)

  import OpenJoystickDriverKit

  /// The titles and symbols of the buttons that the live input view draws, for one glyph family.
  struct InputTestControllerSymbolSet: Equatable {
    /// The title and symbols of one button.
    struct Control: Equatable {
      /// The name VoiceOver reads and the indicator shows when no symbol is drawn.
      let title: String
      /// The name of the SF Symbol, or nil to show the text.
      let symbol: String?
      /// The name of the SF Symbol to try when `symbol` does not exist, or nil.
      let fallbackSymbol: String?
      /// The text to show when no symbol exists.
      let fallbackText: String

      /// Creates the button.
      ///
      /// - Parameters:
      ///   - title: The name of the button.
      ///   - symbol: The name of the SF Symbol, or nil.
      ///   - fallbackSymbol: The name of the SF Symbol to try when `symbol` does not exist, or nil.
      ///   - fallbackText: The text to show when no symbol exists; the title when nil.
      init(
        _ title: String,
        symbol: String? = nil,
        fallbackSymbol: String? = nil,
        fallbackText: String? = nil
      ) {
        self.title = title
        self.symbol = symbol
        self.fallbackSymbol = fallbackSymbol
        self.fallbackText = fallbackText ?? title
      }
    }

    /// The left shoulder button.
    let leftShoulder: Control
    /// The left trigger.
    let leftTrigger: Control
    /// The right trigger.
    let rightTrigger: Control
    /// The right shoulder button.
    let rightShoulder: Control
    /// The View button.
    let view: Control
    /// The guide button.
    let guide: Control
    /// The Menu button.
    let menu: Control
    /// The north face button.
    let northFace: Control
    /// The west face button.
    let westFace: Control
    /// The east face button.
    let eastFace: Control
    /// The south face button.
    let southFace: Control
    /// The click of the left stick.
    let leftStickClick: Control
    /// The click of the right stick.
    let rightStickClick: Control

    /// Returns the set of the glyph family.
    ///
    /// - Parameter glyphFamily: Whether the controller shows Xbox or generic glyphs.
    /// - Returns: The set of the glyph family.
    static func resolve(for glyphFamily: VirtualIdentityGlyphFamily) -> Self {
      switch glyphFamily {
      case .xbox: return xbox
      case .generic: return generic
      }
    }

    /// The Xbox set: bumpers, triggers, View, Menu and lettered face buttons.
    private static var xbox: Self {
      Self(
        leftShoulder: Control(
          OJDLocalized.string("ui.inputTest.leftBumper"),
          symbol: "lb.button.roundedbottom.horizontal",
          fallbackSymbol: "lb.circle",
          fallbackText: "LB"
        ),
        leftTrigger: Control(
          OJDLocalized.string("ui.inputTest.leftTrigger"),
          symbol: "lt.button.roundedtop.horizontal",
          fallbackSymbol: "lt.circle",
          fallbackText: "LT"
        ),
        rightTrigger: Control(
          OJDLocalized.string("ui.inputTest.rightTrigger"),
          symbol: "rt.button.roundedtop.horizontal",
          fallbackSymbol: "rt.circle",
          fallbackText: "RT"
        ),
        rightShoulder: Control(
          OJDLocalized.string("ui.inputTest.rightBumper"),
          symbol: "rb.button.roundedbottom.horizontal",
          fallbackSymbol: "rb.circle",
          fallbackText: "RB"
        ),
        view: Control(
          OJDLocalized.string("ui.inputTest.view"),
          symbol: "rectangle.on.rectangle.button.angledtop.vertical.left",
          fallbackSymbol: "rectangle.on.rectangle"
        ),
        guide: Control(
          OJDLocalized.string("ui.inputTest.xboxButton"),
          symbol: "xbox.logo",
          fallbackSymbol: "house.fill"
        ),
        menu: Control(
          OJDLocalized.string("ui.inputTest.menu"),
          symbol: "line.3.horizontal.button.angledtop.vertical.right",
          fallbackSymbol: "line.3.horizontal"
        ),
        northFace: Control(
          OJDLocalized.string("ui.inputTest.yButton"),
          symbol: "y.circle",
          fallbackText: "Y"
        ),
        westFace: Control(
          OJDLocalized.string("ui.inputTest.xButton"),
          symbol: "x.circle",
          fallbackText: "X"
        ),
        eastFace: Control(
          OJDLocalized.string("ui.inputTest.bButton"),
          symbol: "b.circle",
          fallbackText: "B"
        ),
        southFace: Control(
          OJDLocalized.string("ui.inputTest.aButton"),
          symbol: "a.circle",
          fallbackText: "A"
        ),
        leftStickClick: Control(
          OJDLocalized.string("ui.inputTest.leftStickButton"),
          symbol: "lsb.button.angledbottom.horizontal.left",
          fallbackSymbol: "l.joystick.press.down",
          fallbackText: "LSB"
        ),
        rightStickClick: Control(
          OJDLocalized.string("ui.inputTest.rightStickButton"),
          symbol: "rsb.button.angledbottom.horizontal.right",
          fallbackSymbol: "r.joystick.press.down",
          fallbackText: "RSB"
        )
      )
    }

    /// The generic set: shoulders and triggers by name, and face buttons by their shape.
    private static var generic: Self {
      Self(
        leftShoulder: Control(
          OJDLocalized.string("ui.inputTest.leftBumperGeneric")
        ),
        leftTrigger: Control(
          OJDLocalized.string("ui.inputTest.leftTriggerGeneric")
        ),
        rightTrigger: Control(
          OJDLocalized.string("ui.inputTest.rightTriggerGeneric")
        ),
        rightShoulder: Control(
          OJDLocalized.string("ui.inputTest.rightBumperGeneric")
        ),
        view: Control(
          OJDLocalized.string("ui.inputTest.view"),
          symbol: "rectangle.on.rectangle",
          fallbackText: "View"
        ),
        guide: Control(
          OJDLocalized.string("ui.inputTest.home"),
          symbol: "house.fill",
          fallbackSymbol: "gamecontroller.fill"
        ),
        menu: Control(
          OJDLocalized.string("ui.inputTest.menu"),
          symbol: "line.3.horizontal",
          fallbackText: "Menu"
        ),
        northFace: Control(
          OJDLocalized.string("ui.inputTest.yTriangle"),
          fallbackText: "Y"
        ),
        westFace: Control(
          OJDLocalized.string("ui.inputTest.xSquare"),
          fallbackText: "X"
        ),
        eastFace: Control(
          OJDLocalized.string("ui.inputTest.bCircle"),
          fallbackText: "B"
        ),
        southFace: Control(
          OJDLocalized.string("ui.inputTest.aCross"),
          fallbackText: "A"
        ),
        leftStickClick: Control(
          OJDLocalized.string("ui.inputTest.leftStickButton"),
          symbol: "l.joystick.press.down",
          fallbackText: "L3"
        ),
        rightStickClick: Control(
          OJDLocalized.string("ui.inputTest.rightStickButton"),
          symbol: "r.joystick.press.down",
          fallbackText: "R3"
        )
      )
    }
  }

#endif
