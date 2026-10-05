#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct InputTestLiveInputView: View {
    @ObservedObject
    var liveState: InputTestLiveState
    let publishedProfile: VirtualDeviceProfile
    let embedded: Bool

    init(
      liveState: InputTestLiveState,
      publishedProfile: VirtualDeviceProfile,
      embedded: Bool = false
    ) {
      self.liveState = liveState
      self.publishedProfile = publishedProfile
      self.embedded = embedded
    }

  }

  enum InputTestSystemClusterLayout {
    /// Controls the view slot shows: PlayStation Create publishes as Share, not View.
    static func viewControls(labels: ControllerButtonLabels) -> Set<ControlID> {
      labels == .playStation ? [] : [.view]
    }
  }

  struct InputTestAxisValuesView: View {
    @ObservedObject
    var liveState: InputTestLiveState
    let embedded: Bool

    init(liveState: InputTestLiveState, embedded: Bool = false) {
      self.liveState = liveState
      self.embedded = embedded
    }

    @ViewBuilder
    var body: some View {
      if embedded {
        content
      } else {
        GroupBox {
          content
        } label: {
          Text(OJDLocalized.string("inputTest.axisValues")).font(.headline)
        }
      }
    }

    var content: some View {
      let snapshot = liveState.snapshot
      return HStack(alignment: .top, spacing: 14) {
        VStack(spacing: 8) {
          InputTestAxisRow(
            label: OJDLocalized.string("inputTest.leftX"),
            value: snapshot.leftStick.x.normalized,
            signed: true
          )
          InputTestAxisRow(
            label: OJDLocalized.string("inputTest.leftY"),
            value: -snapshot.leftStick.y.normalized,
            signed: true
          )
          InputTestAxisRow(label: "LT", value: snapshot.leftTrigger.normalized, signed: false)
        }
        VStack(spacing: 8) {
          InputTestAxisRow(
            label: OJDLocalized.string("inputTest.rightX"),
            value: snapshot.rightStick.x.normalized,
            signed: true
          )
          InputTestAxisRow(
            label: OJDLocalized.string("inputTest.rightY"),
            value: -snapshot.rightStick.y.normalized,
            signed: true
          )
          InputTestAxisRow(label: "RT", value: snapshot.rightTrigger.normalized, signed: false)
        }
      }.padding(4)
    }
  }

  struct InputTestStickView: View {
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
        }.ojdAccessibilityLabel(title).ojdAccessibilityValue(
          OJDLocalized.formatted("inputTest.axisPair", x, y)
        )
        HStack(spacing: 10) {
          Text(OJDLocalized.formatted("inputTest.axisX", x))
          Text(OJDLocalized.formatted("inputTest.axisY", y))
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

  struct InputTestIndicator: View {
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
            ? OJDLocalized.string("inputTest.pressed")
            : OJDLocalized.string("inputTest.released")
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
          Text(OJDLocalized.formatted("inputTest.axisValue", value)).font(
            .system(.caption, design: .monospaced)
          )
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
        OJDLocalized.formatted("inputTest.axisValue", value)
      )
    }
  }

#endif
