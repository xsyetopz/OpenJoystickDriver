#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension InputTestLiveInputView {
    /// The live input.
    var body: some View { content }

    /// The shoulders, the D-pad, the system and face buttons, the sticks, and any other pressed
    /// button.
    var content: some View {
      let snapshot = liveState.snapshot
      let pressed = snapshot.pressed
      let symbols = InputTestControllerSymbolSet.resolve(for: presentation.glyphFamily)
      return VStack(spacing: 10) {
        shoulderRow(snapshot: snapshot, symbols: symbols)
        Divider()
        HStack(alignment: .center, spacing: 18) {
          dpadCluster(hat: snapshot.hat).frame(maxWidth: .infinity)
          systemCluster(pressed: pressed, symbols: symbols).frame(
            maxWidth: .infinity
          )
          faceButtonCluster(pressed: pressed, symbols: symbols).frame(maxWidth: .infinity)
        }
        Divider()
        HStack(alignment: .top, spacing: 24) {
          InputTestStickView(
            title: OJDLocalized.string("ui.inputTest.leftStick"),
            x: snapshot.leftStick.x.normalized,
            y: snapshot.leftStick.y.normalized,
            clickPresentation: symbols.leftStickClick,
            clickActive: pressed.contains(.leftStickClick)
          )
          InputTestStickView(
            title: OJDLocalized.string("ui.inputTest.rightStick"),
            x: snapshot.rightStick.x.normalized,
            y: snapshot.rightStick.y.normalized,
            clickPresentation: symbols.rightStickClick,
            clickActive: pressed.contains(.rightStickClick)
          )
        }
        let additionalButtons = InputTestButtonPresentation.additionalControls(in: snapshot)
        if !additionalButtons.isEmpty {
          Divider()
          VStack(alignment: .leading, spacing: 8) {
            Text(OJDLocalized.string("ui.inputTest.additionalButtons"))
              .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
              ForEach(additionalButtons, id: \.self) { control in
                InputTestIndicator(
                  title: InputTestButtonPresentation.localizedTitle(for: control),
                  active: true
                )
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
      }.padding(6)
    }

    /// The shoulder buttons and the triggers with their values.
    ///
    /// - Parameters:
    ///   - snapshot: The latest input.
    ///   - symbols: The titles and symbols of the buttons.
    /// - Returns: The row.
    private func shoulderRow(
      snapshot: ControllerState,
      symbols: InputTestControllerSymbolSet
    ) -> some View {
      HStack(spacing: 10) {
        indicator(symbols.leftShoulder, active: snapshot.pressed.contains(.leftShoulder))
        indicator(
          symbols.leftTrigger,
          value: snapshot.leftTrigger.normalized,
          active: snapshot.leftTrigger.normalized > 0.05
            || snapshot.pressed.contains(.leftTrigger)
        )
        indicator(
          symbols.rightTrigger,
          value: snapshot.rightTrigger.normalized,
          active: snapshot.rightTrigger.normalized > 0.05
            || snapshot.pressed.contains(.rightTrigger)
        )
        indicator(symbols.rightShoulder, active: snapshot.pressed.contains(.rightShoulder))
      }
    }

    /// The four directions of the D-pad.
    ///
    /// - Parameter hat: The direction of the hat switch.
    /// - Returns: The cluster.
    private func dpadCluster(hat: HatDirection) -> some View {
      let directions = RuntimePresentation.dpadDirections(hat)
      return VStack(spacing: 6) {
        dpadIndicator(.up, title: "ui.inputTest.dpadUp", active: directions.contains(.up))
        HStack(spacing: 6) {
          dpadIndicator(.left, title: "ui.inputTest.dpadLeft", active: directions.contains(.left))
          dpadIndicator(
            .right,
            title: "ui.inputTest.dpadRight",
            active: directions.contains(.right)
          )
        }
        dpadIndicator(.down, title: "ui.inputTest.dpadDown", active: directions.contains(.down))
      }
    }

    /// One direction of the D-pad.
    ///
    /// - Parameters:
    ///   - direction: The direction.
    ///   - title: The localization key of the direction's name.
    ///   - active: Whether the direction is pressed.
    /// - Returns: The indicator.
    private func dpadIndicator(
      _ direction: RemappingDpadDirection,
      title: String,
      active: Bool
    ) -> some View {
      indicator(
        OJDLocalized.string(title),
        symbol: InputTestButtonPresentation.dpadSymbol(direction),
        active: active
      )
    }

    /// The View, guide and Menu buttons.
    ///
    /// - Parameters:
    ///   - pressed: The pressed controls.
    ///   - symbols: The titles and symbols of the buttons.
    /// - Returns: The cluster.
    @ViewBuilder
    private func systemCluster(
      pressed: Set<Control>,
      symbols: InputTestControllerSymbolSet
    ) -> some View {
      HStack(spacing: 6) {
        indicator(
          symbols.view,
          active: pressed.contains(.back)
        )
        indicator(symbols.guide, active: pressed.contains(.guide))
        indicator(symbols.menu, active: pressed.contains(.start))
      }
    }

    /// The four face buttons.
    ///
    /// - Parameters:
    ///   - pressed: The pressed controls.
    ///   - symbols: The titles and symbols of the buttons.
    /// - Returns: The cluster.
    private func faceButtonCluster(
      pressed: Set<Control>,
      symbols: InputTestControllerSymbolSet
    ) -> some View {
      VStack(spacing: 6) {
        indicator(symbols.northFace, active: pressed.contains(.north))
        HStack(spacing: 6) {
          indicator(symbols.westFace, active: pressed.contains(.west))
          indicator(symbols.eastFace, active: pressed.contains(.east))
        }
        indicator(symbols.southFace, active: pressed.contains(.south))
      }
    }

    /// Returns an indicator of the symbol.
    ///
    /// - Parameters:
    ///   - title: The name of the button.
    ///   - symbol: The name of the SF Symbol.
    ///   - active: Whether the button is pressed.
    /// - Returns: An indicator of the symbol.
    func indicator(_ title: String, symbol: String, active: Bool) -> some View {
      InputTestIndicator(title: title, symbol: symbol, active: active)
    }

    /// Returns an indicator of the button's title and symbols, with the value when it has one.
    ///
    /// - Parameters:
    ///   - presentation: The title and symbols of the button.
    ///   - value: The analog value, or nil.
    ///   - active: Whether the button is pressed.
    /// - Returns: An indicator of the button's title and symbols, with the value when it has one.
    func indicator(
      _ presentation: InputTestControllerSymbolSet.Control,
      value: Float? = nil,
      active: Bool
    ) -> some View {
      InputTestIndicator(
        title: presentation.title,
        displayedText: value.map { OJDLocalized.formatted("ui.inputTest.axisValue", $0) },
        symbol: presentation.symbol,
        fallbackSymbol: presentation.fallbackSymbol,
        fallbackText: presentation.fallbackText,
        active: active
      )
    }
  }

#endif
