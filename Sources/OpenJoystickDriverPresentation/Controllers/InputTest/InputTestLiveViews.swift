#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The live input of the controller: shoulders, D-pad, system and face buttons, sticks and any
  /// other pressed button.
  struct InputTestLiveInputView: View {
    /// The high-frequency input state.
    @ObservedObject
    var liveState: InputTestLiveState
    /// The glyphs of the controller's identity.
    let presentation: VirtualIdentityPresentation
    /// The controls the controller declares, grouped by kind.
    let layout: InputTestControlLayout
  }

  /// The aim of a pointing device: a square with a dot at the position, the numbers, and the
  /// tracking state.
  struct InputTestPointerView: View {
    /// The horizontal position, -1 to 1.
    let x: Float
    /// The vertical position, -1 to 1.
    let y: Float
    /// Whether the device sees its target.
    let tracking: Bool

    /// The pointer.
    var body: some View {
      let title = OJDLocalized.string("ui.inputTest.pointer")
      return VStack(spacing: OJDSpacing.small) {
        Text(title).font(.subheadline.weight(.semibold))
        ZStack {
          Rectangle().fill(Color(NSColor.controlBackgroundColor)).frame(width: 86, height: 86)
          Rectangle().stroke(Color(NSColor.separatorColor), lineWidth: 1).frame(
            width: 86,
            height: 86
          )
          Circle().fill(tracking ? Color.accentColor : Color(NSColor.tertiaryLabelColor)).frame(
            width: 12,
            height: 12
          ).offset(x: CGFloat(max(-1, min(1, x))) * 37, y: CGFloat(max(-1, min(1, y))) * 37)
        }.ojdAccessibilityLabel(title).ojdAccessibilityValue(
          OJDLocalized.formatted("ui.inputTest.axisPair", x, y)
        )
        HStack(spacing: OJDSpacing.medium) {
          Text(OJDLocalized.formatted("ui.inputTest.axisX", x))
          Text(OJDLocalized.formatted("ui.inputTest.axisY", y))
        }.font(.system(.caption, design: .monospaced)).foregroundColor(
          Color(NSColor.secondaryLabelColor)
        )
        InputTestIndicator(
          title: OJDLocalized.string("ui.inputTest.pointerTracking"),
          active: tracking
        )
      }.frame(maxWidth: .infinity)
    }
  }

  /// One touch surface: a rectangle with a dot for each active contact.
  struct InputTestTouchSurfaceView: View {
    /// The name of the surface.
    let title: String
    /// The latest frame of the surface, or nil before it reports one.
    let frame: ControllerTouchSample?

    /// The active contacts of the frame.
    private var contacts: [ControllerTouchContact] { frame?.contacts.filter(\.isActive) ?? [] }

    /// The surface.
    var body: some View {
      VStack(spacing: OJDSpacing.small) {
        Text(title).font(.subheadline.weight(.semibold))
        ZStack(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor))
          RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor), lineWidth: 1)
          ForEach(contacts, id: \.slot) { contact in
            Circle().fill(Color.accentColor).frame(width: 10, height: 10).offset(
              x: CGFloat(contact.x) / CGFloat(UInt16.max) * 150 - 5,
              y: CGFloat(contact.y) / CGFloat(UInt16.max) * 80 - 5
            )
          }
        }.frame(width: 150, height: 80).ojdAccessibilityLabel(title).ojdAccessibilityValue(
          contacts.map {
            OJDLocalized.formatted(
              "ui.inputTest.axisPair",
              Float($0.x) / Float(UInt16.max),
              Float($0.y) / Float(UInt16.max)
            )
          }.joined(separator: ", ")
        )
        Text(
          contacts.first.map {
            OJDLocalized.formatted(
              "ui.inputTest.axisPair",
              Float($0.x) / Float(UInt16.max),
              Float($0.y) / Float(UInt16.max)
            )
          } ?? OJDLocalized.string("ui.inputTest.touchIdle")
        ).font(.system(.caption, design: .monospaced)).foregroundColor(
          Color(NSColor.secondaryLabelColor)
        )
      }.frame(maxWidth: .infinity)
    }
  }

  /// One stick: a circle with a dot at its position, the numbers, and its click.
  struct InputTestStickView: View {
    /// The name of the stick.
    let title: String
    /// The horizontal position, -1 to 1.
    let x: Float
    /// The vertical position, -1 to 1.
    let y: Float
    /// The title and symbols of the stick click.
    let clickPresentation: InputTestControllerSymbolSet.Control
    /// Whether the stick is clicked.
    let clickActive: Bool

    /// The stick.
    var body: some View {
      VStack(spacing: OJDSpacing.small) {
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
        }.ojdAccessibilityLabel(title).ojdAccessibilityValue(
          OJDLocalized.formatted("ui.inputTest.axisPair", x, y)
        )
        HStack(spacing: OJDSpacing.medium) {
          Text(OJDLocalized.formatted("ui.inputTest.axisX", x))
          Text(OJDLocalized.formatted("ui.inputTest.axisY", y))
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

  /// One button or trigger of the live input, drawn filled while it is pressed.
  struct InputTestIndicator: View {
    /// The name of the button.
    let title: String
    /// The analog value drawn beside the label, for a control that reports one.
    var displayedText: String?
    /// The name of the SF Symbol, or nil to show the text.
    var symbol: String?
    /// The name of the SF Symbol to try when `symbol` does not exist, or nil.
    var fallbackSymbol: String?
    /// The text to show when no symbol exists.
    var fallbackText: String?
    /// Whether the button is pressed.
    let active: Bool

    /// Creates the indicator.
    ///
    /// - Parameters:
    ///   - title: The name of the button.
    ///   - displayedText: The analog value, or nil.
    ///   - symbol: The name of the SF Symbol, or nil.
    ///   - fallbackSymbol: The name of the SF Symbol to try when `symbol` does not exist, or nil.
    ///   - fallbackText: The text to show when no symbol exists.
    ///   - active: Whether the button is pressed.
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

    /// The symbol or text, and the value beside it.
    var body: some View {
      HStack(spacing: OJDSpacing.xSmall) {
        if let symbol {
          OJDSystemSymbol(
            name: symbol,
            fallback: fallbackText ?? title,
            fallbackSymbolName: fallbackSymbol
          )
        }
        if symbol == nil { Text(fallbackText ?? title) }
        if let displayedText {
          Text(displayedText).font(.system(.body, design: .monospaced))
        }
      }.font(.body.weight(active ? .semibold : .regular)).lineLimit(1).padding(.horizontal, 7)
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
          [
            active
              ? OJDLocalized.string("ui.inputTest.pressed")
              : OJDLocalized.string("ui.inputTest.released"),
            displayedText,
          ].compactMap { $0 }.joined(separator: ", ")
        )
    }
  }

#endif
