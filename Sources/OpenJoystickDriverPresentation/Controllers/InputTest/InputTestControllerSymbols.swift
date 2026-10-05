#if canImport(SwiftUI)

  import OpenJoystickDriverKit

  struct InputTestControllerSymbolSet: Equatable {
    struct Control: Equatable {
      let title: String
      let symbol: String?
      let fallbackSymbol: String?
      let fallbackText: String

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

    let leftShoulder: Control
    let leftTrigger: Control
    let rightTrigger: Control
    let rightShoulder: Control
    let view: Control
    let guide: Control
    let menu: Control
    let northFace: Control
    let westFace: Control
    let eastFace: Control
    let southFace: Control
    let leftStickClick: Control
    let rightStickClick: Control

    static func resolve(for glyphFamily: VirtualIdentityGlyphFamily) -> Self {
      switch glyphFamily {
      case .xbox: return xbox
      case .generic: return generic
      }
    }

    private static var xbox: Self {
      Self(
        leftShoulder: Control(
          OJDLocalized.string("inputTest.leftBumper"),
          symbol: "lb.button.roundedbottom.horizontal",
          fallbackSymbol: "lb.circle",
          fallbackText: "LB"
        ),
        leftTrigger: Control(
          OJDLocalized.string("inputTest.leftTrigger"),
          symbol: "lt.button.roundedtop.horizontal",
          fallbackSymbol: "lt.circle",
          fallbackText: "LT"
        ),
        rightTrigger: Control(
          OJDLocalized.string("inputTest.rightTrigger"),
          symbol: "rt.button.roundedtop.horizontal",
          fallbackSymbol: "rt.circle",
          fallbackText: "RT"
        ),
        rightShoulder: Control(
          OJDLocalized.string("inputTest.rightBumper"),
          symbol: "rb.button.roundedbottom.horizontal",
          fallbackSymbol: "rb.circle",
          fallbackText: "RB"
        ),
        view: Control(
          OJDLocalized.string("inputTest.view"),
          symbol: "rectangle.on.rectangle.button.angledtop.vertical.left",
          fallbackSymbol: "rectangle.on.rectangle"
        ),
        guide: Control(
          OJDLocalized.string("inputTest.xboxButton"),
          symbol: "xbox.logo",
          fallbackSymbol: "house.fill"
        ),
        menu: Control(
          OJDLocalized.string("inputTest.menu"),
          symbol: "line.3.horizontal.button.angledtop.vertical.right",
          fallbackSymbol: "line.3.horizontal"
        ),
        northFace: Control(
          OJDLocalized.string("inputTest.yButton"),
          symbol: "y.circle",
          fallbackText: "Y"
        ),
        westFace: Control(
          OJDLocalized.string("inputTest.xButton"),
          symbol: "x.circle",
          fallbackText: "X"
        ),
        eastFace: Control(
          OJDLocalized.string("inputTest.bButton"),
          symbol: "b.circle",
          fallbackText: "B"
        ),
        southFace: Control(
          OJDLocalized.string("inputTest.aButton"),
          symbol: "a.circle",
          fallbackText: "A"
        ),
        leftStickClick: Control(
          OJDLocalized.string("inputTest.leftStickButton"),
          symbol: "lsb.button.angledbottom.horizontal.left",
          fallbackSymbol: "l.joystick.press.down",
          fallbackText: "LSB"
        ),
        rightStickClick: Control(
          OJDLocalized.string("inputTest.rightStickButton"),
          symbol: "rsb.button.angledbottom.horizontal.right",
          fallbackSymbol: "r.joystick.press.down",
          fallbackText: "RSB"
        )
      )
    }

    private static var generic: Self {
      Self(
        leftShoulder: Control(
          OJDLocalized.string("inputTest.leftBumperGeneric")
        ),
        leftTrigger: Control(
          OJDLocalized.string("inputTest.leftTriggerGeneric")
        ),
        rightTrigger: Control(
          OJDLocalized.string("inputTest.rightTriggerGeneric")
        ),
        rightShoulder: Control(
          OJDLocalized.string("inputTest.rightBumperGeneric")
        ),
        view: Control(
          OJDLocalized.string("inputTest.view"),
          symbol: "rectangle.on.rectangle",
          fallbackText: "View"
        ),
        guide: Control(
          OJDLocalized.string("inputTest.home"),
          symbol: "house.fill",
          fallbackSymbol: "gamecontroller.fill"
        ),
        menu: Control(
          OJDLocalized.string("inputTest.menu"),
          symbol: "line.3.horizontal",
          fallbackText: "Menu"
        ),
        northFace: Control(
          OJDLocalized.string("inputTest.yTriangle"),
          fallbackText: "Y"
        ),
        westFace: Control(
          OJDLocalized.string("inputTest.xSquare"),
          fallbackText: "X"
        ),
        eastFace: Control(
          OJDLocalized.string("inputTest.bCircle"),
          fallbackText: "B"
        ),
        southFace: Control(
          OJDLocalized.string("inputTest.aCross"),
          fallbackText: "A"
        ),
        leftStickClick: Control(
          OJDLocalized.string("inputTest.leftStickButton"),
          symbol: "l.joystick.press.down",
          fallbackText: "L3"
        ),
        rightStickClick: Control(
          OJDLocalized.string("inputTest.rightStickButton"),
          symbol: "r.joystick.press.down",
          fallbackText: "R3"
        )
      )
    }
  }

#endif
