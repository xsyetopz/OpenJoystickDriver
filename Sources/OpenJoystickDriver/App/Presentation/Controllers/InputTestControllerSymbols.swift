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
      case .genericHID, .unknown: return generic
      }
    }

    private static let xbox = Self(
      leftShoulder: Control(
        "Left bumper",
        symbol: "lb.button.roundedbottom.horizontal",
        fallbackSymbol: "lb.circle",
        fallbackText: "LB"
      ),
      leftTrigger: Control(
        "Left trigger",
        symbol: "lt.button.roundedtop.horizontal",
        fallbackSymbol: "lt.circle",
        fallbackText: "LT"
      ),
      rightTrigger: Control(
        "Right trigger",
        symbol: "rt.button.roundedtop.horizontal",
        fallbackSymbol: "rt.circle",
        fallbackText: "RT"
      ),
      rightShoulder: Control(
        "Right bumper",
        symbol: "rb.button.roundedbottom.horizontal",
        fallbackSymbol: "rb.circle",
        fallbackText: "RB"
      ),
      view: Control(
        "View",
        symbol: "rectangle.on.rectangle.button.angledtop.vertical.left",
        fallbackSymbol: "rectangle.on.rectangle"
      ),
      guide: Control("Xbox button", symbol: "xbox.logo", fallbackSymbol: "house.fill"),
      menu: Control(
        "Menu",
        symbol: "line.3.horizontal.button.angledtop.vertical.right",
        fallbackSymbol: "line.3.horizontal"
      ),
      northFace: Control("Y button", symbol: "y.circle", fallbackText: "Y"),
      westFace: Control("X button", symbol: "x.circle", fallbackText: "X"),
      eastFace: Control("B button", symbol: "b.circle", fallbackText: "B"),
      southFace: Control("A button", symbol: "a.circle", fallbackText: "A"),
      leftStickClick: Control(
        "Left stick button",
        symbol: "lsb.button.angledbottom.horizontal.left",
        fallbackSymbol: "l.joystick.press.down",
        fallbackText: "LSB"
      ),
      rightStickClick: Control(
        "Right stick button",
        symbol: "rsb.button.angledbottom.horizontal.right",
        fallbackSymbol: "r.joystick.press.down",
        fallbackText: "RSB"
      )
    )

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
        "Share",
        symbol: "rectangle.on.rectangle.button.angledtop.vertical.left",
        fallbackSymbol: "rectangle.on.rectangle"
      ),
      guide: Control("PS button", symbol: "playstation.logo", fallbackSymbol: "house.fill"),
      menu: Control(
        "Options",
        symbol: "line.3.horizontal.button.angledtop.vertical.right",
        fallbackSymbol: "line.3.horizontal"
      ),
      northFace: Control("Triangle", symbol: "triangle.circle", fallbackText: "△"),
      westFace: Control("Square", symbol: "square.circle", fallbackText: "□"),
      eastFace: Control("Circle", symbol: "circle.circle", fallbackText: "○"),
      southFace: Control("Cross", symbol: "xmark.circle", fallbackText: "×"),
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

    private static let switchController = Self(
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
      view: Control("Minus", symbol: "minus.circle", fallbackText: "−"),
      guide: Control("Home", symbol: "house.fill", fallbackSymbol: "gamecontroller.fill"),
      menu: Control("Plus", symbol: "plus.circle", fallbackText: "+"),
      northFace: Control("X button", symbol: "x.circle", fallbackText: "X"),
      westFace: Control("Y button", symbol: "y.circle", fallbackText: "Y"),
      eastFace: Control("A button", symbol: "a.circle", fallbackText: "A"),
      southFace: Control("B button", symbol: "b.circle", fallbackText: "B"),
      leftStickClick: Control(
        "Left stick button",
        symbol: "l.joystick.press.down",
        fallbackText: "L3"
      ),
      rightStickClick: Control(
        "Right stick button",
        symbol: "r.joystick.press.down",
        fallbackText: "R3"
      )
    )

    private static let steam = Self(
      leftShoulder: xbox.leftShoulder,
      leftTrigger: xbox.leftTrigger,
      rightTrigger: xbox.rightTrigger,
      rightShoulder: xbox.rightShoulder,
      view: xbox.view,
      guide: Control("Steam button", symbol: "house.fill", fallbackSymbol: "gamecontroller.fill"),
      menu: xbox.menu,
      northFace: xbox.northFace,
      westFace: xbox.westFace,
      eastFace: xbox.eastFace,
      southFace: xbox.southFace,
      leftStickClick: Control(
        "Left stick button",
        symbol: "l.joystick.press.down",
        fallbackText: "L3"
      ),
      rightStickClick: Control(
        "Right stick button",
        symbol: "r.joystick.press.down",
        fallbackText: "R3"
      )
    )

    private static let generic = Self(
      leftShoulder: Control("LB / L1"),
      leftTrigger: Control("LT / L2"),
      rightTrigger: Control("RT / R2"),
      rightShoulder: Control("RB / R1"),
      view: Control("View", symbol: "rectangle.on.rectangle", fallbackText: "View"),
      guide: Control("Home", symbol: "house.fill", fallbackSymbol: "gamecontroller.fill"),
      menu: Control("Menu", symbol: "line.3.horizontal", fallbackText: "Menu"),
      northFace: Control("Y / Triangle", fallbackText: "Y"),
      westFace: Control("X / Square", fallbackText: "X"),
      eastFace: Control("B / Circle", fallbackText: "B"),
      southFace: Control("A / Cross", fallbackText: "A"),
      leftStickClick: Control(
        "Left stick button",
        symbol: "l.joystick.press.down",
        fallbackText: "L3"
      ),
      rightStickClick: Control(
        "Right stick button",
        symbol: "r.joystick.press.down",
        fallbackText: "R3"
      )
    )
  }

#endif
