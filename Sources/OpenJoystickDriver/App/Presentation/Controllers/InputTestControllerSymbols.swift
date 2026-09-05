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

    static func resolve(for protocolVariant: ControllerProtocolVariant) -> Self {
      switch protocolVariant {
      case .xboxOriginal, .xbox360, .xbox360Wireless, .xboxOne, .xboxAdaptiveJoystick: return xbox
      case .dualShock3, .dualShock4, .dualSense: return playStation
      case .switchPro: return switchController
      case .steamController: return steam
      case .flydigi: return xbox
      case .genericHID, .unknown: return generic
      }
    }

    private static var xbox: Self {
      Self(
        leftShoulder: Control(
          OJDLocalized.string("inputTest.leftBumper", fallback: "Left bumper"),
          symbol: "lb.button.roundedbottom.horizontal",
          fallbackSymbol: "lb.circle",
          fallbackText: "LB"
        ),
        leftTrigger: Control(
          OJDLocalized.string("inputTest.leftTrigger", fallback: "Left trigger"),
          symbol: "lt.button.roundedtop.horizontal",
          fallbackSymbol: "lt.circle",
          fallbackText: "LT"
        ),
        rightTrigger: Control(
          OJDLocalized.string("inputTest.rightTrigger", fallback: "Right trigger"),
          symbol: "rt.button.roundedtop.horizontal",
          fallbackSymbol: "rt.circle",
          fallbackText: "RT"
        ),
        rightShoulder: Control(
          OJDLocalized.string("inputTest.rightBumper", fallback: "Right bumper"),
          symbol: "rb.button.roundedbottom.horizontal",
          fallbackSymbol: "rb.circle",
          fallbackText: "RB"
        ),
        view: Control(
          OJDLocalized.string("inputTest.view", fallback: "View"),
          symbol: "rectangle.on.rectangle.button.angledtop.vertical.left",
          fallbackSymbol: "rectangle.on.rectangle"
        ),
        guide: Control(
          OJDLocalized.string("inputTest.xboxButton", fallback: "Xbox button"),
          symbol: "xbox.logo",
          fallbackSymbol: "house.fill"
        ),
        menu: Control(
          OJDLocalized.string("inputTest.menu", fallback: "Menu"),
          symbol: "line.3.horizontal.button.angledtop.vertical.right",
          fallbackSymbol: "line.3.horizontal"
        ),
        northFace: Control(
          OJDLocalized.string("inputTest.yButton", fallback: "Y button"),
          symbol: "y.circle",
          fallbackText: "Y"
        ),
        westFace: Control(
          OJDLocalized.string("inputTest.xButton", fallback: "X button"),
          symbol: "x.circle",
          fallbackText: "X"
        ),
        eastFace: Control(
          OJDLocalized.string("inputTest.bButton", fallback: "B button"),
          symbol: "b.circle",
          fallbackText: "B"
        ),
        southFace: Control(
          OJDLocalized.string("inputTest.aButton", fallback: "A button"),
          symbol: "a.circle",
          fallbackText: "A"
        ),
        leftStickClick: Control(
          OJDLocalized.string("inputTest.leftStickButton", fallback: "Left stick button"),
          symbol: "lsb.button.angledbottom.horizontal.left",
          fallbackSymbol: "l.joystick.press.down",
          fallbackText: "LSB"
        ),
        rightStickClick: Control(
          OJDLocalized.string("inputTest.rightStickButton", fallback: "Right stick button"),
          symbol: "rsb.button.angledbottom.horizontal.right",
          fallbackSymbol: "r.joystick.press.down",
          fallbackText: "RSB"
        )
      )
    }

    private static let playStation = Self(
      leftShoulder: Control(
        "L1",
        symbol: "l1.button.roundedbottom.horizontal",
        fallbackSymbol: "l1.circle"
      ),
      leftTrigger: Control(
        "L2",
        symbol: "l2.button.roundedtop.horizontal",
        fallbackSymbol: "l2.circle"
      ),
      rightTrigger: Control(
        "R2",
        symbol: "r2.button.roundedtop.horizontal",
        fallbackSymbol: "r2.circle"
      ),
      rightShoulder: Control(
        "R1",
        symbol: "r1.button.roundedbottom.horizontal",
        fallbackSymbol: "r1.circle"
      ),
      view: Control(
        OJDLocalized.string("inputTest.share", fallback: "Share"),
        symbol: "rectangle.on.rectangle.button.angledtop.vertical.left",
        fallbackSymbol: "rectangle.on.rectangle"
      ),
      guide: Control(
        OJDLocalized.string("inputTest.psButton", fallback: "PS button"),
        symbol: "playstation.logo",
        fallbackSymbol: "house.fill"
      ),
      menu: Control(
        OJDLocalized.string("inputTest.options", fallback: "Options"),
        symbol: "line.3.horizontal.button.angledtop.vertical.right",
        fallbackSymbol: "line.3.horizontal"
      ),
      northFace: Control(
        OJDLocalized.string("inputTest.triangle", fallback: "Triangle"),
        symbol: "triangle.circle",
        fallbackText: "△"
      ),
      westFace: Control(
        OJDLocalized.string("inputTest.square", fallback: "Square"),
        symbol: "square.circle",
        fallbackText: "□"
      ),
      eastFace: Control(
        OJDLocalized.string("inputTest.circle", fallback: "Circle"),
        symbol: "circle.circle",
        fallbackText: "○"
      ),
      southFace: Control(
        OJDLocalized.string("inputTest.cross", fallback: "Cross"),
        symbol: "xmark.circle",
        fallbackText: "×"
      ),
      leftStickClick: Control(
        "L3",
        symbol: "l3.button.angledbottom.horizontal.left",
        fallbackSymbol: "l.joystick.press.down"
      ),
      rightStickClick: Control(
        "R3",
        symbol: "r3.button.angledbottom.horizontal.right",
        fallbackSymbol: "r.joystick.press.down"
      )
    )

    private static var switchController: Self {
      Self(
        leftShoulder: Control(
          "L",
          symbol: "l.button.roundedbottom.horizontal",
          fallbackSymbol: "l.circle"
        ),
        leftTrigger: Control("ZL", symbol: "zl.button.roundedtop.horizontal", fallbackText: "ZL"),
        rightTrigger: Control("ZR", symbol: "zr.button.roundedtop.horizontal", fallbackText: "ZR"),
        rightShoulder: Control(
          "R",
          symbol: "r.button.roundedbottom.horizontal",
          fallbackSymbol: "r.circle"
        ),
        view: Control(
          OJDLocalized.string("inputTest.minus", fallback: "Minus"),
          symbol: "minus.circle",
          fallbackText: "−"
        ),
        guide: Control(
          OJDLocalized.string("inputTest.home", fallback: "Home"),
          symbol: "house.fill",
          fallbackSymbol: "gamecontroller.fill"
        ),
        menu: Control(
          OJDLocalized.string("inputTest.plus", fallback: "Plus"),
          symbol: "plus.circle",
          fallbackText: "+"
        ),
        northFace: Control(
          OJDLocalized.string("inputTest.xButton", fallback: "X button"),
          symbol: "x.circle",
          fallbackText: "X"
        ),
        westFace: Control(
          OJDLocalized.string("inputTest.yButton", fallback: "Y button"),
          symbol: "y.circle",
          fallbackText: "Y"
        ),
        eastFace: Control(
          OJDLocalized.string("inputTest.aButton", fallback: "A button"),
          symbol: "a.circle",
          fallbackText: "A"
        ),
        southFace: Control(
          OJDLocalized.string("inputTest.bButton", fallback: "B button"),
          symbol: "b.circle",
          fallbackText: "B"
        ),
        leftStickClick: Control(
          OJDLocalized.string("inputTest.leftStickButton", fallback: "Left stick button"),
          symbol: "l.joystick.press.down",
          fallbackText: "L3"
        ),
        rightStickClick: Control(
          OJDLocalized.string("inputTest.rightStickButton", fallback: "Right stick button"),
          symbol: "r.joystick.press.down",
          fallbackText: "R3"
        )
      )
    }

    private static var steam: Self {
      Self(
        leftShoulder: xbox.leftShoulder,
        leftTrigger: xbox.leftTrigger,
        rightTrigger: xbox.rightTrigger,
        rightShoulder: xbox.rightShoulder,
        view: xbox.view,
        guide: Control(
          OJDLocalized.string("inputTest.steamButton", fallback: "Steam button"),
          symbol: "house.fill",
          fallbackSymbol: "gamecontroller.fill"
        ),
        menu: xbox.menu,
        northFace: xbox.northFace,
        westFace: xbox.westFace,
        eastFace: xbox.eastFace,
        southFace: xbox.southFace,
        leftStickClick: Control(
          OJDLocalized.string("inputTest.leftStickButton", fallback: "Left stick button"),
          symbol: "l.joystick.press.down",
          fallbackText: "L3"
        ),
        rightStickClick: Control(
          OJDLocalized.string("inputTest.rightStickButton", fallback: "Right stick button"),
          symbol: "r.joystick.press.down",
          fallbackText: "R3"
        )
      )
    }

    private static var generic: Self {
      Self(
        leftShoulder: Control(
          OJDLocalized.string("inputTest.leftBumperGeneric", fallback: "LB / L1")
        ),
        leftTrigger: Control(
          OJDLocalized.string("inputTest.leftTriggerGeneric", fallback: "LT / L2")
        ),
        rightTrigger: Control(
          OJDLocalized.string("inputTest.rightTriggerGeneric", fallback: "RT / R2")
        ),
        rightShoulder: Control(
          OJDLocalized.string("inputTest.rightBumperGeneric", fallback: "RB / R1")
        ),
        view: Control(
          OJDLocalized.string("inputTest.view", fallback: "View"),
          symbol: "rectangle.on.rectangle",
          fallbackText: "View"
        ),
        guide: Control(
          OJDLocalized.string("inputTest.home", fallback: "Home"),
          symbol: "house.fill",
          fallbackSymbol: "gamecontroller.fill"
        ),
        menu: Control(
          OJDLocalized.string("inputTest.menu", fallback: "Menu"),
          symbol: "line.3.horizontal",
          fallbackText: "Menu"
        ),
        northFace: Control(
          OJDLocalized.string("inputTest.yTriangle", fallback: "Y / Triangle"),
          fallbackText: "Y"
        ),
        westFace: Control(
          OJDLocalized.string("inputTest.xSquare", fallback: "X / Square"),
          fallbackText: "X"
        ),
        eastFace: Control(
          OJDLocalized.string("inputTest.bCircle", fallback: "B / Circle"),
          fallbackText: "B"
        ),
        southFace: Control(
          OJDLocalized.string("inputTest.aCross", fallback: "A / Cross"),
          fallbackText: "A"
        ),
        leftStickClick: Control(
          OJDLocalized.string("inputTest.leftStickButton", fallback: "Left stick button"),
          symbol: "l.joystick.press.down",
          fallbackText: "L3"
        ),
        rightStickClick: Control(
          OJDLocalized.string("inputTest.rightStickButton", fallback: "Right stick button"),
          symbol: "r.joystick.press.down",
          fallbackText: "R3"
        )
      )
    }
  }

#endif
