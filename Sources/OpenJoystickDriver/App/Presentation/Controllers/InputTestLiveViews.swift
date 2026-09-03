#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct InputTestLiveInputView: View {
    @ObservedObject var liveState: InputTestLiveState
    let protocolVariant: ControllerProtocolVariant
    let mappingFlags: [String]

    var body: some View {
      let snapshot = liveState.snapshot
      let pressedButtons = Set(snapshot.pressedButtons)
      let symbols = InputTestControllerSymbolSet.resolve(for: protocolVariant)
      GroupBox {
        VStack(spacing: 10) {
          shoulderRow(snapshot: snapshot, pressedButtons: pressedButtons, symbols: symbols)
          Divider()
          HStack(alignment: .center, spacing: 18) {
            dpadCluster(pressedButtons: pressedButtons).frame(maxWidth: .infinity)
            systemCluster(
              pressedButtons: pressedButtons,
              symbols: symbols,
              protocolVariant: protocolVariant,
              mappingFlags: mappingFlags
            ).frame(maxWidth: .infinity)
            faceButtonCluster(pressedButtons: pressedButtons, symbols: symbols).frame(
              maxWidth: .infinity
            )
          }
          Divider()
          HStack(alignment: .top, spacing: 24) {
            InputTestStickView(
              title: OJDLocalized.string("inputTest.leftStick", fallback: "Left stick"),
              x: snapshot.leftStickX,
              y: snapshot.leftStickY,
              clickPresentation: symbols.leftStickClick,
              clickActive: isPressed([.leftStick], in: pressedButtons)
            )
            InputTestStickView(
              title: OJDLocalized.string("inputTest.rightStick", fallback: "Right stick"),
              x: snapshot.rightStickX,
              y: snapshot.rightStickY,
              clickPresentation: symbols.rightStickClick,
              clickActive: isPressed([.rightStick], in: pressedButtons)
            )
          }
          let additionalButtons = InputTestButtonPresentation.additionalButtons(in: snapshot)
          if !additionalButtons.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
              Text(
                OJDLocalized.string("inputTest.additionalButtons", fallback: "Additional buttons")
              ).font(.subheadline.weight(.semibold))
              VStack(alignment: .leading, spacing: 8) {
                ForEach(additionalButtons, id: \.self) { title in
                  InputTestIndicator(title: title, active: true)
                }
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
          }
        }.padding(6)
      } label: {
        Text(OJDLocalized.string("inputTest.controls", fallback: "Live input")).font(.headline)
      }
    }

    private func shoulderRow(
      snapshot: DeviceInputState,
      pressedButtons: Set<String>,
      symbols: InputTestControllerSymbolSet
    ) -> some View {
      HStack(spacing: 10) {
        indicator(symbols.leftShoulder, buttons: [.leftBumper, .l1], pressedButtons: pressedButtons)
        indicator(
          symbols.leftTrigger,
          active: snapshot.leftTrigger > 0.05 || isPressed([.l2Digital], in: pressedButtons)
        )
        indicator(
          symbols.rightTrigger,
          active: snapshot.rightTrigger > 0.05 || isPressed([.r2Digital], in: pressedButtons)
        )
        indicator(
          symbols.rightShoulder,
          buttons: [.rightBumper, .r1],
          pressedButtons: pressedButtons
        )
      }
    }

    private func dpadCluster(pressedButtons: Set<String>) -> some View {
      VStack(spacing: 6) {
        indicator(
          "D-pad up",
          symbol: "dpad.up.filled",
          fallbackSymbol: "arrowtriangle.up.fill",
          buttons: [.dpadUp],
          pressedButtons: pressedButtons
        )
        HStack(spacing: 6) {
          indicator(
            "D-pad left",
            symbol: "dpad.left.filled",
            fallbackSymbol: "arrowtriangle.left.fill",
            buttons: [.dpadLeft],
            pressedButtons: pressedButtons
          )
          indicator(
            "D-pad right",
            symbol: "dpad.right.filled",
            fallbackSymbol: "arrowtriangle.right.fill",
            buttons: [.dpadRight],
            pressedButtons: pressedButtons
          )
        }
        indicator(
          "D-pad down",
          symbol: "dpad.down.filled",
          fallbackSymbol: "arrowtriangle.down.fill",
          buttons: [.dpadDown],
          pressedButtons: pressedButtons
        )
      }
    }

    @ViewBuilder private func systemCluster(
      pressedButtons: Set<String>,
      symbols: InputTestControllerSymbolSet,
      protocolVariant: ControllerProtocolVariant,
      mappingFlags: [String]
    ) -> some View {
      switch InputTestSystemClusterLayout.resolve(for: protocolVariant, mappingFlags: mappingFlags)
      {
      case .standard:
        HStack(spacing: 6) {
          indicator(
            symbols.view,
            buttons: InputTestSystemClusterLayout.viewButtons(for: protocolVariant),
            pressedButtons: pressedButtons
          )
          indicator(symbols.guide, active: isPressed([.guide, .ps], in: pressedButtons))
          indicator(symbols.menu, buttons: [.start, .options], pressedButtons: pressedButtons)
        }
      case .xboxWithShare:
        VStack(spacing: 6) {
          HStack(spacing: 6) {
            indicator(symbols.view, buttons: [.back], pressedButtons: pressedButtons)
            indicator(symbols.guide, active: isPressed([.guide], in: pressedButtons))
            indicator(symbols.menu, buttons: [.start], pressedButtons: pressedButtons)
          }
          HStack(spacing: 6) {
            systemPlaceholder
            indicator(
              InputTestSystemClusterLayout.shareControl,
              buttons: InputTestSystemClusterLayout.shareButtons,
              pressedButtons: pressedButtons
            )
            systemPlaceholder
          }
        }
      }
    }

    private var systemPlaceholder: some View { Color.clear.frame(width: 54, height: 30) }

    private func faceButtonCluster(
      pressedButtons: Set<String>,
      symbols: InputTestControllerSymbolSet
    ) -> some View {
      VStack(spacing: 6) {
        indicator(symbols.northFace, buttons: [.y, .triangle], pressedButtons: pressedButtons)
        HStack(spacing: 6) {
          indicator(symbols.westFace, buttons: [.x, .square], pressedButtons: pressedButtons)
          indicator(symbols.eastFace, buttons: [.b, .circle], pressedButtons: pressedButtons)
        }
        indicator(symbols.southFace, buttons: [.a, .cross], pressedButtons: pressedButtons)
      }
    }

    private func indicator(
      _ presentation: InputTestControllerSymbolSet.Control,
      buttons: [OpenJoystickDriverKit.Button],
      pressedButtons: Set<String>
    ) -> some View { indicator(presentation, active: isPressed(buttons, in: pressedButtons)) }

    private func indicator(
      _ title: String,
      symbol: String,
      fallbackSymbol: String? = nil,
      buttons: [OpenJoystickDriverKit.Button],
      pressedButtons: Set<String>
    ) -> some View {
      InputTestIndicator(
        title: title,
        symbol: symbol,
        fallbackSymbol: fallbackSymbol,
        active: isPressed(buttons, in: pressedButtons)
      )
    }

    private func indicator(_ presentation: InputTestControllerSymbolSet.Control, active: Bool)
      -> some View
    {
      InputTestIndicator(
        title: presentation.title,
        symbol: presentation.symbol,
        fallbackSymbol: presentation.fallbackSymbol,
        fallbackText: presentation.fallbackText,
        active: active
      )
    }

    private func isPressed(
      _ buttons: [OpenJoystickDriverKit.Button],
      in pressedButtons: Set<String>
    ) -> Bool { InputTestButtonPresentation.isPressed(buttons, in: pressedButtons) }

  }

  enum InputTestSystemClusterLayout: Equatable {
    case standard
    case xboxWithShare

    enum Slot: Equatable {
      case view
      case guide
      case menu
      case share
      case empty
    }

    var rows: [[Slot]] {
      switch self {
      case .standard: return [[.view, .guide, .menu]]
      case .xboxWithShare: return [[.view, .guide, .menu], [.empty, .share, .empty]]
      }
    }

    static let shareControl = InputTestControllerSymbolSet.Control(
      "Share",
      symbol: "square.and.arrow.up",
      fallbackSymbol: "square.and.arrow.up"
    )

    static func resolve(for protocolVariant: ControllerProtocolVariant, mappingFlags: [String])
      -> Self
    {
      if protocolVariant.isXboxFamily && mappingFlags.contains("shareButton") {
        return .xboxWithShare
      }
      return .standard
    }

    static func viewButtons(for protocolVariant: ControllerProtocolVariant)
      -> [OpenJoystickDriverKit.Button]
    { protocolVariant.isPlayStationFamily ? [.share] : [.back] }

    static let shareButtons: [OpenJoystickDriverKit.Button] = [.share]
  }

  extension ControllerProtocolVariant {
    var isXboxFamily: Bool {
      switch self {
      case .xboxOriginal, .xbox360, .xbox360Wireless, .xboxOne, .xboxAdaptiveJoystick: return true
      default: return false
      }
    }

    var isPlayStationFamily: Bool {
      switch self {
      case .dualShock3, .dualShock4, .dualSense: return true
      default: return false
      }
    }
  }

  struct InputTestAxisValuesView: View {
    @ObservedObject var liveState: InputTestLiveState

    var body: some View {
      let snapshot = liveState.snapshot
      GroupBox {
        HStack(alignment: .top, spacing: 14) {
          VStack(spacing: 8) {
            InputTestAxisRow(label: "Left X", value: snapshot.leftStickX, signed: true)
            InputTestAxisRow(label: "Left Y", value: snapshot.leftStickY, signed: true)
            InputTestAxisRow(label: "LT", value: snapshot.leftTrigger, signed: false)
          }
          VStack(spacing: 8) {
            InputTestAxisRow(label: "Right X", value: snapshot.rightStickX, signed: true)
            InputTestAxisRow(label: "Right Y", value: snapshot.rightStickY, signed: true)
            InputTestAxisRow(label: "RT", value: snapshot.rightTrigger, signed: false)
          }
        }.padding(4)
      } label: {
        Text(OJDLocalized.string("inputTest.axisValues", fallback: "Axis values")).font(.headline)
      }
    }
  }

  private struct InputTestStickView: View {
    let title: String
    let x: Float
    let y: Float
    let clickPresentation: InputTestControllerSymbolSet.Control
    let clickActive: Bool

    var body: some View {
      VStack(spacing: 7) {
        Text(title).font(.subheadline.weight(.semibold))
        ZStack {
          Circle().fill(Color(NSColor.controlBackgroundColor)).frame(width: 86, height: 86)
          Circle().stroke(Color(NSColor.separatorColor), lineWidth: 1).frame(width: 86, height: 86)
          Rectangle().fill(Color(NSColor.separatorColor)).frame(width: 1, height: 72)
          Rectangle().fill(Color(NSColor.separatorColor)).frame(width: 72, height: 1)
          Circle().fill(Color.accentColor).frame(width: 12, height: 12).shadow(
            color: Color.black.opacity(0.16),
            radius: 1,
            y: 1
          ).offset(x: CGFloat(max(-1, min(1, x))) * 33, y: CGFloat(max(-1, min(1, y))) * 33)
        }.ojdAccessibilityLabel(title).ojdAccessibilityValue(String(format: "X %.3f, Y %.3f", x, y))
        HStack(spacing: 10) {
          Text(String(format: "X %.3f", x))
          Text(String(format: "Y %.3f", y))
        }.font(.system(.caption, design: .monospaced)).foregroundColor(
          Color(NSColor.secondaryLabelColor)
        )
        InputTestIndicator(
          title: clickPresentation.title,
          symbol: clickPresentation.symbol,
          fallbackSymbol: clickPresentation.fallbackSymbol,
          fallbackText: clickPresentation.fallbackText,
          active: clickActive
        )
      }.frame(maxWidth: .infinity)
    }
  }

  private struct InputTestIndicator: View {
    let title: String
    var displayedText: String?
    var symbol: String?
    var fallbackSymbol: String?
    var fallbackText: String?
    let active: Bool

    init(
      title: String,
      displayedText: String? = nil,
      symbol: String? = nil,
      fallbackSymbol: String? = nil,
      fallbackText: String? = nil,
      active: Bool
    ) {
      self.title = title
      self.displayedText = displayedText
      self.symbol = symbol
      self.fallbackSymbol = fallbackSymbol
      self.fallbackText = fallbackText
      self.active = active
    }

    var body: some View {
      HStack(spacing: 5) {
        if let symbol {
          OJDSystemSymbol(
            name: symbol,
            fallback: fallbackText ?? displayedText ?? title,
            fallbackSymbolName: fallbackSymbol
          )
        }
        if let displayedText, symbol != nil { Text(displayedText) }
        if symbol == nil { Text(displayedText ?? fallbackText ?? title) }
      }.font(.caption.weight(active ? .semibold : .regular)).lineLimit(1).padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 26).foregroundColor(
          active ? Color.white : Color(NSColor.labelColor)
        ).background(
          RoundedRectangle(cornerRadius: 6).fill(
            active ? Color.accentColor : Color(NSColor.controlBackgroundColor)
          )
        ).overlay(
          RoundedRectangle(cornerRadius: 6).stroke(
            active ? Color.accentColor : Color(NSColor.separatorColor),
            lineWidth: 1
          )
        ).ojdAccessibilityLabel(title).ojdAccessibilityValue(
          active
            ? OJDLocalized.string("inputTest.pressed", fallback: "Pressed")
            : OJDLocalized.string("inputTest.released", fallback: "Released")
        )
    }
  }

  private struct InputTestAxisRow: View {
    let label: String
    let value: Float
    let signed: Bool

    var body: some View {
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text(label)
          Spacer()
          Text(String(format: "%.3f", value)).font(.system(.caption, design: .monospaced))
        }
        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule().fill(Color(NSColor.controlBackgroundColor)).frame(height: 6)
            if signed {
              Rectangle().fill(Color(NSColor.separatorColor)).frame(width: 1, height: 12).position(
                x: proxy.size.width / 2,
                y: proxy.size.height / 2
              )
              Circle().fill(Color.accentColor).frame(width: 10, height: 10).position(
                x: CGFloat((max(-1, min(1, value)) + 1) / 2) * proxy.size.width,
                y: proxy.size.height / 2
              )
            } else {
              Capsule().fill(Color.accentColor).frame(
                width: CGFloat(max(0, min(1, value))) * proxy.size.width,
                height: 6
              )
            }
          }
        }.frame(height: 10)
      }.font(.caption).ojdAccessibilityLabel(label).ojdAccessibilityValue(
        String(format: "%.3f", value)
      )
    }
  }

#endif
